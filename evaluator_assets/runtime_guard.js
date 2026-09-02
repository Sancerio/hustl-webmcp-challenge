(function installEvaluatorRuntimeGuard(global) {
  'use strict';
  if (global.__hustlEvaluatorGuardInstalled) return;

  const origin = global.location && global.location.origin;
  const securityError = (message) =>
    new DOMException(message || 'Blocked by evaluator', 'SecurityError');
  const memoryStorage = () => {
    const values = new Map();
    return Object.freeze({
      get length() { return values.size; },
      key(index) { return Array.from(values.keys())[index] || null; },
      getItem(key) { return values.has(String(key)) ? values.get(String(key)) : null; },
      setItem(key, value) { values.set(String(key), String(value)); },
      removeItem(key) { values.delete(String(key)); },
      clear() { values.clear(); },
    });
  };

  function assertSameOrigin(raw) {
    const url = new URL(String(raw), global.location.href);
    if (url.origin !== origin) {
      throw securityError('Cross-origin access blocked by evaluator');
    }
    return url;
  }

  function blockPersistentBrowserState() {
    Object.defineProperty(global, 'localStorage', {
      value: memoryStorage(),
      configurable: false,
      writable: false,
    });
    Object.defineProperty(global, 'sessionStorage', {
      value: memoryStorage(),
      configurable: false,
      writable: false,
    });

    const cookieOwner = global.Document && global.Document.prototype;
    if (!cookieOwner) throw securityError('Document cookie isolation unavailable');
    Object.defineProperty(cookieOwner, 'cookie', {
      configurable: false,
      get() { return ''; },
      set() { throw securityError('Cookies blocked by evaluator'); },
    });
  }

  function deleteDatabase(name) {
    return new Promise((resolve, reject) => {
      const request = global.indexedDB.deleteDatabase(name);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error || securityError('IndexedDB deletion failed'));
      request.onblocked = () => reject(securityError('IndexedDB deletion blocked'));
    });
  }

  async function clearAndBlockIndexedDb() {
    if (!global.indexedDB) return;
    if (typeof global.indexedDB.databases !== 'function') {
      throw securityError('IndexedDB inventory unavailable');
    }
    const databases = await global.indexedDB.databases();
    if (!Array.isArray(databases)) {
      throw securityError('IndexedDB inventory invalid');
    }
    const names = [];
    for (let index = 0; index < databases.length; index += 1) {
      if (!Object.prototype.hasOwnProperty.call(databases, index)) {
        throw securityError('IndexedDB inventory invalid');
      }
      const database = databases[index];
      if (!database || typeof database.name !== 'string') {
        throw securityError('IndexedDB inventory invalid');
      }
      names.push(database.name);
    }
    await Promise.all(names.map(deleteDatabase));
    const remaining = await global.indexedDB.databases();
    if (!Array.isArray(remaining) || remaining.length !== 0) {
      throw securityError('IndexedDB isolation verification failed');
    }
    const blocked = Object.freeze({
      open() { throw securityError('IndexedDB blocked by evaluator'); },
      deleteDatabase() { throw securityError('IndexedDB blocked by evaluator'); },
      databases: async () => [],
      cmp: global.indexedDB.cmp && global.indexedDB.cmp.bind(global.indexedDB),
    });
    Object.defineProperty(global, 'indexedDB', {
      value: blocked,
      configurable: false,
      writable: false,
    });
  }

  async function clearPlatformCaches() {
    let wasControlled = false;
    if (global.navigator && global.navigator.serviceWorker) {
      const serviceWorker = global.navigator.serviceWorker;
      wasControlled = serviceWorker.controller != null;
      const registrations = await serviceWorker.getRegistrations();
      await Promise.all(registrations.map((item) => item.unregister()));
      if ((await serviceWorker.getRegistrations()).length !== 0) {
        throw securityError('Service worker isolation failed');
      }
    }
    if (global.caches && typeof global.caches.keys === 'function') {
      const keys = await global.caches.keys();
      await Promise.all(keys.map((key) => global.caches.delete(key)));
      if ((await global.caches.keys()).length !== 0) {
        throw securityError('Cache isolation verification failed');
      }
    }
    return wasControlled;
  }

  blockPersistentBrowserState();

  const originalFetch = global.fetch && global.fetch.bind(global);
  if (originalFetch) {
    global.fetch = function guardedFetch(input, init) {
      assertSameOrigin(input && input.url ? input.url : input);
      return originalFetch(input, { ...(init || {}), credentials: 'omit' });
    };
  }

  for (const name of ['XMLHttpRequest', 'WebSocket', 'EventSource']) {
    if (!global[name]) continue;
    global[name] = function BlockedEvaluatorTransport() {
      throw securityError(`${name} blocked by evaluator`);
    };
  }

  if (global.navigator && typeof global.navigator.sendBeacon === 'function') {
    global.navigator.sendBeacon = function blockedBeacon() {
      throw securityError('sendBeacon blocked by evaluator');
    };
  }

  if (global.Element) {
    const originalSetAttribute = global.Element.prototype.setAttribute;
    global.Element.prototype.setAttribute = function guardedAttribute(name, value) {
      if (name === 'src' || name === 'href' || name === 'action') {
        assertSameOrigin(value);
      }
      return originalSetAttribute.apply(this, arguments);
    };
  }

  global.open = function blockedOpen() {
    throw securityError('Popup navigation blocked by evaluator');
  };

  if (global.HTMLAnchorElement) {
    const originalClick = global.HTMLAnchorElement.prototype.click;
    global.HTMLAnchorElement.prototype.click = function guardedClick() {
      assertSameOrigin(this.href);
      return originalClick.call(this);
    };
  }

  const ready = Promise.all([
    clearAndBlockIndexedDb(),
    clearPlatformCaches(),
  ]).then(([, wasControlled]) => {
    if (!wasControlled) return;
    global.location.reload();
    return new Promise(() => {});
  });
  Object.defineProperty(global, '__hustlEvaluatorReady', {
    value: ready,
    configurable: false,
    writable: false,
  });
  Object.defineProperty(global, '__hustlEvaluatorGuardInstalled', {
    value: true,
    configurable: false,
    writable: false,
  });
})(globalThis);
