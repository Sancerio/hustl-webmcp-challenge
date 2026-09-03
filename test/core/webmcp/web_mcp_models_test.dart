import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/webmcp/web_mcp_models.dart';

void main() {
  test('registration JSON always carries the complete annotation contract', () {
    final tool = WebMcpToolDefinition(
      name: 'hustl_contract_probe',
      title: 'Contract probe',
      description: 'Verify the serialized WebMCP registration contract.',
      inputSchema: const {'type': 'object', 'additionalProperties': false},
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false,
      untrustedContentHint: true,
      handler: (_) async => const {'status': 'ready'},
    );

    expect(tool.toRegistrationJson(), {
      'name': 'hustl_contract_probe',
      'title': 'Contract probe',
      'description': 'Verify the serialized WebMCP registration contract.',
      'inputSchema': {'type': 'object', 'additionalProperties': false},
      'annotations': {
        'readOnlyHint': false,
        'destructiveHint': true,
        'idempotentHint': false,
        'openWorldHint': false,
        'untrustedContentHint': true,
      },
    });
  });
}
