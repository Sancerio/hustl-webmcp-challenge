import 'web_mcp_models.dart';

WebMcpHost createWebMcpHost() => const UnsupportedWebMcpHost();

class UnsupportedWebMcpHost implements WebMcpHost {
  const UnsupportedWebMcpHost();

  @override
  bool get isSupported => false;

  @override
  Future<WebMcpRegistration?> registerTool(WebMcpToolDefinition tool) async =>
      null;
}
