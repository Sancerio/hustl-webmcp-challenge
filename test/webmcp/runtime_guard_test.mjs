import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import vm from 'node:vm';

const guard = readFileSync(
  new URL('../../evaluator_assets/runtime_guard.js', import.meta.url),
  'utf8',
);
const index = readFileSync(new URL('../../web/index.html', import.meta.url), 'utf8');
const gate = readFileSync(
  new URL('../../web/bootstrap_gate.js', import.meta.url),
  'utf8',
);
const vercel = JSON.parse(
  readFileSync(new URL('../../vercel.json', import.meta.url), 'utf8'),
);

test('runtime guard covers storage and cross-origin primitives', () => {
  for (const required of [
    'localStorage',
    'sessionStorage',
    'cookie',
    'indexedDB',
    'fetch',
    'XMLHttpRequest',
    'sendBeacon',
    'WebSocket',
    'EventSource',
    'setAttribute',
    'HTMLAnchorElement',
    'serviceWorker',
    'caches',
  ]) {
    assert.match(guard, new RegExp(required));
  }
  assert.match(guard, /Cross-origin access blocked by evaluator/);
  assert.match(guard, /credentials: 'omit'/);
  assert.match(guard, /__hustlEvaluatorReady/);
});

test('guard and CSP load before Flutter bootstrap', () => {
  assert.ok(index.indexOf('runtime_guard.js') >= 0);
  assert.ok(index.indexOf('runtime_guard.js') < index.indexOf('bootstrap_gate.js'));
  assert.doesNotMatch(index, /src="flutter_bootstrap\.js"/);
  assert.match(gate, /await global\.__hustlEvaluatorReady/);
  assert.match(gate, /__hustlEvaluatorGuardInstalled !== true/);
  assert.match(gate, /script\.src = 'flutter_bootstrap\.js'/);
  assert.match(index, /connect-src 'self'/);
  assert.doesNotMatch(index, /http-equiv="Content-Security-Policy"[^>]*frame-ancestors/);
  assert.doesNotMatch(index, /manifest\.json|serviceWorker/);
});

test('deployment clears cookies only on the finite document-route set', () => {
  const commonHeaders = Object.fromEntries(
    vercel.headers[0].headers.map(({ key, value }) => [key, value]),
  );
  assert.equal(vercel.headers[0].source, '/(.*)');
  assert.equal(commonHeaders['Clear-Site-Data'], undefined);
  assert.match(commonHeaders['Permissions-Policy'], /camera=\(\)/);
  assert.match(commonHeaders['Permissions-Policy'], /microphone=\(\)/);
  assert.match(commonHeaders['Content-Security-Policy'], /connect-src 'self'/);

  const documentSources = [
    '/',
    '/demo',
    '/health',
    '/nutrition',
    '/proposals',
    '/proposals/:path*',
    '/templates',
    '/templates/:path*',
  ];
  assert.deepEqual(
    vercel.headers.slice(1).map(({ source }) => source),
    documentSources,
  );
  const navigationConditions = [
    { type: 'header', key: 'Sec-Fetch-Dest', value: 'document' },
    { type: 'header', key: 'Sec-Fetch-Mode', value: 'navigate' },
  ];
  for (const route of vercel.headers.slice(1)) {
    assert.deepEqual(route.has, navigationConditions);
    assert.deepEqual(route.headers, [
      { key: 'Clear-Site-Data', value: '"cookies"' },
    ]);
  }

  const matchesDocumentSource = (source, pathname) => {
    if (!source.endsWith('/:path*')) return pathname === source;
    const prefix = source.slice(0, -'/:path*'.length);
    return pathname === prefix || pathname.startsWith(`${prefix}/`);
  };
  const carriesClearSiteData = (pathname, destination, mode) =>
    vercel.headers.slice(1).some((rule) =>
      matchesDocumentSource(rule.source, pathname) &&
      rule.has.every(({ key, value }) => ({
        'Sec-Fetch-Dest': destination,
        'Sec-Fetch-Mode': mode,
      })[key] === value));
  for (const documentPath of [
    '/',
    '/demo',
    '/health',
    '/nutrition',
    '/proposals',
    '/proposals/proposal-1',
    '/proposals/proposal.with-dot',
    '/templates',
    '/templates/template-strength-a',
    '/templates/template.with-dot',
  ]) {
    assert.equal(
      carriesClearSiteData(documentPath, 'document', 'navigate'),
      true,
      `${documentPath} must clear inherited cookies`,
    );
    assert.equal(carriesClearSiteData(documentPath, '', 'cors'), false);
  }

  for (const [asset, destination, mode] of [
    ['/index.html', 'document', 'navigate'],
    ['/runtime_guard.js', 'script', 'no-cors'],
    ['/webmcp_bridge.js', 'script', 'no-cors'],
    ['/bootstrap_gate.js', 'script', 'no-cors'],
    ['/flutter_bootstrap.js', 'script', 'no-cors'],
    ['/main.dart.js', 'script', 'no-cors'],
    ['/main.dart.wasm', '', 'cors'],
    ['/version.json', '', 'cors'],
    ['/canvaskit/canvaskit.js', 'script', 'cors'],
    ['/canvaskit/canvaskit.wasm', '', 'cors'],
    ['/assets/AssetManifest.bin.json', '', 'cors'],
    ['/assets/FontManifest.json', '', 'cors'],
    ['/assets/data/exercises.json', '', 'cors'],
    ['/assets/fonts/DM-Sans-Variable.ttf', 'font', 'cors'],
    [
      '/assets/notosanssymbols/v43/notosanssymbols2-regular.woff2',
      'font',
      'cors',
    ],
  ]) {
    assert.equal(
      carriesClearSiteData(asset, destination, mode),
      false,
      `${asset} must not carry Clear-Site-Data`,
    );
  }
});

test('Flutter bootstrap patch keeps font fallback requests on the evaluator origin', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'hustl-evaluator-bootstrap-'));
  try {
    const bootstrap = join(scratch, 'flutter_bootstrap.js');
    writeFileSync(bootstrap, 'before;_flutter.loader.load();after;', 'utf8');
    const result = spawnSync(
      process.execPath,
      [
        new URL('../../scripts/patch_flutter_bootstrap.mjs', import.meta.url)
          .pathname,
        bootstrap,
      ],
      { encoding: 'utf8' },
    );
    assert.equal(result.status, 0, result.stderr);
    assert.equal(
      readFileSync(bootstrap, 'utf8'),
      'before;_flutter.loader.load({config:{fontFallbackBaseUrl:"assets/"}});after;',
    );

    const second = spawnSync(
      process.execPath,
      [
        new URL('../../scripts/patch_flutter_bootstrap.mjs', import.meta.url)
          .pathname,
        bootstrap,
      ],
      { encoding: 'utf8' },
    );
    assert.notEqual(second.status, 0);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});

test('guard omits credentials and blocks persistent or alternate transports', async () => {
  const fetches = [];
  class Document {}
  Object.defineProperty(Document.prototype, 'cookie', {
    configurable: true,
    get: () => 'legacy=session',
    set: () => {},
  });
  const indexedDB = {
    databases: async () => [],
    deleteDatabase: () => {
      throw new Error('unexpected delete');
    },
    cmp: () => 0,
  };
  const context = {
    URL,
    DOMException,
    Document,
    document: new Document(),
    location: {
      origin: 'https://evaluator.example',
      href: 'https://evaluator.example/',
    },
    indexedDB,
    fetch: async (input, init) => {
      fetches.push({ input, init });
      return { ok: true };
    },
    XMLHttpRequest: function XMLHttpRequest() {},
    WebSocket: function WebSocket() {},
    EventSource: function EventSource() {},
    navigator: { sendBeacon: () => true },
  };
  context.globalThis = context;
  vm.runInNewContext(guard, context);
  await context.__hustlEvaluatorReady;

  await context.fetch('/asset.json', { credentials: 'include' });
  assert.equal(fetches[0].init.credentials, 'omit');
  assert.throws(() => context.fetch('https://outside.example/data'));
  assert.throws(() => new context.XMLHttpRequest());
  assert.throws(() => new context.WebSocket('/socket'));
  assert.throws(() => new context.EventSource('/events'));
  assert.throws(() => context.navigator.sendBeacon('/events'));
  assert.equal(context.document.cookie, '');
  assert.throws(() => { context.document.cookie = 'session=secret'; });
  assert.throws(() => context.indexedDB.open('anything'));
  assert.equal((await context.indexedDB.databases()).length, 0);
});

test('runtime guard deletes every legal IndexedDB string name including empty', async () => {
  class Document {}
  Object.defineProperty(Document.prototype, 'cookie', {
    configurable: true,
    get: () => '',
    set: () => {},
  });
  const deleted = [];
  let inventoryReads = 0;
  const context = {
    URL,
    DOMException,
    Document,
    document: new Document(),
    location: {
      origin: 'https://evaluator.example',
      href: 'https://evaluator.example/',
    },
    indexedDB: {
      databases: async () => {
        inventoryReads += 1;
        return inventoryReads === 1
          ? [{ name: '' }, { name: 'normal-database' }]
          : [];
      },
      deleteDatabase: (name) => {
        deleted.push(name);
        const request = {};
        queueMicrotask(() => request.onsuccess());
        return request;
      },
      cmp: () => 0,
    },
  };
  context.globalThis = context;
  vm.runInNewContext(guard, context);
  await context.__hustlEvaluatorReady;

  assert.deepEqual(deleted, ['', 'normal-database']);
  assert.equal(inventoryReads, 2);
  assert.equal((await context.indexedDB.databases()).length, 0);
});

test('runtime guard fails closed on sparse or malformed IndexedDB inventory entries', async () => {
  for (const inventory of [new Array(1), [{ name: null }]]) {
    class Document {}
    Object.defineProperty(Document.prototype, 'cookie', {
      configurable: true,
      get: () => '',
      set: () => {},
    });
    let inventoryReads = 0;
    let deleteCalls = 0;
    const context = {
      URL,
      DOMException,
      Document,
      document: new Document(),
      location: {
        origin: 'https://evaluator.example',
        href: 'https://evaluator.example/',
      },
      indexedDB: {
        databases: async () => {
          inventoryReads += 1;
          return inventoryReads === 1 ? inventory : [];
        },
        deleteDatabase: () => {
          deleteCalls += 1;
          const request = {};
          queueMicrotask(() => request.onsuccess());
          return request;
        },
        cmp: () => 0,
      },
    };
    context.globalThis = context;
    vm.runInNewContext(guard, context);

    await assert.rejects(
      context.__hustlEvaluatorReady,
      (error) => error.name === 'SecurityError' &&
        error.message === 'IndexedDB inventory invalid',
    );
    assert.equal(inventoryReads, 1);
    assert.equal(deleteCalls, 0);
  }
});

test('runtime guard fails closed when any IndexedDB inventory entry remains', async () => {
  class Document {}
  Object.defineProperty(Document.prototype, 'cookie', {
    configurable: true,
    get: () => '',
    set: () => {},
  });
  let inventoryReads = 0;
  const context = {
    URL,
    DOMException,
    Document,
    document: new Document(),
    location: {
      origin: 'https://evaluator.example',
      href: 'https://evaluator.example/',
    },
    indexedDB: {
      databases: async () => {
        inventoryReads += 1;
        return [{ name: '' }];
      },
      deleteDatabase: () => {
        const request = {};
        queueMicrotask(() => request.onsuccess());
        return request;
      },
      cmp: () => 0,
    },
  };
  context.globalThis = context;
  vm.runInNewContext(guard, context);

  await assert.rejects(
    context.__hustlEvaluatorReady,
    (error) => error.name === 'SecurityError' &&
      error.message === 'IndexedDB isolation verification failed',
  );
  assert.equal(inventoryReads, 2);
  assert.equal(context.indexedDB.open, undefined);
});

test('controlled legacy service worker forces a reload before Flutter can boot', async () => {
  class Document {}
  Object.defineProperty(Document.prototype, 'cookie', {
    configurable: true,
    get: () => '',
    set: () => {},
  });
  let registered = true;
  let reloads = 0;
  const registration = {
    unregister: async () => {
      registered = false;
      return true;
    },
  };
  const context = {
    URL,
    DOMException,
    Document,
    document: new Document(),
    location: {
      origin: 'https://evaluator.example',
      href: 'https://evaluator.example/',
      reload: () => { reloads += 1; },
    },
    indexedDB: {
      databases: async () => [],
      deleteDatabase: () => { throw new Error('unexpected delete'); },
      cmp: () => 0,
    },
    caches: {
      keys: async () => [],
      delete: async () => true,
    },
    navigator: {
      sendBeacon: () => true,
      serviceWorker: {
        controller: {},
        getRegistrations: async () => registered ? [registration] : [],
      },
    },
  };
  context.globalThis = context;
  vm.runInNewContext(guard, context);

  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(reloads, 1);
  assert.equal(registered, false);
  const readiness = await Promise.race([
    context.__hustlEvaluatorReady.then(() => 'resolved'),
    new Promise((resolve) => setTimeout(() => resolve('pending'), 10)),
  ]);
  assert.equal(readiness, 'pending');
});
