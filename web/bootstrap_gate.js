(async function bootEvaluator(global) {
  'use strict';
  try {
    if (
      global.__hustlEvaluatorGuardInstalled !== true ||
      !global.__hustlEvaluatorReady ||
      typeof global.__hustlEvaluatorReady.then !== 'function'
    ) {
      throw new Error('Evaluator safety guard unavailable');
    }
    await global.__hustlEvaluatorReady;
    const script = global.document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    script.async = true;
    global.document.body.appendChild(script);
  } catch (_) {
    global.document.body.textContent =
      'The evaluator could not establish its offline safety boundary.';
  }
})(globalThis);
