import { hasHelpOrVersion } from "./argv.js";

function isTermuxEnvironment(): boolean {
  return Boolean(
    process.env.TERMUX_VERSION ||
    process.env.PREFIX?.startsWith("/data/data/com.termux"),
  );
}

export function shouldSkipRespawnForArgv(argv: string[]): boolean {
  if (isTermuxEnvironment()) {
    return true;
  }
  return hasHelpOrVersion(argv);
}
