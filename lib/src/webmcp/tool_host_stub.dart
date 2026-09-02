import 'tool.dart';

ToolHost createToolHost() => const UnsupportedToolHost();

class UnsupportedToolHost implements ToolHost {
  const UnsupportedToolHost();

  @override
  bool get supported => false;

  @override
  Future<ToolRegistration?> register(ToolDefinition definition) async => null;
}
