import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import dotenv from "dotenv";

import { resolveAgentDir, resolveAgentWorkspaceDir } from "../agents/agent-scope.js";
import type { ResolvedMemorySearchConfig } from "../agents/memory-search.js";
import { resolveMemorySearchConfig } from "../agents/memory-search.js";
import type { MoltbotConfig } from "../config/config.js";
import { createSubsystemLogger } from "../logging/subsystem.js";
import { resolveUserPath } from "../utils.js";
import {
  createEmbeddingProvider,
  type EmbeddingProvider,
  type EmbeddingProviderResult,
} from "./embeddings.js";
import {
  buildFileEntry,
  chunkMarkdown,
  hashText,
  listMemoryFiles,
  type MemoryChunk,
  type MemoryFileEntry,
  normalizeRelPath,
  isMemoryPath,
} from "./internal.js";

const log = createSubsystemLogger("memory-supabase");

// Helper to interact with Supabase via REST to avoid adding npm dependencies
class SupabaseClient {
  constructor(private url: string, private key: string) {}

  async rpc(name: string, params: any) {
    const res = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "ApiKey": this.key,
        "Authorization": `Bearer ${this.key}`,
      },
      body: JSON.stringify(params),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase RPC ${name} failed: ${res.status} ${txt}`);
    }
    return await res.json();
  }

  async insert(table: string, rows: any[]) {
    if (rows.length === 0) return;
    const res = await fetch(`${this.url}/rest/v1/${table}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "ApiKey": this.key,
        "Authorization": `Bearer ${this.key}`,
        "Prefer": "return=minimal",
      },
      body: JSON.stringify(rows),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase INSERT ${table} failed: ${res.status} ${txt}`);
    }
  }

  async delete(table: string, match: Record<string, string>) {
    const query = new URLSearchParams();
    for (const [k, v] of Object.entries(match)) {
      query.append(k, `eq.${v}`);
    }
    const res = await fetch(`${this.url}/rest/v1/${table}?${query.toString()}`, {
      method: "DELETE",
      headers: {
        "ApiKey": this.key,
        "Authorization": `Bearer ${this.key}`,
      },
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Supabase DELETE ${table} failed: ${res.status} ${txt}`);
    }
  }
}

export class SupabaseMemoryManager {
  private readonly cfg: MoltbotConfig;
  private readonly agentId: string;
  private readonly workspaceDir: string;
  private readonly settings: ResolvedMemorySearchConfig;
  private provider: EmbeddingProvider;
  private supabase: SupabaseClient | null = null;
  private tableName: string = "memory_vectors";
  private initialized = false;

  constructor(params: {
    cacheKey: string;
    cfg: MoltbotConfig;
    agentId: string;
    workspaceDir: string;
    settings: ResolvedMemorySearchConfig;
    providerResult: EmbeddingProviderResult;
  }) {
    this.cfg = params.cfg;
    this.agentId = params.agentId;
    this.workspaceDir = params.workspaceDir;
    this.settings = params.settings;
    this.provider = params.providerResult.provider;

    // --- AUTO-LOAD CONFIGURATION (Fix for Termux/PM2) ---
    const home = process.env.HOME || "/data/data/com.termux/files/home";
    
    // 1. Load ~/.embedding-config (Ollama & Dimensions)
    const embeddingConfigPath = path.join(home, ".embedding-config");
    if (fsSync.existsSync(embeddingConfigPath)) {
      const result = dotenv.config({ path: embeddingConfigPath });
      if (result.parsed) {
        // Manually override if not already set, to ensure precedence
        for (const [k, v] of Object.entries(result.parsed)) {
            if (!process.env[k]) process.env[k] = v;
        }
      }
    }

    // 2. Load ~/clawd/moltbot-supabase-memory-config.env (Supabase Creds)
    // Try multiple possible locations for robustness
    const clawdConfigPaths = [
        path.join(home, "clawd", "moltbot-supabase-memory-config.env"),
        path.join(this.workspaceDir, "..", "..", "moltbot-supabase-memory-config.env") // In case we are deep in structure
    ];

    for (const cfgPath of clawdConfigPaths) {
        if (fsSync.existsSync(cfgPath)) {
            const result = dotenv.config({ path: cfgPath });
            if (result.parsed) {
                 // Map Supabase variables from this specific file format to standard env vars
                 if (result.parsed.SUPABASE_ANON_KEY && !process.env.SUPABASE_KEY) {
                     process.env.SUPABASE_KEY = result.parsed.SUPABASE_ANON_KEY;
                 }
                 if (result.parsed.SUPABASE_MEMORY_TABLE && !process.env.MEMORY_TABLE) {
                     process.env.MEMORY_TABLE = result.parsed.SUPABASE_MEMORY_TABLE;
                 }
                 // Load others
                 for (const [k, v] of Object.entries(result.parsed)) {
                    if (!process.env[k]) process.env[k] = v;
                }
                break; // Found one, stop looking
            }
        }
    }
    // ----------------------------------------------------

    const url = process.env.SUPABASE_URL;
    // Prioritize Service Key (for RLS bypass if needed), then Anon, then generic Key
    const key = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_KEY;
    this.tableName = process.env.MEMORY_TABLE || process.env.SUPABASE_MEMORY_TABLE || "memory_vectors";
    
    if (url && key) {
      this.supabase = new SupabaseClient(url, key);
      log.info(`Initialized Supabase wrapper for memory (Agent: ${this.agentId})`);
      log.debug(`Supabase Config: URL=${url}, Table=${this.tableName}`);
    } else {
      log.warn("Supabase credentials (SUPABASE_URL, SUPABASE_KEY) not found. Memory search will fail.");
    }
  }

  async search(
    query: string,
    opts?: {
      maxResults?: number;
      minScore?: number;
      sessionKey?: string;
    },
  ): Promise<any[]> {
    if (!this.supabase) return [];
    
    const limit = opts?.maxResults ?? this.settings.query.maxResults ?? 10;
    const minScore = opts?.minScore ?? this.settings.query.minScore ?? 0.7;

    try {
      const embedding = await this.provider.embedQuery(query);
      const data = await this.supabase.rpc("match_memory_vectors", {
        query_embedding: embedding,
        match_count: limit,
      });

      if (!Array.isArray(data)) return [];

      return data
        .map((row: any) => ({
          path: row.path,
          startLine: 0, // Not stored in simplified schema, or need to extract from metadata
          endLine: 0,
          score: row.similarity,
          snippet: row.text,
          source: row.metadata?.source || "memory",
          id: row.id
        }))
        .filter(r => r.score >= minScore);

    } catch (err) {
      log.error(`Supabase search failed: ${err}`);
      return [];
    }
  }

  async sync(params?: { reason?: string; force?: boolean }): Promise<void> {
    if (!this.supabase) return;
    log.info(`Syncing memory to Supabase (reason: ${params?.reason})...`);

    // 1. List files
    const files = await listMemoryFiles(this.workspaceDir);
    
    // 2. Process each file
    for (const file of files) {
      try {
        const entry = await buildFileEntry(file, this.workspaceDir);
        // Clean existing
        await this.supabase.delete(this.tableName, { path: entry.path });

        // Chunk and Embed
        const content = await fs.readFile(entry.absPath, "utf-8");
        const chunks = chunkMarkdown(content, this.settings.chunking);
        
        if (chunks.length === 0) continue;

        // Note: Simple serial embedding for now to avoid complexity. 
        // Can be optimized to batching if provider supports it.
        const texts = chunks.map(c => c.text);
        let embeddings: number[][] = [];
        
        try {
           embeddings = await this.provider.embedBatch(texts);
        } catch {
           // Fallback to serial
           for (const text of texts) {
             embeddings.push(await this.provider.embedQuery(text));
           }
        }

        const rows = chunks.map((chunk, i) => ({
           path: entry.path,
           text: chunk.text,
           embedding: embeddings[i],
           source: "memory",
           metadata: {
             hash: chunk.hash,
             startLine: chunk.startLine,
             endLine: chunk.endLine,
             source: "memory"
           }
        }));

        await this.supabase.insert(this.tableName, rows);
        log.debug(`Synced ${entry.path} (${rows.length} chunks) to Supabase`);
        
      } catch (err) {
        log.error(`Failed to sync file ${file}: ${err}`);
      }
    }
    log.info("Supabase sync completed.");
  }

  // API Compatibility Stubs
  
  async warmSession(sessionKey?: string): Promise<void> {
    // No-op
  }

  async readFile(params: {
    relPath: string;
    from?: number;
    lines?: number;
  }): Promise<{ text: string; path: string }> {
    const relPath = normalizeRelPath(params.relPath);
    if (!relPath || !isMemoryPath(relPath)) throw new Error("path required");
    const absPath = path.resolve(this.workspaceDir, relPath);
    const content = await fs.readFile(absPath, "utf-8");
    return { text: content, path: relPath }; // Simplified
  }

  status(): any {
     return {
       files: 0,
       chunks: 0,
       dirty: false,
       workspaceDir: this.workspaceDir,
       dbPath: "supabase://remote",
       provider: this.provider.id,
       model: this.provider.model,
       sources: ["memory"],
       sourceCounts: [],
       vector: { enabled: true, available: true, driver: "supabase" }
     };
  }

  async probeVectorAvailability(): Promise<boolean> {
    return !!this.supabase;
  }

  async probeEmbeddingAvailability(): Promise<{ ok: boolean; error?: string }> {
    return { ok: true };
  }

  async close(): Promise<void> {
    // No-op
  }
}
