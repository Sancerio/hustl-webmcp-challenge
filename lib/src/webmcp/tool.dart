typedef ToolHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> arguments);

class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.handler,
    required this.readOnlyHint,
    this.destructiveHint = false,
    this.idempotentHint = true,
    this.openWorldHint = false,
    this.untrustedContentHint = true,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final ToolHandler handler;
  final bool readOnlyHint;
  final bool destructiveHint;
  final bool idempotentHint;
  final bool openWorldHint;
  final bool untrustedContentHint;

  ToolDefinition withHandler(ToolHandler nextHandler) => ToolDefinition(
    name: name,
    title: title,
    description: description,
    inputSchema: inputSchema,
    handler: nextHandler,
    readOnlyHint: readOnlyHint,
    destructiveHint: destructiveHint,
    idempotentHint: idempotentHint,
    openWorldHint: openWorldHint,
    untrustedContentHint: untrustedContentHint,
  );

  Map<String, Object?> registrationJson() => {
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

abstract interface class ToolRegistration {
  void dispose();
}

abstract interface class ToolHost {
  bool get supported;
  Future<ToolRegistration?> register(ToolDefinition definition);
}
