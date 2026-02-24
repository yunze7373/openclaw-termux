import type { SessionSendPolicyConfig } from "./types.base.js";

export type MemoryBackend = "builtin" | "qmd" | "supabase";
export type MemoryCitationsMode = "auto" | "on" | "off";
export type MemoryQmdSearchMode = "query" | "search" | "vsearch";

export type MemoryConfig = {
  backend?: MemoryBackend;
  citations?: MemoryCitationsMode;
  qmd?: MemoryQmdConfig;
  supabase?: MemorySupabaseConfig;
};

export type MemorySupabaseConfig = {
  /** Supabase project URL (overrides SUPABASE_URL env var) */
  url?: string;
  /** Supabase service/anon key (overrides SUPABASE_SERVICE_KEY env var) */
  key?: string;
  /** Table name for memory vectors (default: "memory_vectors") */
  table?: string;
  /** RPC function name for vector search (default: "match_memory_vectors") */
  rpcFunction?: string;
  /** Enable full-text search alongside vector search (default: true) */
  ftsEnabled?: boolean;
  /** RPC function name for full-text search (default: "fts_memory_vectors") */
  ftsFunction?: string;
  /** Enable session transcript indexing (default: false) */
  sessions?: MemorySupabaseSessionConfig;
  /** Sync interval (e.g. "5m", "30s") */
  syncInterval?: string;
  /** Maximum results per search (default: 10) */
  maxResults?: number;
  /** Minimum similarity score threshold (default: 0.5) */
  minScore?: number;
};

export type MemorySupabaseSessionConfig = {
  enabled?: boolean;
  retentionDays?: number;
};

export type MemoryQmdConfig = {
  command?: string;
  mcporter?: MemoryQmdMcporterConfig;
  searchMode?: MemoryQmdSearchMode;
  includeDefaultMemory?: boolean;
  paths?: MemoryQmdIndexPath[];
  sessions?: MemoryQmdSessionConfig;
  update?: MemoryQmdUpdateConfig;
  limits?: MemoryQmdLimitsConfig;
  scope?: SessionSendPolicyConfig;
};

export type MemoryQmdMcporterConfig = {
  /**
   * Route QMD searches through mcporter (MCP runtime) instead of spawning `qmd` per query.
   * Requires:
   * - `mcporter` installed and on PATH
   * - A configured mcporter server that runs `qmd mcp` with `lifecycle: keep-alive`
   */
  enabled?: boolean;
  /** mcporter server name (defaults to "qmd") */
  serverName?: string;
  /** Start the mcporter daemon automatically (defaults to true when enabled). */
  startDaemon?: boolean;
};

export type MemoryQmdIndexPath = {
  path: string;
  name?: string;
  pattern?: string;
};

export type MemoryQmdSessionConfig = {
  enabled?: boolean;
  exportDir?: string;
  retentionDays?: number;
};

export type MemoryQmdUpdateConfig = {
  interval?: string;
  debounceMs?: number;
  onBoot?: boolean;
  waitForBootSync?: boolean;
  embedInterval?: string;
  commandTimeoutMs?: number;
  updateTimeoutMs?: number;
  embedTimeoutMs?: number;
};

export type MemoryQmdLimitsConfig = {
  maxResults?: number;
  maxSnippetChars?: number;
  maxInjectedChars?: number;
  timeoutMs?: number;
};
