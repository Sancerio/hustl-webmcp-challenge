import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../web/webmcp_bridge.js', import.meta.url), 'utf8');

test('bridge registers and aborts route-owned browser tools', async () => {
  const received = [];
  const context = {
    AbortController,
    document: {
      modelContext: {
        registerTool: async (tool, options) => received.push({ tool, options }),
      },
    },
  };
  context.globalThis = context;
  vm.runInNewContext(source, context);

  const id = await context.hustlEvaluatorWebMcp.registerTool(
    JSON.stringify({
      name: 'test_tool',
      annotations: { readOnlyHint: true, untrustedContentHint: true },
    }),
    async () => JSON.stringify({ status: 'ready' }),
  );
  assert.equal(received.length, 1);
  assert.equal(received[0].tool.name, 'test_tool');
  assert.equal(
    JSON.stringify(await received[0].tool.execute({})),
    JSON.stringify({ status: 'ready' }),
  );
  assert.equal(received[0].options.signal.aborted, false);
  context.hustlEvaluatorWebMcp.unregisterTool(id);
  assert.equal(received[0].options.signal.aborted, true);
});
