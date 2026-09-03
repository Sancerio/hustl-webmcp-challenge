(function installHustlEvaluatorRuntimeGuard() {
  'use strict';

  if (globalThis.__hustlEvaluatorRuntimeGuard) return;

  const pageUrl = new URL(globalThis.location.href);
  const blockedResourceNodes = new WeakSet();
  const nativeIndexedDb = globalThis.indexedDB;

  function networkUrl(input) {
    const value =
      input && typeof input === 'object' && 'url' in input
        ? input.url
        : input;
    try {
      return new URL(String(value), pageUrl.href);
    } catch (_) {
      return null;
    }
  }

  function isSameOriginHttpUrl(input) {
    const target = networkUrl(input);
    if (!target) return false;
    if (target.protocol === 'blob:') return target.origin === pageUrl.origin;
    return (
      (target.protocol === 'http:' || target.protocol === 'https:') &&
      target.origin === pageUrl.origin
    );
  }

  function blockedNetworkError(apiName) {
    return new TypeError(`${apiName} blocked by the evaluator runtime guard`);
  }

  function blockedStorageError(apiName) {
    return new TypeError(`${apiName} blocked by the evaluator runtime guard`);
  }

  function replaceValue(target, property, value) {
    try {
      Object.defineProperty(target, property, {
        configurable: true,
        writable: true,
        value,
      });
      return target[property] === value;
    } catch (_) {
      try {
        target[property] = value;
        return target[property] === value;
      } catch (_) {
        return false;
      }
    }
  }

  function replaceRequired(target, property, value, boundaryName) {
    if (!replaceValue(target, property, value)) {
      throw new Error(
        `Evaluator runtime guard could not install ${boundaryName}`,
      );
    }
  }

  function propertyOwner(target, property) {
    let owner = target;
    while (
      owner &&
      !Object.prototype.hasOwnProperty.call(owner, property)
    ) {
      owner = Object.getPrototypeOf(owner);
    }
    return owner || target;
  }

  const blockedIndexedDb = Object.freeze({
    cmp() {
      throw blockedStorageError('indexedDB.cmp');
    },
    databases() {
      return Promise.reject(blockedStorageError('indexedDB.databases'));
    },
    deleteDatabase() {
      throw blockedStorageError('indexedDB.deleteDatabase');
    },
    open() {
      throw blockedStorageError('indexedDB.open');
    },
  });
  replaceRequired(
    propertyOwner(globalThis, 'indexedDB'),
    'indexedDB',
    blockedIndexedDb,
    'IndexedDB replacement',
  );

  function deleteIndexedDbDatabase(name) {
    return new Promise((resolve, reject) => {
      let request;
      try {
        request = Reflect.apply(nativeIndexedDb.deleteDatabase, nativeIndexedDb, [
          name,
        ]);
      } catch (error) {
        reject(error);
        return;
      }
      if (!request || typeof request !== 'object') {
        reject(new Error(`Evaluator could not delete IndexedDB database ${name}`));
        return;
      }
      request.onsuccess = () => resolve();
      request.onerror = () =>
        reject(
          request.error ||
            new Error(`Evaluator could not delete IndexedDB database ${name}`),
        );
      request.onblocked = () =>
        reject(new Error(`Evaluator IndexedDB deletion was blocked for ${name}`));
    });
  }

  async function cleanupIndexedDb() {
    if (
      nativeIndexedDb == null ||
      typeof nativeIndexedDb.databases !== 'function' ||
      typeof nativeIndexedDb.deleteDatabase !== 'function'
    ) {
      throw new Error(
        'Evaluator cannot enumerate and delete existing IndexedDB databases',
      );
    }

    const databaseInfos = await Reflect.apply(
      nativeIndexedDb.databases,
      nativeIndexedDb,
      [],
    );
    if (!Array.isArray(databaseInfos)) {
      throw new Error('Evaluator received an invalid IndexedDB database list');
    }
    const names = new Set();
    for (const databaseInfo of databaseInfos) {
      if (typeof databaseInfo?.name !== 'string') {
        throw new Error('Evaluator found an unnamed IndexedDB database');
      }
      names.add(databaseInfo.name);
    }
    for (const name of names) await deleteIndexedDbDatabase(name);

    const remaining = await Reflect.apply(
      nativeIndexedDb.databases,
      nativeIndexedDb,
      [],
    );
    if (!Array.isArray(remaining) || remaining.length !== 0) {
      throw new Error(
        'Evaluator could not delete all existing IndexedDB databases',
      );
    }
  }
  Object.freeze(cleanupIndexedDb);

  const originalFetch = globalThis.fetch;
  if (typeof originalFetch === 'function') {
    const evaluatorFetch = function evaluatorFetch(input, init) {
      if (!isSameOriginHttpUrl(input)) {
        return Promise.reject(blockedNetworkError('fetch'));
      }
      return Reflect.apply(originalFetch, this, [
        input,
        { ...(init || {}), credentials: 'omit' },
      ]);
    };
    replaceRequired(
      propertyOwner(globalThis, 'fetch'),
      'fetch',
      evaluatorFetch,
      'fetch isolation',
    );
  }

  const navigatorObject = globalThis.navigator;
  if (typeof navigatorObject?.sendBeacon === 'function') {
    replaceRequired(
      propertyOwner(navigatorObject, 'sendBeacon'),
      'sendBeacon',
      function evaluatorSendBeacon() {
        return false;
      },
      'sendBeacon isolation',
    );
  }

  function blockConstructor(name) {
    const Original = globalThis[name];
    if (typeof Original !== 'function') return;

    function EvaluatorBlockedConstructor() {
      throw blockedNetworkError(name);
    }
    // Keep both objects extensible. Flutter's compiled JS runtime annotates
    // browser-interface constructors/prototypes with its dispatch record during
    // engine startup; freezing either receiver crashes before the first frame.
    // Construction still fails closed unconditionally.
    replaceRequired(
      propertyOwner(globalThis, name),
      name,
      EvaluatorBlockedConstructor,
      `${name} isolation`,
    );
  }

  blockConstructor('XMLHttpRequest');
  blockConstructor('WebSocket');
  blockConstructor('EventSource');

  const originalWindowOpen = globalThis.open;
  if (typeof originalWindowOpen === 'function') {
    replaceRequired(
      propertyOwner(globalThis, 'open'),
      'open',
      function evaluatorWindowOpen(url, ...args) {
        if (!isSameOriginHttpUrl(url)) return null;
        return Reflect.apply(originalWindowOpen, this, [url, ...args]);
      },
      'window.open navigation isolation',
    );
  }

  const resourceAttributes = Object.freeze({
    A: ['href', 'ping'],
    AREA: ['href', 'ping'],
    AUDIO: ['src'],
    BASE: ['href'],
    EMBED: ['src'],
    FORM: ['action'],
    IFRAME: ['src', 'srcdoc'],
    IMG: ['src', 'srcset'],
    INPUT: ['src'],
    LINK: ['href'],
    OBJECT: ['data'],
    SCRIPT: ['src'],
    SOURCE: ['src', 'srcset'],
    TRACK: ['src'],
    VIDEO: ['poster', 'src'],
  });

  function isAllowedResourceValue(attribute, value) {
    const raw = String(value || '').trim();
    if (!raw) return true;
    if (attribute === 'srcdoc') return false;
    if (attribute === 'ping') {
      return raw.split(/\s+/).filter(Boolean).every(isSameOriginHttpUrl);
    }
    if (attribute === 'srcset') {
      return raw
        .split(',')
        .map((candidate) => candidate.trim().split(/\s+/, 1)[0])
        .filter(Boolean)
        .every(isSameOriginHttpUrl);
    }
    return isSameOriginHttpUrl(raw);
  }

  function isResourceAttribute(node, attribute) {
    const tagName = String(node?.tagName || '').toUpperCase();
    return resourceAttributes[tagName]?.includes(String(attribute).toLowerCase());
  }

  function nodeHasBlockedResource(node) {
    if (!node || typeof node !== 'object') return false;
    if (blockedResourceNodes.has(node)) return true;

    const tagName = String(node.tagName || '').toUpperCase();
    const attributes = resourceAttributes[tagName] || [];
    for (const attribute of attributes) {
      const value = node.getAttribute?.(attribute);
      if (value && !isAllowedResourceValue(attribute, value)) return true;
    }

    if (typeof node.querySelectorAll === 'function') {
      const selector = Object.keys(resourceAttributes)
        .map((tag) => tag.toLowerCase())
        .join(',');
      for (const descendant of node.querySelectorAll(selector)) {
        if (nodeHasBlockedResource(descendant)) return true;
      }
    }
    return false;
  }

  const elementPrototype = globalThis.Element?.prototype;
  // Capture the native parser before replacing markup setters below. Setting
  // innerHTML on a template parses and decodes markup without activating its
  // resource nodes, which is safer and more accurate than URL-like regexes.
  const originalInnerHtmlDescriptor = elementPrototype
    ? Object.getOwnPropertyDescriptor(elementPrototype, 'innerHTML')
    : undefined;
  if (elementPrototype) {
    const originalSetAttribute = elementPrototype.setAttribute;
    if (typeof originalSetAttribute === 'function') {
      replaceRequired(
        elementPrototype,
        'setAttribute',
        function evaluatorSetAttribute(name, value) {
          const attribute = String(name).toLowerCase();
          if (
            isResourceAttribute(this, attribute) &&
            !isAllowedResourceValue(attribute, value)
          ) {
            blockedResourceNodes.add(this);
            return undefined;
          }
          if (isResourceAttribute(this, attribute)) {
            blockedResourceNodes.delete(this);
          }
          return Reflect.apply(originalSetAttribute, this, [name, value]);
        },
        'resource attribute isolation',
      );
    }

    const originalSetAttributeNs = elementPrototype.setAttributeNS;
    if (typeof originalSetAttributeNs === 'function') {
      replaceRequired(
        elementPrototype,
        'setAttributeNS',
        function evaluatorSetAttributeNs(namespace, name, value) {
          const attribute = String(name).toLowerCase();
          if (
            isResourceAttribute(this, attribute) &&
            !isAllowedResourceValue(attribute, value)
          ) {
            blockedResourceNodes.add(this);
            return undefined;
          }
          if (isResourceAttribute(this, attribute)) {
            blockedResourceNodes.delete(this);
          }
          return Reflect.apply(originalSetAttributeNs, this, [
            namespace,
            name,
            value,
          ]);
        },
        'namespaced resource attribute isolation',
      );
    }
  }

  function guardUrlProperty(constructorName, property, attribute = property) {
    const prototype = globalThis[constructorName]?.prototype;
    if (!prototype) return;
    let descriptorOwner = prototype;
    let descriptor = Object.getOwnPropertyDescriptor(descriptorOwner, property);
    while (!descriptor && descriptorOwner) {
      descriptorOwner = Object.getPrototypeOf(descriptorOwner);
      descriptor = descriptorOwner
        ? Object.getOwnPropertyDescriptor(descriptorOwner, property)
        : undefined;
    }
    if (!descriptor?.configurable || typeof descriptor.set !== 'function') {
      throw new Error(
        `Evaluator runtime guard could not isolate ${constructorName}.${property}`,
      );
    }

    try {
      Object.defineProperty(prototype, property, {
        ...descriptor,
        set(value) {
          if (!isAllowedResourceValue(attribute, value)) {
            blockedResourceNodes.add(this);
            return;
          }
          blockedResourceNodes.delete(this);
          Reflect.apply(descriptor.set, this, [value]);
        },
      });
    } catch (_) {
      throw new Error(
        `Evaluator runtime guard could not isolate ${constructorName}.${property}`,
      );
    }
  }

  for (const [constructorName, properties] of Object.entries({
    HTMLAnchorElement: ['href', 'ping'],
    HTMLAreaElement: ['href', 'ping'],
    HTMLBaseElement: ['href'],
    HTMLEmbedElement: ['src'],
    HTMLFormElement: ['action'],
    HTMLIFrameElement: ['src', 'srcdoc'],
    HTMLImageElement: ['src', 'srcset'],
    HTMLInputElement: ['src'],
    HTMLLinkElement: ['href'],
    HTMLMediaElement: ['src'],
    HTMLObjectElement: ['data'],
    HTMLScriptElement: ['src'],
    HTMLSourceElement: ['src', 'srcset'],
    HTMLTrackElement: ['src'],
    HTMLVideoElement: ['poster'],
  })) {
    for (const property of properties) {
      guardUrlProperty(constructorName, property);
    }
  }

  for (const constructorName of ['HTMLAnchorElement', 'HTMLAreaElement']) {
    const prototype = globalThis[constructorName]?.prototype;
    const originalClick = prototype?.click;
    if (typeof originalClick !== 'function') continue;
    replaceRequired(
      prototype,
      'click',
      function evaluatorNavigationClick(...args) {
        if (nodeHasBlockedResource(this)) return undefined;
        const href = this.getAttribute?.('href');
        const ping = this.getAttribute?.('ping');
        if (
          (href && !isSameOriginHttpUrl(href)) ||
          (ping && !isAllowedResourceValue('ping', ping))
        ) {
          return undefined;
        }
        return Reflect.apply(originalClick, this, args);
      },
      `${constructorName}.click navigation isolation`,
    );
  }

  const nodePrototype = globalThis.Node?.prototype;
  if (nodePrototype) {
    const originalAppendChild = nodePrototype.appendChild;
    const originalInsertBefore = nodePrototype.insertBefore;
    const originalReplaceChild = nodePrototype.replaceChild;

    if (typeof originalAppendChild === 'function') {
      replaceRequired(
        nodePrototype,
        'appendChild',
        function evaluatorAppendChild(node) {
          if (nodeHasBlockedResource(node)) return node;
          return Reflect.apply(originalAppendChild, this, [node]);
        },
        'appendChild resource isolation',
      );
    }
    if (typeof originalInsertBefore === 'function') {
      replaceRequired(
        nodePrototype,
        'insertBefore',
        function evaluatorInsertBefore(node, referenceNode) {
          if (nodeHasBlockedResource(node)) return node;
          return Reflect.apply(originalInsertBefore, this, [node, referenceNode]);
        },
        'insertBefore resource isolation',
      );
    }
    if (typeof originalReplaceChild === 'function') {
      replaceRequired(
        nodePrototype,
        'replaceChild',
        function evaluatorReplaceChild(node, oldChild) {
          if (nodeHasBlockedResource(node)) return oldChild;
          return Reflect.apply(originalReplaceChild, this, [node, oldChild]);
        },
        'replaceChild resource isolation',
      );
    }
  }

  function guardVariadicInsertion(prototype, methodName) {
    const original = prototype?.[methodName];
    if (typeof original !== 'function') return;
    replaceRequired(
      prototype,
      methodName,
      function evaluatorDomInsertion(...nodes) {
        if (nodes.some(nodeHasBlockedResource)) return undefined;
        return Reflect.apply(original, this, nodes);
      },
      `${methodName} resource isolation`,
    );
  }

  for (const prototype of [
    globalThis.Element?.prototype,
    globalThis.Document?.prototype,
    globalThis.DocumentFragment?.prototype,
  ]) {
    for (const method of [
      'append',
      'prepend',
      'before',
      'after',
      'replaceWith',
    ]) {
      guardVariadicInsertion(prototype, method);
    }
  }

  function fallbackMarkupHasBlockedResource(markup) {
    const source = String(markup);
    const tagPattern =
      /<(a|area|audio|base|embed|form|iframe|img|input|link|object|script|source|track|video)\b[^>]*>/gi;
    for (const tagMatch of source.matchAll(tagPattern)) {
      const tagName = tagMatch[1].toUpperCase();
      const attributes = resourceAttributes[tagName] || [];
      for (const attribute of attributes) {
        const escapedAttribute = attribute.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const attributePattern = new RegExp(
          `\\b${escapedAttribute}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>\\x60]+))`,
          'gi',
        );
        for (const attributeMatch of tagMatch[0].matchAll(attributePattern)) {
          const value =
            attributeMatch[1] ?? attributeMatch[2] ?? attributeMatch[3] ?? '';
          // Without an inert DOM parser, fail closed on character references.
          // A browser can decode those into URL syntax (for example, an
          // entity-encoded colon) after a textual URL check has allowed them.
          if (/&(?:#(?:x[0-9a-f]+|\d+)|[a-z][a-z0-9]+);?/i.test(value)) {
            return true;
          }
          if (!isAllowedResourceValue(attribute, value)) return true;
        }
      }
    }
    return false;
  }

  function markupHasBlockedResource(markup) {
    const source = String(markup);
    const createElement = globalThis.document?.createElement;
    if (
      typeof createElement === 'function' &&
      typeof originalInnerHtmlDescriptor?.set === 'function'
    ) {
      try {
        const template = Reflect.apply(createElement, globalThis.document, [
          'template',
        ]);
        Reflect.apply(originalInnerHtmlDescriptor.set, template, [source]);
        return nodeHasBlockedResource(template.content ?? template);
      } catch (_) {
        // Fall through to the conservative textual check if the host has an
        // incomplete or non-standard DOM implementation.
      }
    }
    return fallbackMarkupHasBlockedResource(source);
  }

  if (elementPrototype) {
    const originalInsertAdjacentHtml = elementPrototype.insertAdjacentHTML;
    if (typeof originalInsertAdjacentHtml === 'function') {
      replaceRequired(
        elementPrototype,
        'insertAdjacentHTML',
        function evaluatorInsertAdjacentHtml(position, markup) {
          if (markupHasBlockedResource(markup)) return undefined;
          return Reflect.apply(originalInsertAdjacentHtml, this, [position, markup]);
        },
        'insertAdjacentHTML resource isolation',
      );
    }

    for (const property of ['innerHTML', 'outerHTML']) {
      const descriptor = Object.getOwnPropertyDescriptor(elementPrototype, property);
      if (!descriptor?.configurable || typeof descriptor.set !== 'function') continue;
      Object.defineProperty(elementPrototype, property, {
        ...descriptor,
        set(value) {
          if (markupHasBlockedResource(value)) return;
          Reflect.apply(descriptor.set, this, [value]);
        },
      });
    }
  }

  const documentObject = globalThis.document;
  if (documentObject) {
    try {
      let cookieOwner = documentObject;
      let cookieDescriptor;
      while (cookieOwner && !cookieDescriptor) {
        cookieDescriptor = Object.getOwnPropertyDescriptor(cookieOwner, 'cookie');
        if (!cookieDescriptor) cookieOwner = Object.getPrototypeOf(cookieOwner);
      }
      if (
        cookieDescriptor &&
        (!cookieDescriptor.configurable ||
          typeof cookieDescriptor.get !== 'function' ||
          typeof cookieDescriptor.set !== 'function')
      ) {
        throw new Error('document.cookie accessor cannot be replaced');
      }
      Object.defineProperty(cookieOwner || documentObject, 'cookie', {
        configurable: false,
        enumerable: cookieDescriptor?.enumerable ?? true,
        get() {
          return '';
        },
        set() {},
      });
      if (documentObject.cookie !== '') {
        throw new Error('cookie getter remained readable');
      }
    } catch (_) {
      throw new Error(
        'Evaluator runtime guard could not install document.cookie isolation',
      );
    }
    if (typeof documentObject.write === 'function') {
      replaceRequired(
        documentObject,
        'write',
        function evaluatorDocumentWrite() {},
        'document.write isolation',
      );
    }
    if (typeof documentObject.writeln === 'function') {
      replaceRequired(
        documentObject,
        'writeln',
        function evaluatorDocumentWriteln() {},
        'document.writeln isolation',
      );
    }
  }

  function createMemoryStorage() {
    const values = Object.create(null);
    const keys = [];
    const storage = {};
    Object.defineProperties(storage, {
      length: {
        enumerable: true,
        get() {
          return keys.length;
        },
      },
      clear: {
        enumerable: true,
        value() {
          for (const key of keys) delete values[key];
          keys.length = 0;
        },
      },
      getItem: {
        enumerable: true,
        value(key) {
          const normalized = String(key);
          return Object.prototype.hasOwnProperty.call(values, normalized)
            ? values[normalized]
            : null;
        },
      },
      key: {
        enumerable: true,
        value(index) {
          const normalized = Number(index);
          return Number.isInteger(normalized) && normalized >= 0
            ? keys[normalized] ?? null
            : null;
        },
      },
      removeItem: {
        enumerable: true,
        value(key) {
          const normalized = String(key);
          if (!Object.prototype.hasOwnProperty.call(values, normalized)) return;
          delete values[normalized];
          keys.splice(keys.indexOf(normalized), 1);
        },
      },
      setItem: {
        enumerable: true,
        value(key, value) {
          const normalized = String(key);
          if (!Object.prototype.hasOwnProperty.call(values, normalized)) {
            keys.push(normalized);
          }
          values[normalized] = String(value);
        },
      },
    });
    // Flutter's compiled JS interop adds an internal dispatch record to Web API
    // receivers. Leave this synthetic Storage object extensible for that one
    // runtime requirement while keeping its public API descriptors immutable.
    return storage;
  }

  const localMemoryStorage = createMemoryStorage();
  const sessionMemoryStorage = createMemoryStorage();
  replaceRequired(
    propertyOwner(globalThis, 'localStorage'),
    'localStorage',
    localMemoryStorage,
    'localStorage replacement',
  );
  replaceRequired(
    propertyOwner(globalThis, 'sessionStorage'),
    'sessionStorage',
    sessionMemoryStorage,
    'sessionStorage replacement',
  );

  Object.defineProperty(globalThis, '__hustlEvaluatorRuntimeGuard', {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze({
      active: true,
      allowsUrl: isSameOriginHttpUrl,
      cleanupIndexedDb,
      version: 2,
    }),
  });

  // Browser QA runs through a deliberately read-only page scope that does not
  // expose custom Window properties. Mirror only the non-sensitive version on
  // the root element after the authoritative guard marker is active.
  documentObject?.documentElement?.setAttribute(
    'data-hustl-evaluator-runtime-guard',
    '2',
  );
})();
