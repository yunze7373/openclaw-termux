/**
 * Native Dependencies Manager
 * Handles optional native dependencies for Termux/Android compatibility
 * These dependencies are optional and may not be available on all platforms
 */

const nativeDeps = {
  canvas: null as any,
  llamaCpp: null as any,
  opus: null as any,
};

const loadedModules = new Set<string>();

/**
 * Safely load optional native dependency
 * @param moduleName - Name of the module to load
 * @param fallbackPath - Path to use in error messages
 * @returns Loaded module or null if unavailable
 */
export async function loadOptionalNative(moduleName: string, fallbackPath?: string): Promise<any> {
  if (loadedModules.has(moduleName)) {
    return nativeDeps[moduleName as keyof typeof nativeDeps];
  }

  try {
    let module = null;
    
    switch (moduleName) {
      case 'canvas':
        module = await import('@napi-rs/canvas');
        break;
      case 'llama-cpp':
        module = await import('node-llama-cpp');
        break;
      case 'opus':
        module = await import('@discordjs/opus');
        break;
      default:
        throw new Error(`Unknown native module: ${moduleName}`);
    }

    nativeDeps[moduleName as keyof typeof nativeDeps] = module;
    loadedModules.add(moduleName);
    
    return module;
  } catch (error) {
    // Log warning but don't fail
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.warn(
      `[Native Deps] Failed to load ${moduleName}: ${errorMsg}` +
      (fallbackPath ? `\n[Native Deps] Fallback: Features requiring ${moduleName} will be unavailable` : '')
    );
    
    nativeDeps[moduleName as keyof typeof nativeDeps] = null;
    loadedModules.add(moduleName);
    
    return null;
  }
}

/**
 * Check if native dependency is available
 */
export function isNativeAvailable(moduleName: string): boolean {
  return nativeDeps[moduleName as keyof typeof nativeDeps] !== null;
}

/**
 * Get cached native module
 */
export function getNativeModule(moduleName: string): any {
  return nativeDeps[moduleName as keyof typeof nativeDeps] || null;
}

/**
 * Report availability of all native dependencies
 */
export function getNativeDepsReport(): Record<string, boolean> {
  return {
    canvas: isNativeAvailable('canvas'),
    'llama-cpp': isNativeAvailable('llama-cpp'),
    opus: isNativeAvailable('opus'),
  };
}

/**
 * Alert: Canvas module not available fallback
 * This is used when @napi-rs/canvas is not available
 */
export const canvasUnavailableError = new Error(
  'Canvas module (@napi-rs/canvas) is not available on this platform. ' +
  'This typically happens on Termux/Android due to CPU instruction incompatibility. ' +
  'Features requiring canvas (media rendering, screenshot) will be unavailable.'
);

/**
 * Alert: Llama.cpp module not available
 */
export const llamaCppUnavailableError = new Error(
  'Llama.cpp module (node-llama-cpp) is not available on this platform. ' +
  'Local LLM execution will be unavailable. Use cloud-based models instead.'
);
