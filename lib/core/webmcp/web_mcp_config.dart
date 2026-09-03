/// Compile-time gate for Hustl's browser-provided WebMCP tools.
///
/// The feature stays off in ordinary builds until the draft browser API and
/// the hackathon distribution are explicitly requested together.
const bool kWebMcpEnabled = bool.fromEnvironment(
  'HUSTL_WEBMCP',
  defaultValue: false,
);
