(function installEvaluatorWebMcpBridge(global) {
  'use strict';
  if (global.hustlEvaluatorWebMcp) return;

  const registrations = new Map();
  let nextId = 0;

  function supported() {
    return Boolean(
      global.document &&
      global.document.modelContext &&
      typeof global.document.modelContext.registerTool === 'function'
    );
  }

  async function registerTool(definitionJson, dartHandler) {
    if (!supported()) return '';
    const id = `hustl-evaluator-${++nextId}`;
    const controller = new AbortController();
    const definition = JSON.parse(definitionJson);
    const tool = {
      ...definition,
      execute: async (argumentsObject) => {
        const result = await dartHandler(JSON.stringify(argumentsObject || {}));
        return JSON.parse(result);
      },
    };
    try {
      await global.document.modelContext.registerTool(tool, {
        signal: controller.signal,
      });
      registrations.set(id, controller);
      return id;
    } catch (error) {
      controller.abort();
      throw error;
    }
  }

  function unregisterTool(id) {
    const controller = registrations.get(id);
    if (!controller) return;
    controller.abort();
    registrations.delete(id);
  }

  global.hustlEvaluatorWebMcp = Object.freeze({
    get supported() { return supported(); },
    registerTool,
    unregisterTool,
  });
})(globalThis);
