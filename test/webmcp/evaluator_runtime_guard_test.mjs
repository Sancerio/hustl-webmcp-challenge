import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(
  new URL('../../evaluator_assets/evaluator_runtime_guard.js', import.meta.url),
  'utf8',
);

function fakeIndexedDb({ snapshots, deleteOutcome = 'success' }) {
  const deletes = [];
  let reads = 0;
  const factory = {
    async databases() {
      const snapshot = snapshots[Math.min(reads++, snapshots.length - 1)];
      if (snapshot instanceof Error) throw snapshot;
      return snapshot;
    },
    deleteDatabase(name) {
      deletes.push(name);
      const request = { error: undefined };
      queueMicrotask(() => {
        if (deleteOutcome === 'blocked') {
          request.onblocked?.();
        } else if (deleteOutcome === 'error') {
          request.error = new Error(`native delete failed for ${name}`);
          request.onerror?.();
        } else {
          request.onsuccess?.();
        }
      });
      return request;
    },
  };
  return {
    deletes,
    factory,
    get reads() {
      return reads;
    },
  };
}

function install(configureContext) {
  const calls = {
    beacon: [],
    console: [],
    cookieWrites: [],
    documentWrite: [],
    eventSource: [],
    fetch: [],
    insertedHtml: [],
    navigationClicks: [],
    webSocket: [],
    windowOpen: [],
    xhrConstructed: 0,
    xhrOpen: [],
    xhrSend: 0,
  };

  class FakeNode {
    constructor() {
      this.children = [];
    }

    appendChild(node) {
      this.children.push(node);
      return node;
    }

    insertBefore(node, referenceNode) {
      const index = this.children.indexOf(referenceNode);
      this.children.splice(index < 0 ? this.children.length : index, 0, node);
      return node;
    }

    replaceChild(node, oldChild) {
      const index = this.children.indexOf(oldChild);
      if (index >= 0) this.children[index] = node;
      return oldChild;
    }
  }

  class FakeElement extends FakeNode {
    constructor(tagName = 'div') {
      super();
      this.tagName = tagName.toUpperCase();
      this.attributes = Object.create(null);
      this._innerHtml = '';
    }

    append(...nodes) {
      this.children.push(...nodes);
    }

    prepend(...nodes) {
      this.children.unshift(...nodes);
    }

    before(...nodes) {
      this.children.push(...nodes);
    }

    after(...nodes) {
      this.children.push(...nodes);
    }

    replaceWith(...nodes) {
      this.children = [...nodes];
    }

    getAttribute(name) {
      const normalized = String(name).toLowerCase();
      return Object.prototype.hasOwnProperty.call(this.attributes, normalized)
        ? this.attributes[normalized]
        : null;
    }

    setAttribute(name, value) {
      this.attributes[String(name).toLowerCase()] = String(value);
    }

    setAttributeNS(_namespace, name, value) {
      this.setAttribute(name, value);
    }

    querySelectorAll() {
      return [];
    }

    insertAdjacentHTML(position, markup) {
      calls.insertedHtml.push([position, markup]);
    }
  }

  Object.defineProperties(FakeElement.prototype, {
    innerHTML: {
      configurable: true,
      get() {
        return this._innerHtml;
      },
      set(value) {
        this._innerHtml = String(value);
        this.parseInertMarkup?.(this._innerHtml);
      },
    },
    outerHTML: {
      configurable: true,
      get() {
        return this._innerHtml;
      },
      set(value) {
        this._innerHtml = String(value);
      },
    },
  });

  function resourceElement(tagName, properties) {
    class ResourceElement extends FakeElement {
      constructor() {
        super(tagName);
      }
    }
    for (const property of properties) {
      Object.defineProperty(ResourceElement.prototype, property, {
        configurable: true,
        get() {
          return this.getAttribute(property) || '';
        },
        set(value) {
          this.setAttribute(property, value);
        },
      });
    }
    return ResourceElement;
  }

  class FakeDocumentFragment extends FakeNode {
    append(...nodes) {
      this.children.push(...nodes);
    }

    prepend(...nodes) {
      this.children.unshift(...nodes);
    }

    querySelectorAll() {
      return this.children;
    }
  }

  class FakeTemplateElement extends FakeElement {
    constructor() {
      super('template');
      this.content = new FakeDocumentFragment();
    }

    parseInertMarkup(markup) {
      this.content.children = [];
      const tagPattern =
        /<(a|area|audio|base|embed|form|iframe|img|input|link|object|script|source|track|video)\b([^>]*)>/gi;
      for (const tagMatch of String(markup).matchAll(tagPattern)) {
        const element = new FakeElement(tagMatch[1]);
        const attributePattern =
          /\b([a-z][a-z0-9:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>\x60]+))/gi;
        for (const attributeMatch of tagMatch[2].matchAll(attributePattern)) {
          const value =
            attributeMatch[2] ?? attributeMatch[3] ?? attributeMatch[4] ?? '';
          element.attributes[attributeMatch[1].toLowerCase()] = value
            .replace(/&#x([0-9a-f]+);?/gi, (_, hex) =>
              String.fromCodePoint(Number.parseInt(hex, 16)),
            )
            .replace(/&#(\d+);?/g, (_, decimal) =>
              String.fromCodePoint(Number.parseInt(decimal, 10)),
            )
            .replace(/&colon;?/gi, ':');
        }
        this.content.children.push(element);
      }
    }
  }

  class FakeDocument extends FakeNode {
    constructor() {
      super();
      this.documentElement = new FakeElement('html');
    }

    append(...nodes) {
      this.children.push(...nodes);
    }

    prepend(...nodes) {
      this.children.unshift(...nodes);
    }

    createElement(tagName) {
      return String(tagName).toLowerCase() === 'template'
        ? new FakeTemplateElement()
        : new FakeElement(tagName);
    }

    write(...args) {
      calls.documentWrite.push(args);
    }

    writeln(...args) {
      calls.documentWrite.push(args);
    }
  }

  Object.defineProperty(FakeDocument.prototype, 'cookie', {
    configurable: true,
    get() {
      return 'visible_session=native';
    },
    set(value) {
      calls.cookieWrites.push(value);
    },
  });

  class FakeXhr {
    constructor() {
      calls.xhrConstructed += 1;
    }

    open(...args) {
      calls.xhrOpen.push(args);
    }

    send() {
      calls.xhrSend += 1;
    }

    setRequestHeader() {}
  }

  class FakeWebSocket {
    constructor(url) {
      calls.webSocket.push(url);
    }
  }

  class FakeEventSource {
    constructor(url) {
      calls.eventSource.push(url);
    }
  }

  class FakeNavigator {
    sendBeacon(...args) {
      calls.beacon.push(args);
      return true;
    }
  }

  const HTMLMediaElement = resourceElement('audio', ['src']);
  const HTMLAnchorElement = resourceElement('a', ['href', 'ping']);
  HTMLAnchorElement.prototype.click = function click() {
    calls.navigationClicks.push(this.getAttribute('href'));
  };
  const HTMLAreaElement = resourceElement('area', ['href', 'ping']);
  HTMLAreaElement.prototype.click = HTMLAnchorElement.prototype.click;
  const HTMLVideoElement = class extends HTMLMediaElement {
    constructor() {
      super();
      this.tagName = 'VIDEO';
    }
  };
  Object.defineProperty(HTMLVideoElement.prototype, 'poster', {
    configurable: true,
    get() {
      return this.getAttribute('poster') || '';
    },
    set(value) {
      this.setAttribute('poster', value);
    },
  });

  const context = {
    Document: FakeDocument,
    DocumentFragment: FakeDocumentFragment,
    Element: FakeElement,
    EventSource: FakeEventSource,
    HTMLAnchorElement,
    HTMLAreaElement,
    HTMLBaseElement: resourceElement('base', ['href']),
    HTMLEmbedElement: resourceElement('embed', ['src']),
    HTMLFormElement: resourceElement('form', ['action']),
    HTMLIFrameElement: resourceElement('iframe', ['src', 'srcdoc']),
    HTMLImageElement: resourceElement('img', ['src', 'srcset']),
    HTMLInputElement: resourceElement('input', ['src']),
    HTMLLinkElement: resourceElement('link', ['href']),
    HTMLMediaElement,
    HTMLObjectElement: resourceElement('object', ['data']),
    HTMLScriptElement: resourceElement('script', ['src']),
    HTMLSourceElement: resourceElement('source', ['src', 'srcset']),
    HTMLTrackElement: resourceElement('track', ['src']),
    HTMLVideoElement,
    Node: FakeNode,
    Promise,
    Reflect,
    URL,
    WeakMap,
    WeakSet,
    WebSocket: FakeWebSocket,
    XMLHttpRequest: FakeXhr,
    console: Object.fromEntries(
      ['debug', 'error', 'info', 'log', 'warn'].map((method) => [
        method,
        (...args) => calls.console.push([method, ...args]),
      ]),
    ),
    document: new FakeDocument(),
    fetch: async (...args) => {
      calls.fetch.push(args);
      return { ok: true };
    },
    localStorage: {
      getItem() {
        throw new Error('persistent localStorage was accessed');
      },
    },
    location: {
      href: 'https://evaluator.example/train',
      origin: 'https://evaluator.example',
      protocol: 'https:',
    },
    navigator: new FakeNavigator(),
    open(...args) {
      calls.windowOpen.push(args);
      return { opened: true };
    },
    sessionStorage: {
      getItem() {
        throw new Error('persistent sessionStorage was accessed');
      },
    },
  };
  context.globalThis = context;
  configureContext?.(context);
  vm.runInNewContext(source, context, {
    filename: 'evaluator_runtime_guard.js',
  });
  return { calls, context };
}

test('loads same-origin assets without credentials and blocks credential-bearing transports', async () => {
  const { calls, context } = install();

  assert.equal(
    Object.getOwnPropertyDescriptor(context, 'fetch').value,
    context.fetch,
  );

  await context.fetch('/assets/app.json');
  assert.equal(calls.fetch[0][1].credentials, 'omit');

  const request = { credentials: 'include', url: '/release.json' };
  const callerInit = { cache: 'reload', credentials: 'include' };
  await context.fetch(request, callerInit);
  assert.equal(calls.fetch[1][0], request);
  assert.equal(calls.fetch[1][1].cache, 'reload');
  assert.equal(calls.fetch[1][1].credentials, 'omit');
  assert.deepEqual(callerInit, { cache: 'reload', credentials: 'include' });

  await assert.rejects(
    context.fetch('https://accounts.example/client.js'),
    /blocked by the evaluator runtime guard/,
  );
  assert.equal(calls.fetch.length, 2);

  assert.throws(
    () => new context.XMLHttpRequest(),
    /XMLHttpRequest blocked/,
  );
  assert.equal(context.XMLHttpRequest.prototype.open, undefined);
  assert.equal(
    Object.getOwnPropertyDescriptor(context, 'XMLHttpRequest').value,
    context.XMLHttpRequest,
  );
  assert.equal(calls.xhrConstructed, 0);
  assert.deepEqual(calls.xhrOpen, []);
  assert.equal(calls.xhrSend, 0);

  assert.equal(context.navigator.sendBeacon('/metrics', 'ok'), false);
  assert.equal(
    context.navigator.sendBeacon('https://telemetry.example/metrics', 'no'),
    false,
  );
  assert.equal(calls.beacon.length, 0);
  const beaconDescriptor = Object.getOwnPropertyDescriptor(
    Object.getPrototypeOf(context.navigator),
    'sendBeacon',
  );
  assert.equal(beaconDescriptor.value.call(context.navigator, '/metrics'), false);
  assert.equal(calls.beacon.length, 0);

  assert.throws(
    () => new context.WebSocket('wss://evaluator.example/socket'),
    /blocked by the evaluator runtime guard/,
  );
  assert.throws(
    () => new context.WebSocket('wss://socket.example/live'),
    /blocked by the evaluator runtime guard/,
  );
  assert.throws(
    () => new context.EventSource('/events'),
    /blocked by the evaluator runtime guard/,
  );
  assert.throws(
    () => new context.EventSource('https://events.example/live'),
    /blocked by the evaluator runtime guard/,
  );
  for (const name of ['XMLHttpRequest', 'WebSocket', 'EventSource']) {
    assert.equal(Object.isExtensible(context[name]), true);
    assert.equal(Object.isExtensible(context[name].prototype), true);
    assert.doesNotThrow(() => {
      Object.defineProperty(
        context[name].prototype,
        '___dart_dispatch_record_test',
        { value: {} },
      );
    });
  }
  assert.deepEqual(calls.webSocket, []);
  assert.deepEqual(calls.eventSource, []);

  assert.deepEqual(context.open('/settings'), { opened: true });
  assert.equal(context.open('https://fdc.nal.usda.gov/'), null);
  assert.deepEqual(calls.windowOpen, [['/settings']]);
  assert.deepEqual(calls.console, []);
});

test('replaces local and session storage with independent memory-only stores', () => {
  const { context } = install();

  for (const property of ['localStorage', 'sessionStorage']) {
    const descriptor = Object.getOwnPropertyDescriptor(context, property);
    assert.equal(descriptor.get, undefined);
    assert.equal(descriptor.value, context[property]);
    assert.equal(Object.isExtensible(context[property]), true);
    assert.equal(
      Object.getOwnPropertyDescriptor(context[property], 'setItem').writable,
      false,
    );
    assert.doesNotThrow(() => {
      Object.defineProperty(context[property], '___dart_dispatch_record_test', {
        value: {},
      });
    });
  }

  context.localStorage.setItem('token', 123);
  context.sessionStorage.setItem('token', 456);
  assert.equal(context.localStorage.getItem('token'), '123');
  assert.equal(context.sessionStorage.getItem('token'), '456');
  assert.equal(context.localStorage.length, 1);
  assert.equal(context.localStorage.key(0), 'token');
  context.localStorage.removeItem('token');
  assert.equal(context.localStorage.getItem('token'), null);
  assert.equal(context.sessionStorage.getItem('token'), '456');
  context.sessionStorage.clear();
  assert.equal(context.sessionStorage.length, 0);
});

test('suppresses document cookies through the prototype accessor', () => {
  const { calls, context } = install();

  assert.equal(context.document.cookie, '');
  context.document.cookie = 'visible_session=changed';
  const descriptor = Object.getOwnPropertyDescriptor(
    context.Document.prototype,
    'cookie',
  );
  assert.equal(descriptor.get.call(context.document), '');
  descriptor.set.call(context.document, 'reflective_bypass=attempted');
  assert.deepEqual(calls.cookieWrites, []);
  assert.equal(descriptor.configurable, false);
});

test('fails closed when the document cookie accessor cannot be replaced', () => {
  assert.throws(
    () =>
      install((context) => {
        Object.defineProperty(context.Document.prototype, 'cookie', {
          configurable: false,
          get() {
            return 'visible_session=native';
          },
          set() {},
        });
      }),
    /could not install document\.cookie isolation/,
  );
});

test('re-enumerates and deletes IndexedDB recreated between cleanup passes', async () => {
  const native = fakeIndexedDb({
    snapshots: [
      [{ name: 'flutter' }, { name: 'shared_preferences' }],
      [],
      [{ name: 'recreated-by-legacy-realm' }],
      [],
    ],
  });
  const { context } = install((configuredContext) => {
    configuredContext.indexedDB = native.factory;
  });

  assert.throws(
    () => context.indexedDB.open('new-database'),
    /indexedDB\.open blocked/,
  );
  await assert.rejects(
    context.indexedDB.databases(),
    /indexedDB\.databases blocked/,
  );
  await context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb();
  await context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb();
  assert.deepEqual(native.deletes, [
    'flutter',
    'shared_preferences',
    'recreated-by-legacy-realm',
  ]);
  assert.equal(native.reads, 4);
  assert.equal(Object.isFrozen(context.indexedDB), true);
  assert.equal(
    Object.isFrozen(context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb),
    true,
  );
});

test('fails IndexedDB cleanup on blocked or errored deletion', async (t) => {
  for (const outcome of ['blocked', 'error']) {
    await t.test(outcome, async () => {
      const native = fakeIndexedDb({
        snapshots: [[{ name: 'legacy' }], []],
        deleteOutcome: outcome,
      });
      const { context } = install((configuredContext) => {
        configuredContext.indexedDB = native.factory;
      });

      await assert.rejects(
        context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb(),
        outcome === 'blocked' ? /deletion was blocked/ : /native delete failed/,
      );
      assert.deepEqual(native.deletes, ['legacy']);
    });
  }
});

test('fails IndexedDB cleanup on enumeration failure or remaining databases', async (t) => {
  await t.test('enumeration failure', async () => {
    const native = fakeIndexedDb({
      snapshots: [new Error('native enumeration failed')],
    });
    const { context } = install((configuredContext) => {
      configuredContext.indexedDB = native.factory;
    });
    await assert.rejects(
      context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb(),
      /native enumeration failed/,
    );
  });

  await t.test('remaining database', async () => {
    const native = fakeIndexedDb({
      snapshots: [[{ name: 'legacy' }], [{ name: 'legacy' }]],
    });
    const { context } = install((configuredContext) => {
      configuredContext.indexedDB = native.factory;
    });
    await assert.rejects(
      context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb(),
      /could not delete all existing IndexedDB databases/,
    );
  });
});

test('fails IndexedDB cleanup when existing databases cannot be enumerated', async () => {
  const { context } = install((configuredContext) => {
    configuredContext.indexedDB = {
      deleteDatabase() {
        throw new Error('must not be reached');
      },
    };
  });

  await assert.rejects(
    context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb(),
    /cannot enumerate and delete existing IndexedDB databases/,
  );
});

test('fails cleanup when native IndexedDB is absent while blocking new access', async () => {
  const { context } = install();

  await assert.rejects(
    context.__hustlEvaluatorRuntimeGuard.cleanupIndexedDb(),
    /cannot enumerate and delete existing IndexedDB databases/,
  );
  const descriptor = Object.getOwnPropertyDescriptor(context, 'indexedDB');
  assert.equal(descriptor.get, undefined);
  assert.equal(descriptor.value, context.indexedDB);
  assert.throws(
    () => context.indexedDB.deleteDatabase('new-database'),
    /indexedDB\.deleteDatabase blocked/,
  );
});

test('suppresses cross-origin resource attributes and DOM insertion quietly', () => {
  const { calls, context } = install();
  const head = new context.Element('head');

  const blockedScript = new context.HTMLScriptElement();
  blockedScript.setAttribute('src', 'https://accounts.example/client.js');
  blockedScript.setAttribute('id', 'identity-sdk');
  assert.equal(head.appendChild(blockedScript), blockedScript);
  assert.equal(head.children.length, 0);
  assert.equal(blockedScript.getAttribute('src'), null);

  const allowedScript = new context.HTMLScriptElement();
  allowedScript.src = '/flutter_bootstrap.js';
  head.appendChild(allowedScript);
  assert.equal(head.children.length, 1);
  assert.equal(
    allowedScript.getAttribute('src'),
    '/flutter_bootstrap.js',
  );

  const blockedImage = new context.HTMLImageElement();
  blockedImage.src = 'https://images.example/private.png';
  head.append(blockedImage);
  assert.equal(head.children.length, 1);

  const blockedAnchor = new context.HTMLAnchorElement();
  blockedAnchor.href = 'https://fdc.nal.usda.gov/';
  head.appendChild(blockedAnchor);
  blockedAnchor.click();
  assert.equal(head.children.length, 1);
  assert.deepEqual(calls.navigationClicks, []);

  const allowedAnchor = new context.HTMLAnchorElement();
  allowedAnchor.href = '/privacy';
  head.appendChild(allowedAnchor);
  allowedAnchor.click();
  assert.equal(head.children.length, 2);
  assert.deepEqual(calls.navigationClicks, ['/privacy']);

  head.insertAdjacentHTML(
    'beforeend',
    '<script src="https://cdn.example/sdk.js"></script>',
  );
  assert.equal(calls.insertedHtml.length, 0);
  head.insertAdjacentHTML('beforeend', '<img src="/safe.png">');
  assert.equal(calls.insertedHtml.length, 1);

  head.innerHTML = '<iframe src="https://auth.example/login"></iframe>';
  assert.equal(head.innerHTML, '');
  head.innerHTML = '<img src="/safe.png">';
  assert.equal(head.innerHTML, '<img src="/safe.png">');
  head.innerHTML = '<a href=https://external.example/>leave</a>';
  assert.equal(head.innerHTML, '<img src="/safe.png">');
  head.innerHTML = '<img src="https&#58;//images.example/private.png">';
  assert.equal(head.innerHTML, '<img src="/safe.png">');

  head.insertAdjacentHTML(
    'beforeend',
    '<script src="https&#x3a;//cdn.example/sdk.js"></script>',
  );
  assert.equal(calls.insertedHtml.length, 1);

  const iframe = new context.HTMLIFrameElement();
  iframe.srcdoc = '<script src="https://cdn.example/sdk.js"></script>';
  head.appendChild(iframe);
  assert.equal(head.children.length, 2);

  context.document.write('<script src="https://cdn.example/sdk.js"></script>');
  assert.deepEqual(calls.documentWrite, []);
  assert.deepEqual(calls.console, []);
});

test('fallback markup inspection fails closed on encoded resource URLs', () => {
  const { calls, context } = install((configuredContext) => {
    configuredContext.document.createElement = undefined;
  });
  const head = new context.Element('head');

  head.insertAdjacentHTML(
    'beforeend',
    '<img src="https&#58;//images.example/private.png">',
  );
  assert.deepEqual(calls.insertedHtml, []);

  head.insertAdjacentHTML('beforeend', '<img src="/safe.png">');
  assert.equal(calls.insertedHtml.length, 1);
});

test('installation is idempotent', () => {
  const { calls, context } = install();
  const guardedFetch = context.fetch;

  vm.runInNewContext(source, context, {
    filename: 'evaluator_runtime_guard.js',
  });

  assert.equal(context.fetch, guardedFetch);
  assert.equal(context.__hustlEvaluatorRuntimeGuard.active, true);
  assert.equal(context.__hustlEvaluatorRuntimeGuard.version, 2);
  assert.equal(
    context.document.documentElement.getAttribute(
      'data-hustl-evaluator-runtime-guard',
    ),
    '2',
  );
  assert.equal(context.__hustlEvaluatorRuntimeGuard.allowsUrl('/safe'), true);
  assert.equal(
    context.__hustlEvaluatorRuntimeGuard.allowsUrl('https://other.example'),
    false,
  );
  assert.deepEqual(calls.console, []);
});

test('does not install the active marker when storage cannot be replaced', () => {
  let failedContext;

  assert.throws(
    () =>
      install((context) => {
        failedContext = context;
        Object.defineProperty(context, 'localStorage', {
          configurable: false,
          writable: false,
          value: context.localStorage,
        });
      }),
    /could not install localStorage replacement/,
  );
  assert.equal(failedContext.__hustlEvaluatorRuntimeGuard, undefined);
});
