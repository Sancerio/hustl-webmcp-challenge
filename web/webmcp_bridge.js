(function installHustlWebMcpBridge(global) {
  'use strict';

  if (global.hustlWebMcp) return;

  const registrations = new Map();
  let nextRegistrationId = 0;

  function isSupported() {
    return Boolean(
      global.document &&
        global.document.modelContext &&
        typeof global.document.modelContext.registerTool === 'function',
    );
  }

  async function registerTool(definitionJson, dartHandler) {
    if (!isSupported()) return '';

    const registrationId = `hustl-webmcp-${++nextRegistrationId}`;
    const controller = new AbortController();
    const definition = JSON.parse(definitionJson);
    const tool = {
      ...definition,
      execute: async (argumentsObject) => {
        const resultJson = await dartHandler(
          JSON.stringify(argumentsObject || {}),
        );
        return JSON.parse(resultJson);
      },
    };

    try {
      await global.document.modelContext.registerTool(tool, {
        signal: controller.signal,
      });
      registrations.set(registrationId, controller);
      return registrationId;
    } catch (error) {
      controller.abort();
      throw error;
    }
  }

  function unregisterTool(registrationId) {
    const controller = registrations.get(registrationId);
    if (!controller) return;
    controller.abort();
    registrations.delete(registrationId);
  }

  // Keep the public contract immutable without freezing the host object. The
  // compiled Dart JS interop runtime attaches an internal dispatch record to
  // JavaScript receivers on first use; a frozen/non-extensible bridge crashes
  // app boot before the first Flutter frame in fresh browser contexts.
  const bridge = {};
  Object.defineProperties(bridge, {
    supported: {
      enumerable: true,
      get: isSupported,
    },
    registerTool: {
      enumerable: true,
      value: registerTool,
      writable: false,
    },
    unregisterTool: {
      enumerable: true,
      value: unregisterTool,
      writable: false,
    },
  });
  Object.defineProperty(global, 'hustlWebMcp', {
    configurable: false,
    value: bridge,
    writable: false,
  });
})(globalThis);
