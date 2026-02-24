import {
  installLaunchAgent,
  isLaunchAgentLoaded,
  readLaunchAgentProgramArguments,
  readLaunchAgentRuntime,
  restartLaunchAgent,
  stopLaunchAgent,
  uninstallLaunchAgent,
} from "./launchd.js";
import {
  installPm2Process,
  isPm2ProcessRunning,
  isTermux,
  readPm2ProcessCommand,
  readPm2ProcessRuntime,
  restartPm2Process,
  stopPm2Process,
  uninstallPm2Process,
} from "./pm2.js";
import {
  installScheduledTask,
  isScheduledTaskInstalled,
  readScheduledTaskCommand,
  readScheduledTaskRuntime,
  restartScheduledTask,
  stopScheduledTask,
  uninstallScheduledTask,
} from "./schtasks.js";
import type { GatewayServiceRuntime } from "./service-runtime.js";
import type {
  GatewayServiceCommandConfig,
  GatewayServiceControlArgs,
  GatewayServiceEnv,
  GatewayServiceEnvArgs,
  GatewayServiceInstallArgs,
  GatewayServiceManageArgs,
} from "./service-types.js";
import {
  installSystemdService,
  isSystemdServiceEnabled,
  readSystemdServiceExecStart,
  readSystemdServiceRuntime,
  restartSystemdService,
  stopSystemdService,
  uninstallSystemdService,
} from "./systemd.js";
export type {
  GatewayServiceCommandConfig,
  GatewayServiceControlArgs,
  GatewayServiceEnv,
  GatewayServiceEnvArgs,
  GatewayServiceInstallArgs,
  GatewayServiceManageArgs,
} from "./service-types.js";

function ignoreInstallResult(
  install: (args: GatewayServiceInstallArgs) => Promise<unknown>,
): (args: GatewayServiceInstallArgs) => Promise<void> {
  return async (args) => {
    await install(args);
  };
}

export type GatewayService = {
  label: string;
  loadedText: string;
  notLoadedText: string;
  install: (args: GatewayServiceInstallArgs) => Promise<void>;
  uninstall: (args: GatewayServiceManageArgs) => Promise<void>;
  stop: (args: GatewayServiceControlArgs) => Promise<void>;
  restart: (args: GatewayServiceControlArgs) => Promise<void>;
  isLoaded: (args: GatewayServiceEnvArgs) => Promise<boolean>;
  readCommand: (env: GatewayServiceEnv) => Promise<GatewayServiceCommandConfig | null>;
  readRuntime: (env: GatewayServiceEnv) => Promise<GatewayServiceRuntime>;
};

export function resolveGatewayService(): GatewayService {
  if (process.platform === "darwin") {
    return {
      label: "LaunchAgent",
      loadedText: "loaded",
      notLoadedText: "not loaded",
      install: ignoreInstallResult(installLaunchAgent),
      uninstall: uninstallLaunchAgent,
      stop: stopLaunchAgent,
      restart: restartLaunchAgent,
      isLoaded: isLaunchAgentLoaded,
      readCommand: readLaunchAgentProgramArguments,
      readRuntime: readLaunchAgentRuntime,
    };
  }

  if (process.platform === "linux") {
    return {
      label: "systemd",
      loadedText: "enabled",
      notLoadedText: "disabled",
      install: ignoreInstallResult(installSystemdService),
      uninstall: uninstallSystemdService,
      stop: stopSystemdService,
      restart: restartSystemdService,
      isLoaded: isSystemdServiceEnabled,
      readCommand: readSystemdServiceExecStart,
      readRuntime: readSystemdServiceRuntime,
    };
  }

  if (process.platform === "win32") {
    return {
      label: "Scheduled Task",
      loadedText: "registered",
      notLoadedText: "missing",
      install: ignoreInstallResult(installScheduledTask),
      uninstall: uninstallScheduledTask,
      stop: stopScheduledTask,
      restart: restartScheduledTask,
      isLoaded: isScheduledTaskInstalled,
      readCommand: readScheduledTaskCommand,
      readRuntime: readScheduledTaskRuntime,
    };
  }

  if (process.platform === "android") {
    if (isTermux()) {
      return {
        label: "pm2 (Termux)",
        loadedText: "online",
        notLoadedText: "stopped",
        install: ignoreInstallResult(installPm2Process),
        uninstall: uninstallPm2Process,
        stop: stopPm2Process,
        restart: restartPm2Process,
        isLoaded: isPm2ProcessRunning,
        readCommand: readPm2ProcessCommand,
        readRuntime: readPm2ProcessRuntime,
      };
    }

    return {
      label: "Manual (Android)",
      loadedText: "manual",
      notLoadedText: "manual",
      install: async () => {},
      uninstall: async () => {},
      stop: async () => {},
      restart: async () => {},
      isLoaded: async () => false,
      readCommand: async () => null,
      readRuntime: async () => ({ status: "stopped" }),
    };
  }

  throw new Error(`Gateway service install not supported on ${process.platform}`);
}
