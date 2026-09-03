import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(
  new URL('../../web/webmcp_bridge.js', import.meta.url),
  'utf8',
);

function install(document, extras = {}) {
  const context = {
    AbortController,
    clearTimeout,
    document,
    setTimeout,
    ...extras,
  };
  context.globalThis = context;
  vm.runInNewContext(source, context, { filename: 'webmcp_bridge.js' });
  return context.hustlWebMcp;
}

test('reports unsupported when document.modelContext is absent', () => {
  const bridge = install({});

  assert.equal(bridge.supported, false);
});

test('keeps the API immutable while allowing Dart interop dispatch metadata', () => {
  const bridge = install({});

  assert.equal(Object.isExtensible(bridge), true);
  assert.equal(
    Object.getOwnPropertyDescriptor(bridge, 'registerTool').writable,
    false,
  );
  assert.doesNotThrow(() => {
    Object.defineProperty(bridge, '___dart_dispatch_record_test', {
      value: {},
    });
  });
});

test('registers, executes, and aborts the exact browser tool', async () => {
  let browserTool;
  let browserOptions;
  const bridge = install({
    modelContext: {
      async registerTool(tool, options) {
        browserTool = tool;
        browserOptions = options;
      },
    },
  });
  const definition = {
    name: 'hustl_test',
    title: 'Test',
    description: 'Bridge test',
    inputSchema: { type: 'object' },
    annotations: {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false,
      untrustedContentHint: true,
    },
  };

  const registrationId = await bridge.registerTool(
    JSON.stringify(definition),
    async (argumentsJson) =>
      JSON.stringify({ status: 'ok', arguments: JSON.parse(argumentsJson) }),
  );

  assert.equal(bridge.supported, true);
  assert.equal(browserTool.name, 'hustl_test');
  assert.equal(
    JSON.stringify(browserTool.annotations),
    JSON.stringify(definition.annotations),
  );
  assert.equal(browserOptions.signal.aborted, false);
  assert.equal(
    JSON.stringify(await browserTool.execute({ value: 7 })),
    JSON.stringify({ status: 'ok', arguments: { value: 7 } }),
  );

  bridge.unregisterTool(registrationId);
  assert.equal(browserOptions.signal.aborted, true);
});

test('aborts a controller when browser registration rejects', async () => {
  let signal;
  const bridge = install({
    modelContext: {
      async registerTool(_tool, options) {
        signal = options.signal;
        throw new Error('registration rejected');
      },
    },
  });

  await assert.rejects(
    bridge.registerTool(
      JSON.stringify({
        name: 'hustl_test',
        description: 'Bridge test',
        inputSchema: { type: 'object' },
      }),
      async () => '{}',
    ),
    /registration rejected/,
  );
  assert.equal(signal.aborted, true);
});
