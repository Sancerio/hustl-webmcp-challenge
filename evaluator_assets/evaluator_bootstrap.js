(async function startHustlEvaluator() {
  'use strict';

  const runtimeGuard = globalThis.__hustlEvaluatorRuntimeGuard;
  if (runtimeGuard?.active !== true) return;
  if (typeof runtimeGuard.cleanupIndexedDb !== 'function') {
    throw new Error('Evaluator IndexedDB cleanup boundary is unavailable');
  }

  // The guard has already replaced window.indexedDB with a fail-closed facade.
  // Await its closure-held native factory cleanup before any Flutter code can
  // run, so both legacy databases and new persistence attempts are covered.
  await runtimeGuard.cleanupIndexedDb();

  // Flutter's historical web default registered an offline-first worker. A
  // worker from an older evaluator deployment can continue serving stale app
  // code before this release's page scripts run, so evict it before booting.
  // If this page is still controlled, one reload is required for the
  // unregistration to take effect. The next load has no controller and boots.
  const serviceWorker = globalThis.navigator?.serviceWorker;
  let wasControlled = false;
  if (serviceWorker) {
    wasControlled = serviceWorker.controller != null;
    const registrations = await serviceWorker.getRegistrations();
    for (const registration of registrations) {
      // A false result can mean another tab removed the registration between
      // discovery and this call. Verify the final state instead of treating
      // that benign race as a hard failure.
      await registration.unregister();
    }
    if ((await serviceWorker.getRegistrations()).length !== 0) {
      throw new Error('Evaluator could not unregister a legacy service worker');
    }

  }

  // CacheStorage can exist even when the service-worker API is unavailable or
  // disabled. It is an independent persistent boundary and must be empty
  // before Flutter can boot.
  if (globalThis.caches) {
    for (const key of await globalThis.caches.keys()) {
      // CacheStorage.delete has the same already-deleted race semantics as
      // ServiceWorkerRegistration.unregister.
      await globalThis.caches.delete(key);
    }
    if ((await globalThis.caches.keys()).length !== 0) {
      throw new Error('Evaluator could not delete a legacy browser cache');
    }
  }

  // Persistent state can be recreated by a legacy worker or another
  // same-origin realm while the asynchronous worker/cache cleanup runs. The
  // guard's cleanup is intentionally re-runnable: make a fresh enumeration,
  // deletion, and zero-remnant verification immediately before reload/boot.
  await runtimeGuard.cleanupIndexedDb();

  if (wasControlled) {
    globalThis.location.reload();
    return;
  }

  const bootstrap = document.createElement('script');
  bootstrap.src = 'flutter_bootstrap.js';
  bootstrap.async = true;
  document.body.appendChild(bootstrap);
})().catch((error) => {
  // Surface a hard failure without falling through to Flutter. The evaluator
  // is safer unavailable than running behind stale persistent browser state.
  setTimeout(() => {
    throw error;
  });
});
