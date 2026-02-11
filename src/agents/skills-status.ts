import path from "node:path";
import type { OpenClawConfig } from "../config/config.js";
import { CONFIG_DIR } from "../utils.js";
import {
  hasBinary,
  isBundledSkillAllowed,
  isConfigPathTruthy,
  loadWorkspaceSkillEntries,
  resolveBundledAllowlist,
  resolveConfigPath,
  resolveSkillConfig,
  resolveSkillsInstallPreferences,
  type SkillEntry,
  type SkillEligibilityContext,
  type SkillInstallSpec,
  type SkillsInstallPreferences,
} from "./skills.js";
import { resolveBundledSkillsContext } from "./skills/bundled-context.js";

export type SkillStatusConfigCheck = {
  path: string;
  value: unknown;
  satisfied: boolean;
};

export type SkillInstallOption = {
  id: string;
  kind: SkillInstallSpec["kind"];
  label: string;
  bins: string[];
};

export type SkillStatusEntry = {
  name: string;
  description: string;
  source: string;
  bundled: boolean;
  filePath: string;
  baseDir: string;
  skillKey: string;
  primaryEnv?: string;
  emoji?: string;
  homepage?: string;
  always: boolean;
  disabled: boolean;
  blockedByAllowlist: boolean;
  eligible: boolean;
  requirements: {
    bins: string[];
    anyBins: string[];
    env: string[];
    config: string[];
    os: string[];
  };
  missing: {
    bins: string[];
    anyBins: string[];
    env: string[];
    config: string[];
    os: string[];
  };
  configChecks: SkillStatusConfigCheck[];
  install: SkillInstallOption[];
};

export type SkillStatusReport = {
  workspaceDir: string;
  managedSkillsDir: string;
  skills: SkillStatusEntry[];
};

function resolveSkillKey(entry: SkillEntry): string {
  return entry.metadata?.skillKey ?? entry.skill.name;
}

function selectPreferredInstallSpec(
  install: SkillInstallSpec[],
  prefs: SkillsInstallPreferences,
): { spec: SkillInstallSpec; index: number } | undefined {
  if (install.length === 0) {
    return undefined;
  }
  const indexed = install.map((spec, index) => ({ spec, index }));
  const findKind = (kind: SkillInstallSpec["kind"]) =>
    indexed.find((item) => item.spec.kind === kind);

  const brewSpec = findKind("brew");
  const nodeSpec = findKind("node");
  const goSpec = findKind("go");
  const uvSpec = findKind("uv");
  const pipSpec = findKind("pip");
  const cargoSpec = findKind("cargo");

  const isTermuxAndroid = process.platform === "android" || Boolean(process.env.TERMUX_VERSION) || (process.env.PREFIX || "").includes("com.termux") || Boolean(process.env.ANDROID_ROOT);
  if (isTermuxAndroid) {
    // Termux often lacks brew and treats "android" as "linux" for most CLI tooling.
    // Prefer npm/go/pip/cargo installers when available.
    if (cargoSpec) {
      return cargoSpec;
    }
    if (nodeSpec) {
      return nodeSpec;
    }
    if (pipSpec) {
      return pipSpec;
    }
    if (goSpec) {
      return goSpec;
    }
    if (uvSpec) {
      return uvSpec;
    }
    if (brewSpec) {
      return brewSpec;
    }
    return indexed[0];
  }

  if (prefs.preferBrew && hasBinary("brew") && brewSpec) {
    return brewSpec;
  }
  if (cargoSpec) {
    return cargoSpec;
  }
  if (uvSpec) {
    return uvSpec;
  }
  if (pipSpec) {
    return pipSpec;
  }
  if (nodeSpec) {
    return nodeSpec;
  }
  if (brewSpec) {
    return brewSpec;
  }
  if (goSpec) {
    return goSpec;
  }
  return indexed[0];
}

function resolveSkillOsFilter(): { platform: NodeJS.Platform; compatible: NodeJS.Platform[] } {
  const raw = process.platform;
  const isTermuxAndroid = raw === "android" || Boolean(process.env.TERMUX_VERSION);
  if (!isTermuxAndroid) {
    return { platform: raw, compatible: [raw] };
  }
  // Skills typically declare linux, not android, but Termux should accept both.
  return { platform: "linux", compatible: ["linux", "android"] };
}

function normalizeInstallOptions(
  entry: SkillEntry,
  prefs: SkillsInstallPreferences,
): SkillInstallOption[] {
  const install = entry.metadata?.install ?? [];
  if (install.length === 0) {
    return [];
  }

  const { compatible } = resolveSkillOsFilter();
  const filtered = install.filter((spec) => {
    const osList = spec.os ?? [];
    return osList.length === 0 || compatible.some((os) => osList.includes(os));
  });
  if (filtered.length === 0) {
    return [];
  }

  const toOption = (spec: SkillInstallSpec, index: number): SkillInstallOption => {
    const id = (spec.id ?? `${spec.kind}-${index}`).trim();
    const bins = spec.bins ?? [];
    let label = (spec.label ?? "").trim();
    if (spec.kind === "node" && spec.package) {
      label = `Install ${spec.package} (${prefs.nodeManager})`;
    }
    if (!label) {
      if (spec.kind === "brew" && spec.formula) {
        label = `Install ${spec.formula} (brew)`;
      } else if (spec.kind === "node" && spec.package) {
        label = `Install ${spec.package} (${prefs.nodeManager})`;
      } else if (spec.kind === "go" && spec.module) {
        label = `Install ${spec.module} (go)`;
      } else if (spec.kind === "uv" && spec.package) {
        label = `Install ${spec.package} (uv)`;
      } else if (spec.kind === "pip" && spec.package) {
        label = `Install ${spec.package} (pip)`;
      } else if (spec.kind === "cargo" && spec.package) {
        label = `Install ${spec.package} (cargo)`;
      } else if (spec.kind === "download" && spec.url) {
        const url = spec.url.trim();
        const last = url.split("/").pop();
        label = `Download ${last && last.length > 0 ? last : url}`;
      } else {
        label = "Run installer";
      }
    }
    return { id, kind: spec.kind, label, bins };
  };

  const allDownloads = filtered.every((spec) => spec.kind === "download");
  if (allDownloads) {
    return filtered.map((spec, index) => toOption(spec, index));
  }

  const preferred = selectPreferredInstallSpec(filtered, prefs);
  if (!preferred) {
    return [];
  }
  return [toOption(preferred.spec, preferred.index)];
}

function buildSkillStatus(
  entry: SkillEntry,
  config?: OpenClawConfig,
  prefs?: SkillsInstallPreferences,
  eligibility?: SkillEligibilityContext,
  bundledNames?: Set<string>,
): SkillStatusEntry {
  const osFilter = resolveSkillOsFilter();
  const skillKey = resolveSkillKey(entry);
  const skillConfig = resolveSkillConfig(config, skillKey);
  const disabled = skillConfig?.enabled === false;
  const allowBundled = resolveBundledAllowlist(config);
  const blockedByAllowlist = !isBundledSkillAllowed(entry, allowBundled);
  const always = entry.metadata?.always === true;
  const emoji = entry.metadata?.emoji ?? entry.frontmatter.emoji;
  const homepageRaw =
    entry.metadata?.homepage ??
    entry.frontmatter.homepage ??
    entry.frontmatter.website ??
    entry.frontmatter.url;
  const homepage = homepageRaw?.trim() ? homepageRaw.trim() : undefined;
  const bundled =
    bundledNames && bundledNames.size > 0
      ? bundledNames.has(entry.skill.name)
      : entry.skill.source === "openclaw-bundled";

  const requiredBins = entry.metadata?.requires?.bins ?? [];
  const requiredAnyBins = entry.metadata?.requires?.anyBins ?? [];
  const requiredEnv = entry.metadata?.requires?.env ?? [];
  const requiredConfig = entry.metadata?.requires?.config ?? [];
  const requiredOs = entry.metadata?.os ?? [];

  const missingBins = requiredBins.filter((bin) => {
    if (hasBinary(bin)) {
      return false;
    }
    if (eligibility?.remote?.hasBin?.(bin)) {
      return false;
    }
    return true;
  });
  const missingAnyBins =
    requiredAnyBins.length > 0 &&
    !(
      requiredAnyBins.some((bin) => hasBinary(bin)) ||
      eligibility?.remote?.hasAnyBin?.(requiredAnyBins)
    )
      ? requiredAnyBins
      : [];
  const missingOs =
    requiredOs.length > 0 &&
    !osFilter.compatible.some((os) => requiredOs.includes(os)) &&
    !eligibility?.remote?.platforms?.some((remotePlatform) => {
      const rp = String(remotePlatform);
      if (rp === "android") {
        return requiredOs.includes("linux" as NodeJS.Platform) || requiredOs.includes("android");
      }
      return requiredOs.includes(rp as NodeJS.Platform);
    })
      ? requiredOs
      : [];

  const missingEnv: string[] = [];
  for (const envName of requiredEnv) {
    if (process.env[envName]) {
      continue;
    }
    if (skillConfig?.env?.[envName]) {
      continue;
    }
    if (skillConfig?.apiKey && entry.metadata?.primaryEnv === envName) {
      continue;
    }
    missingEnv.push(envName);
  }

  const configChecks: SkillStatusConfigCheck[] = requiredConfig.map((pathStr) => {
    const value = resolveConfigPath(config, pathStr);
    const satisfied = isConfigPathTruthy(config, pathStr);
    return { path: pathStr, value, satisfied };
  });
  const missingConfig = configChecks.filter((check) => !check.satisfied).map((check) => check.path);

  const missing = always
    ? { bins: [], anyBins: [], env: [], config: [], os: [] }
    : {
        bins: missingBins,
        anyBins: missingAnyBins,
        env: missingEnv,
        config: missingConfig,
        os: missingOs,
      };
  const eligible =
    !disabled &&
    !blockedByAllowlist &&
    (always ||
      (missing.bins.length === 0 &&
        missing.anyBins.length === 0 &&
        missing.env.length === 0 &&
        missing.config.length === 0 &&
        missing.os.length === 0));

  return {
    name: entry.skill.name,
    description: entry.skill.description,
    source: entry.skill.source,
    bundled,
    filePath: entry.skill.filePath,
    baseDir: entry.skill.baseDir,
    skillKey,
    primaryEnv: entry.metadata?.primaryEnv,
    emoji,
    homepage,
    always,
    disabled,
    blockedByAllowlist,
    eligible,
    requirements: {
      bins: requiredBins,
      anyBins: requiredAnyBins,
      env: requiredEnv,
      config: requiredConfig,
      os: requiredOs,
    },
    missing,
    configChecks,
    install: normalizeInstallOptions(entry, prefs ?? resolveSkillsInstallPreferences(config)),
  };
}

export function buildWorkspaceSkillStatus(
  workspaceDir: string,
  opts?: {
    config?: OpenClawConfig;
    managedSkillsDir?: string;
    entries?: SkillEntry[];
    eligibility?: SkillEligibilityContext;
  },
): SkillStatusReport {
  const managedSkillsDir = opts?.managedSkillsDir ?? path.join(CONFIG_DIR, "skills");
  const bundledContext = resolveBundledSkillsContext();
  const skillEntries =
    opts?.entries ??
    loadWorkspaceSkillEntries(workspaceDir, {
      config: opts?.config,
      managedSkillsDir,
      bundledSkillsDir: bundledContext.dir,
    });
  const prefs = resolveSkillsInstallPreferences(opts?.config);
  return {
    workspaceDir,
    managedSkillsDir,
    skills: skillEntries.map((entry) =>
      buildSkillStatus(entry, opts?.config, prefs, opts?.eligibility, bundledContext.names),
    ),
  };
}
