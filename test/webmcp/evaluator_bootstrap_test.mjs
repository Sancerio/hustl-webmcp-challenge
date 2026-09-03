import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(
  new URL('../../evaluator_assets/evaluator_bootstrap.js', import.meta.url),
  'utf8',
);

async function run(
  active,
  {
    controlled = false,
    serviceWorkerAvailable = true,
    registrations = [],
    finalRegistrations = [],
    cacheKeys = ['flutter-app-cache'],
    finalCacheKeys = [],
    cacheDeleteResult = true,
    cleanupAvailable = true,
    indexedDbCleanup = async () => {},
    onAppend = () => {},
  } = {},
) {
  const appended = [];
  const deletedCaches = [];
  const errors = [];
  let reloads = 0;
  let registrationReads = 0;
  let cacheKeyReads = 0;
  let cleanupCalls = 0;
  const context = {
    __hustlEvaluatorRuntimeGuard: active
      ? {
          active: true,
          cleanupIndexedDb: cleanupAvailable
            ? () => {
                cleanupCalls += 1;
                return indexedDbCleanup(cleanupCalls);
              }
            : undefined,
        }
      : undefined,
    caches: {
      async delete(key) {
        deletedCaches.push(key);
        return cacheDeleteResult;
      },
      async keys() {
        return cacheKeyReads++ === 0 ? cacheKeys : finalCacheKeys;
      },
    },
    document: {
      body: {
        appendChild(node) {
          appended.push(node);
          onAppend(node);
        },
      },
      createElement(tagName) {
        return { tagName };
      },
    },
    location: {
      reload() {
        reloads += 1;
      },
    },
    navigator: {
      serviceWorker: serviceWorkerAvailable
        ? {
            controller: controlled ? {} : null,
            async getRegistrations() {
              return registrationReads++ === 0
                ? registrations
                : finalRegistrations;
            },
          }
        : undefined,
    },
    setTimeout(callback) {
      try {
        callback();
      } catch (error) {
        errors.push(error);
      }
    },
  };
  context.globalThis = context;
  vm.runInNewContext(source, context, { filename: 'evaluator_bootstrap.js' });
  await new Promise((resolve) => setImmediate(resolve));
  return {
    appended,
    cacheKeyReads,
    cleanupCalls,
    deletedCaches,
    errors,
    registrationReads,
    reloads,
  };
}

test('starts Flutter only after the evaluator guard is active', async () => {
  assert.deepEqual((await run(false)).appended, []);

  const { appended, cleanupCalls, deletedCaches, reloads } = await run(true);
  assert.equal(appended.length, 1);
  assert.deepEqual(appended[0], {
    async: true,
    src: 'flutter_bootstrap.js',
    tagName: 'script',
  });
  assert.deepEqual(deletedCaches, ['flutter-app-cache']);
  assert.equal(cleanupCalls, 2);
  assert.equal(reloads, 0);
});

test('re-verifies IndexedDB after worker and cache cleanup before starting Flutter', async () => {
  const lifecycle = [];
  let releaseFinalCleanup;
  const resultPromise = run(true, {
    indexedDbCleanup: (call) => {
      lifecycle.push(`cleanup-${call}-started`);
      if (call === 1) {
        lifecycle.push('cleanup-1-finished');
        return Promise.resolve();
      }
      return new Promise((resolve) => {
        releaseFinalCleanup = () => {
          lifecycle.push('cleanup-2-finished');
          resolve();
        };
      });
    },
    onAppend() {
      lifecycle.push('flutter-appended');
    },
  });

  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(lifecycle, [
    'cleanup-1-started',
    'cleanup-1-finished',
    'cleanup-2-started',
  ]);
  releaseFinalCleanup();
  const result = await resultPromise;
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(result.cleanupCalls, 2);
  assert.deepEqual(lifecycle, [
    'cleanup-1-started',
    'cleanup-1-finished',
    'cleanup-2-started',
    'cleanup-2-finished',
    'flutter-appended',
  ]);
});

test('fails closed when IndexedDB cleanup rejects or is unavailable', async () => {
  const initialRejected = await run(true, {
    indexedDbCleanup: async (call) => {
      assert.equal(call, 1);
      throw new Error('IndexedDB cleanup failed');
    },
  });
  assert.equal(initialRejected.cleanupCalls, 1);
  assert.deepEqual(initialRejected.appended, []);
  assert.match(initialRejected.errors[0]?.message, /IndexedDB cleanup failed/);

  const finalRejected = await run(true, {
    indexedDbCleanup: async (call) => {
      if (call === 2) throw new Error('Final IndexedDB verification failed');
    },
  });
  assert.equal(finalRejected.cleanupCalls, 2);
  assert.deepEqual(finalRejected.appended, []);
  assert.match(
    finalRejected.errors[0]?.message,
    /Final IndexedDB verification failed/,
  );

  const unavailable = await run(true, { cleanupAvailable: false });
  assert.equal(unavailable.cleanupCalls, 0);
  assert.deepEqual(unavailable.appended, []);
  assert.match(
    unavailable.errors[0]?.message,
    /IndexedDB cleanup boundary is unavailable/,
  );
});

test('unregisters a legacy worker and reloads before Flutter starts', async () => {
  let unregisters = 0;
  const result = await run(true, {
    controlled: true,
    registrations: [
      {
        async unregister() {
          unregisters += 1;
          return true;
        },
      },
    ],
  });

  assert.equal(unregisters, 1);
  assert.equal(result.cleanupCalls, 2);
  assert.equal(result.reloads, 1);
  assert.deepEqual(result.appended, []);
});

test('tolerates concurrent cleanup races after verifying final state', async () => {
  let unregisters = 0;
  const result = await run(true, {
    cacheDeleteResult: false,
    registrations: [
      {
        async unregister() {
          unregisters += 1;
          return false;
        },
      },
    ],
  });

  assert.equal(unregisters, 1);
  assert.equal(result.registrationReads, 2);
  assert.equal(result.cacheKeyReads, 2);
  assert.equal(result.cleanupCalls, 2);
  assert.deepEqual(result.deletedCaches, ['flutter-app-cache']);
  assert.equal(result.appended.length, 1);
  assert.deepEqual(result.errors, []);
});

test('clears and verifies caches when service workers are unavailable', async () => {
  const result = await run(true, { serviceWorkerAvailable: false });

  assert.equal(result.registrationReads, 0);
  assert.equal(result.cacheKeyReads, 2);
  assert.equal(result.cleanupCalls, 2);
  assert.deepEqual(result.deletedCaches, ['flutter-app-cache']);
  assert.equal(result.appended.length, 1);
  assert.deepEqual(result.errors, []);
});

test('fails closed when legacy persistent state remains after cleanup', async () => {
  const remainingRegistration = { async unregister() { return false; } };
  const registrationFailure = await run(true, {
    registrations: [remainingRegistration],
    finalRegistrations: [remainingRegistration],
  });
  assert.deepEqual(registrationFailure.appended, []);
  assert.match(
    registrationFailure.errors[0]?.message,
    /could not unregister a legacy service worker/,
  );

  const cacheFailure = await run(true, {
    finalCacheKeys: ['flutter-app-cache'],
  });
  assert.deepEqual(cacheFailure.appended, []);
  assert.match(
    cacheFailure.errors[0]?.message,
    /could not delete a legacy browser cache/,
  );
});
