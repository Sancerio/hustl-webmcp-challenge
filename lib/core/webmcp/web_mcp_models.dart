typedef WebMcpToolHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> arguments);

class WebMcpToolDefinition {
  const WebMcpToolDefinition({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.readOnlyHint = false,
    this.untrustedContentHint = false,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final WebMcpToolHandler handler;
  final bool readOnlyHint;
  final bool untrustedContentHint;

  Map<String, Object?> toRegistrationJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': {
      'readOnlyHint': readOnlyHint,
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
