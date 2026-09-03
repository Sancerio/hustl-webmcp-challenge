typedef WebMcpToolHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> arguments);

class WebMcpToolDefinition {
  const WebMcpToolDefinition({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.handler,
    required this.readOnlyHint,
    required this.destructiveHint,
    required this.idempotentHint,
    required this.openWorldHint,
    this.untrustedContentHint = false,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final WebMcpToolHandler handler;
  final bool readOnlyHint;
  final bool destructiveHint;
  final bool idempotentHint;
  final bool openWorldHint;
  final bool untrustedContentHint;

  Map<String, Object?> toRegistrationJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': {
      'readOnlyHint': readOnlyHint,
      'destructiveHint': destructiveHint,
      'idempotentHint': idempotentHint,
      'openWorldHint': openWorldHint,
      'untrustedContentHint': untrustedContentHint,
    },
  };
}

abstract interface class WebMcpRegistration {
  void dispose();
}

abstract interface class WebMcpHost {
  bool get isSupported;

  Future<WebMcpRegistration?> registerTool(WebMcpToolDefinition tool);
}
