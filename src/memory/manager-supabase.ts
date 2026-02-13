import fs from "node:fs/promises";
import path from "node:path";

import type { OpenClawConfig } from "../config/config.js";
import type {
  ResolvedMemoryBackendConfig,
  ResolvedSupabaseConfig,
} from "./backend-config.js";
import type {
  MemoryEmbeddingProbeResult,
  MemoryProviderStatus,
  MemorySearchManager,
  MemorySearchResult,
  MemorySource,
  MemorySyncProgressUpdate,
} from "./types.js";
import { resolveAgentWorkspaceDir } from "../agents/agent-scope.js";
import { resolveMemorySearchConfig, type ResolvedMemorySearchConfig } from "../agents/memory-search.js";
import { createSubsystemLogger } from "../logging/subsystem.js";
import {
  buildFileEntry,
  chunkMarkdown,
  isMemoryPath,
  listMemoryFiles,
  normalizeRelPath,
} from "./internal.js";
import {
  listSessionFilesForAgent,
  buildSessionEntry,
} from "./session-files.js";
import {
  createEmbeddingProvider,
  type EmbeddingProvider,
} from "./embeddings.js";

const log = createSubsystemLogger("memory-supabase");

// ---------------------------------------------------------------------------
// REST client for Supabase (no npm dependency)
// ---------------------------------------------------------------------------

class SupabaseRestClient {
  constructor(
    private readonly url: string,
    private readonly key: string,
  ) { }

  private headers(): Record<string, string> {
    return {
      "Content-Type": "application/json",
      ApiKey: this.key,
      Authorization: `Bearer ${this.key}`,
    };
  }

  async rpc(name: string, params: unknown): Promise<unknown> {
    const res = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify(params),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase RPC ${name} failed: ${res.status} ${txt}`);
    }
    return await res.json();
  }

  async upsert(table: string, rows: unknown[]): Promise<void> {
    if (rows.length === 0) return;
    const res = await fetch(`${this.url}/rest/v1/${table}`, {
      method: "POST",
      headers: {
        ...this.headers(),
        Prefer: "resolution=merge-duplicates",
      },
      body: JSON.stringify(rows),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase UPSERT ${table} failed: ${res.status} ${txt}`);
    }
  }

  async insert(table: string, rows: unknown[]): Promise<void> {
    if (rows.length === 0) return;
    const res = await fetch(`${this.url}/rest/v1/${table}`, {
      method: "POST",
      headers: {
        ...this.headers(),
        Prefer: "return=minimal",
      },
      body: JSON.stringify(rows),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase INSERT ${table} failed: ${res.status} ${txt}`);
    }
  }

  async delete(table: string, match: Record<string, string>): Promise<void> {
    const query = new URLSearchParams();
    for (const [k, v] of Object.entries(match)) {
      query.append(k, `eq.${v}`);
    }
    const res = await fetch(`${this.url}/rest/v1/${table}?${query.toString()}`, {
      method: "DELETE",
      headers: this.headers(),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase DELETE ${table} failed: ${res.status} ${txt}`);
    }
  }

  async select(table: string, params: string): Promise<unknown[]> {
    const res = await fetch(`${this.url}/rest/v1/${table}?${params}`, {
      method: "GET",
      headers: this.headers(),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase SELECT ${table} failed: ${res.status} ${txt}`);
    }
    return (await res.json()) as unknown[];
  }
}

// ---------------------------------------------------------------------------
// Hash index for incremental sync
// ---------------------------------------------------------------------------

type ChunkHashRecord = {
  path: string;
  fileHash: string;
  chunkHashes: string[];
};

// ---------------------------------------------------------------------------
// SupabaseMemoryManager — implements MemorySearchManager
// ---------------------------------------------------------------------------

export class SupabaseMemoryManager implements MemorySearchManager {
  private readonly cfg: OpenClawConfig;
  private readonly agentId: string;
  private readonly workspaceDir: string;
  private readonly settings: ResolvedMemorySearchConfig;
  private readonly supabaseConfig: ResolvedSupabaseConfig;
  private readonly client: SupabaseRestClient;
  private provider: EmbeddingProvider;

  // Incremental sync state (in-memory)
  private readonly syncedHashes = new Map<string, ChunkHashRecord>();
  private syncTimer: ReturnType<typeof setInterval> | null = null;
  private closed = false;

  // -----------------------------------------------------------------------
  // Factory
  // -----------------------------------------------------------------------

  static async create(params: {
    cfg: OpenClawConfig;
    agentId: string;
    resolved: ResolvedMemoryBackendConfig;
  }): Promise<SupabaseMemoryManager | null> {
    const supabaseConfig = params.resolved.supabase;
    if (!supabaseConfig) {
      return null;
    }

    const settings = resolveMemorySearchConfig(params.cfg, params.agentId);
    if (!settings) {
      return null;
    }

    // Create embedding provider using OpenClaw's standard provider system
    let providerResult: { provider: EmbeddingProvider };
    try {
      providerResult = await createEmbeddingProvider({
        config: params.cfg,
        provider: settings.provider,
        model: settings.model,
        fallback: settings.fallback,
        remote: settings.remote,
        local: settings.local,
      });
    } catch (err) {
      log.error(`Failed to create embedding provider: ${String(err)}`);
      return null;
    }

    const workspaceDir = resolveAgentWorkspaceDir(params.cfg, params.agentId);
    const manager = new SupabaseMemoryManager({
      cfg: params.cfg,
      agentId: params.agentId,
      workspaceDir,
      settings,
      supabaseConfig,
      provider: providerResult.provider,
    });

    // Start periodic sync if configured
    if (supabaseConfig.syncIntervalMs > 0) {
      manager.syncTimer = setInterval(() => {
        void manager.sync({ reason: "interval" }).catch((err) => {
          log.warn(`Periodic sync failed: ${String(err)}`);
        });
      }, supabaseConfig.syncIntervalMs);
    }

    // Initial sync on creation
    void manager.sync({ reason: "boot" }).catch((err) => {
      log.warn(`Initial sync failed: ${String(err)}`);
    });

    log.info(`Supabase memory manager initialized (agent: ${params.agentId})`);
    return manager;
  }

  private constructor(params: {
    cfg: OpenClawConfig;
    agentId: string;
    workspaceDir: string;
    settings: ResolvedMemorySearchConfig;
    supabaseConfig: ResolvedSupabaseConfig;
    provider: EmbeddingProvider;
  }) {
    this.cfg = params.cfg;
    this.agentId = params.agentId;
    this.workspaceDir = params.workspaceDir;
    this.settings = params.settings;
    this.supabaseConfig = params.supabaseConfig;
    this.provider = params.provider;
    this.client = new SupabaseRestClient(
      params.supabaseConfig.url,
      params.supabaseConfig.key,
    );
  }

  // -----------------------------------------------------------------------
  // Search — hybrid (vector + FTS) with dedup
  // -----------------------------------------------------------------------

  async search(
    query: string,
    opts?: { maxResults?: number; minScore?: number; sessionKey?: string },
  ): Promise<MemorySearchResult[]> {
    const trimmed = query.trim();
    if (!trimmed) return [];

    const limit = Math.min(
      opts?.maxResults ?? this.supabaseConfig.maxResults,
      this.supabaseConfig.maxResults,
    );
    const minScore = opts?.minScore ?? this.supabaseConfig.minScore;

    // Determine which sources to search
    const sources = this.settings.sources ?? ["memory"];

    try {
      // Vector search
      const embedding = await this.provider.embedQuery(trimmed);
      const vectorResults = await this.vectorSearch(embedding, limit * 2, sources);

      // Full-text search (if enabled)
      let ftsResults: RawSearchRow[] = [];
      if (this.supabaseConfig.ftsEnabled) {
        try {
          ftsResults = await this.ftsSearch(trimmed, limit * 2, sources);
        } catch (err) {
          log.debug(`FTS search failed, using vector only: ${String(err)}`);
        }
      }

      // Hybrid merge + dedup
      const merged = this.hybridMerge(vectorResults, ftsResults, limit);

      // Filter by minScore and convert to MemorySearchResult
      return merged
        .filter((r) => r.score >= minScore)
        .slice(0, limit)
        .map((r) => ({
          path: r.path,
          startLine: r.startLine,
          endLine: r.endLine,
          score: r.score,
          snippet: r.snippet,
          source: r.source as MemorySource,
        }));
    } catch (err) {
      log.error(`Supabase search failed: ${String(err)}`);
      return [];
    }
  }

  private async vectorSearch(
    embedding: number[],
    limit: number,
    sources: string[],
  ): Promise<RawSearchRow[]> {
    const data = (await this.client.rpc(this.supabaseConfig.rpcFunction, {
      query_embedding: embedding,
      match_count: limit,
      filter_sources: sources.length > 0 ? sources : undefined,
    })) as Array<{
      id?: number;
      path?: string;
      content?: string;
      text?: string;
      similarity?: number;
      metadata?: Record<string, unknown>;
    }>;

    if (!Array.isArray(data)) return [];

    return data.map((row) => ({
      id: String(row.id ?? ""),
      path: String(row.path ?? ""),
      snippet: String(row.content ?? row.text ?? ""),
      score: Number(row.similarity ?? 0),
      startLine: Number((row.metadata as any)?.startLine ?? 0),
      endLine: Number((row.metadata as any)?.endLine ?? 0),
      source: String((row.metadata as any)?.source ?? "memory"),
      searchType: "vector" as const,
    }));
  }

  private async ftsSearch(
    query: string,
    limit: number,
    sources: string[],
  ): Promise<RawSearchRow[]> {
    try {
      const data = (await this.client.rpc(this.supabaseConfig.ftsFunction, {
        search_query: query,
        match_count: limit,
        filter_sources: sources.length > 0 ? sources : undefined,
      })) as Array<{
        id?: number;
        path?: string;
        content?: string;
        text?: string;
        rank?: number;
        metadata?: Record<string, unknown>;
      }>;

      if (!Array.isArray(data)) return [];

      return data.map((row) => ({
        id: String(row.id ?? ""),
        path: String(row.path ?? ""),
        snippet: String(row.content ?? row.text ?? ""),
        score: Math.max(0, 1 - Math.abs(Number(row.rank ?? 0))), // BM25 rank → 0-1 score
        startLine: Number((row.metadata as any)?.startLine ?? 0),
        endLine: Number((row.metadata as any)?.endLine ?? 0),
        source: String((row.metadata as any)?.source ?? "memory"),
        searchType: "fts" as const,
      }));
    } catch {
      return [];
    }
  }

  /** Merge vector and FTS results with weighted scoring and dedup */
  private hybridMerge(
    vectorResults: RawSearchRow[],
    ftsResults: RawSearchRow[],
    limit: number,
  ): RawSearchRow[] {
    const hybridCfg = this.settings.query.hybrid;
    const vectorWeight = hybridCfg.enabled ? hybridCfg.vectorWeight : 1;
    const textWeight = hybridCfg.enabled ? hybridCfg.textWeight : 0;

    // Build dedup map keyed on path+startLine
    const merged = new Map<string, RawSearchRow>();

    for (const row of vectorResults) {
      const key = `${row.path}:${row.startLine}`;
      const existing = merged.get(key);
      const weightedScore = row.score * vectorWeight;
      if (!existing || weightedScore > existing.score) {
        merged.set(key, { ...row, score: weightedScore });
      }
    }

    for (const row of ftsResults) {
      const key = `${row.path}:${row.startLine}`;
      const existing = merged.get(key);
      const weightedScore = row.score * textWeight;
      if (existing) {
        // Combine scores for entries found in both searches
        existing.score = existing.score + weightedScore;
      } else {
        merged.set(key, { ...row, score: weightedScore });
      }
    }

    return Array.from(merged.values())
      .sort((a, b) => b.score - a.score)
      .slice(0, limit);
  }

  // -----------------------------------------------------------------------
  // Sync — incremental, hash-based
  // -----------------------------------------------------------------------

  async sync(params?: {
    reason?: string;
    force?: boolean;
    progress?: (update: MemorySyncProgressUpdate) => void;
  }): Promise<void> {
    if (this.closed) return;

    log.info(`Syncing memory to Supabase (reason: ${params?.reason ?? "manual"})...`);

    // 1. Collect all files to sync
    const memoryFiles = await listMemoryFiles(
      this.workspaceDir,
      this.settings.extraPaths,
    );

    // 2. Collect session files if enabled
    let sessionFiles: string[] = [];
    if (
      this.supabaseConfig.sessions.enabled &&
      this.settings.sources.includes("sessions")
    ) {
      sessionFiles = await listSessionFilesForAgent(this.agentId);
    }

    const totalFiles = memoryFiles.length + sessionFiles.length;
    let processed = 0;

    params?.progress?.({ completed: 0, total: totalFiles, label: "Scanning files…" });

    // 3. Sync memory files (incremental)
    for (const file of memoryFiles) {
      try {
        await this.syncFile(file, "memory", params?.force);
      } catch (err) {
        log.warn(`Failed to sync ${file}: ${String(err)}`);
      }
      processed++;
      params?.progress?.({
        completed: processed,
        total: totalFiles,
        label: `Syncing ${path.basename(file)}`,
      });
    }

    // 4. Sync session files (incremental)
    for (const file of sessionFiles) {
      try {
        await this.syncSessionFile(file, params?.force);
      } catch (err) {
        log.debug(`Failed to sync session ${file}: ${String(err)}`);
      }
      processed++;
      params?.progress?.({
        completed: processed,
        total: totalFiles,
        label: `Syncing session ${path.basename(file)}`,
      });
    }

    // 5. Clean up deleted files
    await this.cleanupDeletedFiles(memoryFiles);

    log.info(`Supabase sync completed (${processed} files processed).`);
    params?.progress?.({
      completed: totalFiles,
      total: totalFiles,
      label: "Sync complete",
    });
  }

  /** Sync a single memory file with incremental hash check */
  private async syncFile(
    absPath: string,
    source: MemorySource,
    force?: boolean,
  ): Promise<void> {
    const entry = await buildFileEntry(absPath, this.workspaceDir);

    // Incremental check: skip if file hash hasn't changed
    const cached = this.syncedHashes.get(entry.path);
    if (!force && cached && cached.fileHash === entry.hash) {
      log.debug(`Skipping unchanged: ${entry.path}`);
      return;
    }

    const content = await fs.readFile(absPath, "utf-8");
    const chunks = chunkMarkdown(content, this.settings.chunking);

    if (chunks.length === 0) return;

    // Vector dedup: check which chunks are actually new
    const newChunks = cached
      ? chunks.filter((ch) => !cached.chunkHashes.includes(ch.hash))
      : chunks;

    if (newChunks.length === 0 && !force) {
      // All chunks the same, just update file hash
      this.syncedHashes.set(entry.path, {
        path: entry.path,
        fileHash: entry.hash,
        chunkHashes: chunks.map((c) => c.hash),
      });
      log.debug(`All chunks unchanged: ${entry.path}`);
      return;
    }

    // Delete existing chunks for this path, then re-insert all
    await this.client.delete(this.supabaseConfig.table, { path: entry.path });

    // Generate embeddings in batch
    const texts = chunks.map((c) => c.text);
    let embeddings: number[][];
    try {
      embeddings = await this.provider.embedBatch(texts);
    } catch {
      // Fallback to serial
      embeddings = [];
      for (const text of texts) {
        embeddings.push(await this.provider.embedQuery(text));
      }
    }

    // Build rows for upsert
    const rows = chunks.map((chunk, i) => ({
      path: entry.path,
      content: chunk.text,
      embedding: embeddings[i],
      metadata: {
        hash: chunk.hash,
        fileHash: entry.hash,
        startLine: chunk.startLine,
        endLine: chunk.endLine,
        source,
        agentId: this.agentId,
      },
    }));

    await this.client.insert(this.supabaseConfig.table, rows);

    // Update hash cache
    this.syncedHashes.set(entry.path, {
      path: entry.path,
      fileHash: entry.hash,
      chunkHashes: chunks.map((c) => c.hash),
    });

    log.debug(`Synced ${entry.path} (${rows.length} chunks, ${newChunks.length} new)`);
  }

  /** Sync a session transcript file */
  private async syncSessionFile(absPath: string, force?: boolean): Promise<void> {
    const entry = await buildSessionEntry(absPath);
    if (!entry || !entry.content.trim()) return;

    const cached = this.syncedHashes.get(entry.path);
    if (!force && cached && cached.fileHash === entry.hash) {
      return;
    }

    const chunks = chunkMarkdown(entry.content, this.settings.chunking);
    if (chunks.length === 0) return;

    // Delete and re-insert
    await this.client.delete(this.supabaseConfig.table, { path: entry.path });

    const texts = chunks.map((c) => c.text);
    let embeddings: number[][];
    try {
      embeddings = await this.provider.embedBatch(texts);
    } catch {
      embeddings = [];
      for (const text of texts) {
        embeddings.push(await this.provider.embedQuery(text));
      }
    }

    const rows = chunks.map((chunk, i) => ({
      path: entry.path,
      content: chunk.text,
      embedding: embeddings[i],
      metadata: {
        hash: chunk.hash,
        fileHash: entry.hash,
        startLine: chunk.startLine,
        endLine: chunk.endLine,
        source: "sessions",
        agentId: this.agentId,
      },
    }));

    await this.client.insert(this.supabaseConfig.table, rows);

    this.syncedHashes.set(entry.path, {
      path: entry.path,
      fileHash: entry.hash,
      chunkHashes: chunks.map((c) => c.hash),
    });

    log.debug(`Synced session ${entry.path} (${rows.length} chunks)`);
  }

  /** Remove chunks for files that no longer exist */
  private async cleanupDeletedFiles(currentFiles: string[]): Promise<void> {
    const currentPaths = new Set<string>();
    for (const file of currentFiles) {
      const rel = path.relative(this.workspaceDir, file).replace(/\\/g, "/");
      currentPaths.add(rel);
    }

    for (const [cachedPath] of this.syncedHashes) {
      // Skip session paths (managed separately)
      if (cachedPath.startsWith("sessions/")) continue;

      if (!currentPaths.has(cachedPath)) {
        try {
          await this.client.delete(this.supabaseConfig.table, { path: cachedPath });
          this.syncedHashes.delete(cachedPath);
          log.debug(`Cleaned up deleted file: ${cachedPath}`);
        } catch (err) {
          log.warn(`Failed to cleanup ${cachedPath}: ${String(err)}`);
        }
      }
    }
  }

  // -----------------------------------------------------------------------
  // Read file
  // -----------------------------------------------------------------------

  async readFile(params: {
    relPath: string;
    from?: number;
    lines?: number;
  }): Promise<{ text: string; path: string }> {
    const relPath = normalizeRelPath(params.relPath);
    if (!relPath || !isMemoryPath(relPath)) {
      throw new Error("path required");
    }
    const absPath = path.resolve(this.workspaceDir, relPath);
    const stat = await fs.lstat(absPath);
    if (stat.isSymbolicLink() || !stat.isFile()) {
      throw new Error("path required");
    }
    const content = await fs.readFile(absPath, "utf-8");
    if (!params.from && !params.lines) {
      return { text: content, path: relPath };
    }
    const allLines = content.split("\n");
    const start = Math.max(1, params.from ?? 1);
    const count = Math.max(1, params.lines ?? allLines.length);
    const slice = allLines.slice(start - 1, start - 1 + count);
    return { text: slice.join("\n"), path: relPath };
  }

  // -----------------------------------------------------------------------
  // Status, probes, close
  // -----------------------------------------------------------------------

  status(): MemoryProviderStatus {
    return {
      backend: "supabase",
      provider: this.provider.id,
      model: this.provider.model,
      requestedProvider: this.settings.provider,
      files: this.syncedHashes.size,
      chunks: Array.from(this.syncedHashes.values()).reduce(
        (sum, entry) => sum + entry.chunkHashes.length,
        0,
      ),
      dirty: false,
      workspaceDir: this.workspaceDir,
      dbPath: `supabase://${this.supabaseConfig.url}/${this.supabaseConfig.table}`,
      sources: this.settings.sources as MemorySource[],
      sourceCounts: [],
      vector: { enabled: true, available: true },
      fts: { enabled: this.supabaseConfig.ftsEnabled, available: true },
      custom: {
        supabase: {
          table: this.supabaseConfig.table,
          rpcFunction: this.supabaseConfig.rpcFunction,
          ftsEnabled: this.supabaseConfig.ftsEnabled,
          sessionsEnabled: this.supabaseConfig.sessions.enabled,
        },
      },
    };
  }

  async probeEmbeddingAvailability(): Promise<MemoryEmbeddingProbeResult> {
    try {
      await this.provider.embedQuery("test");
      return { ok: true };
    } catch (err) {
      return { ok: false, error: String(err) };
    }
  }

  async probeVectorAvailability(): Promise<boolean> {
    try {
      await this.client.rpc(this.supabaseConfig.rpcFunction, {
        query_embedding: [],
        match_count: 1,
      });
      return true;
    } catch {
      return false;
    }
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

type RawSearchRow = {
  id: string;
  path: string;
  snippet: string;
  score: number;
  startLine: number;
  endLine: number;
  source: string;
  searchType: "vector" | "fts";
};
