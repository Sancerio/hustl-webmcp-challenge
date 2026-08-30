import 'package:flutter/material.dart';

import '../../domain/models/connection.dart';

/// The Hustl connector (MCP server) URL the help steps tell users to paste into
/// their AI app. Defaults to the production MCP deployment; overridable at build
/// time via `--dart-define=HUSTL_MCP_CONNECTOR_URL=...` (e.g. a custom domain or
/// a local dev server), mirroring how [ApiConfig] sources HUSTL_API_BASE_URL.
const String kConnectorUrl = String.fromEnvironment(
  'HUSTL_MCP_CONNECTOR_URL',
  defaultValue: 'https://offline.invalid/mcp',
);

/// One client's worth of connect instructions: a heading, an optional vendor
/// brand mark, plain-sentence steps, and an optional copy-ready command block.
class ConnectHelpClient {
  const ConnectHelpClient({
    required this.id,
    required this.title,
    required this.vendor,
    required this.fallbackIcon,
    required this.steps,
    this.commandLabel,
    this.command,
  });

  /// Stable URL slug for the per-platform article route (`/connections/help/:id`).
  final String id;

  /// The per-client section heading (rendered as a step heading in the screen).
  final String title;

  /// Trusted vendor for the brand mark, or [ConnectionVendor.unknown] for CLIs.
  final ConnectionVendor vendor;

  /// Glyph shown when [vendor] is unknown (loopback CLIs have no brand mark).
  final IconData fallbackIcon;

  /// Ordered, plain-sentence steps.
  final List<String> steps;

  /// Optional caption above the command block (e.g. the file it goes in).
  final String? commandLabel;

  /// Optional copyable command / snippet.
  final String? command;
}

/// Per-client connect steps, mirroring `docs/help/connect-ai-to-hustl.md`.
const List<ConnectHelpClient> connectHelpClients = [
  ConnectHelpClient(
    id: 'claude',
    title: 'Claude (claude.ai / Desktop)',
    vendor: ConnectionVendor.claude,
    fallbackIcon: Icons.chat_bubble_outline,
    steps: [
      'Open Customize, then Connectors.',
      'Click +, then Add custom connector.',
      'Enter the connector URL above.',
      'Leave OAuth client ID and secret blank — Hustl registers the client '
          'automatically.',
      'Click Add, sign in with Google on the Hustl consent screen, and choose '
          'what to allow.',
    ],
  ),
  ConnectHelpClient(
    id: 'claude-code',
    title: 'Claude Code (CLI)',
    vendor: ConnectionVendor.unknown,
    fallbackIcon: Icons.terminal_outlined,
    steps: [
      'Run the command below to add Hustl as an http MCP server.',
      'Run /mcp inside Claude Code and authenticate when prompted — it opens '
          'the Hustl consent screen and finishes on a local callback.',
    ],
    commandLabel: 'Terminal',
    command: 'claude mcp add --transport http hustl $kConnectorUrl',
  ),
  ConnectHelpClient(
    id: 'codex',
    title: 'Codex',
    vendor: ConnectionVendor.codex,
    fallbackIcon: Icons.terminal_outlined,
    steps: [
      'Codex app: open Settings, then MCP servers, and click "+ Add server".',
      'Name it hustl, paste the connector URL above as the server URL, save, '
          'and make sure its toggle is on.',
      'Codex starts sign-in automatically — sign in with Google on the Hustl '
          'consent screen and choose what to allow. Then try "plan a pull day '
          'and propose it as a Hustl template."',
      'Prefer the CLI? Add the block below to ~/.codex/config.toml instead, '
          'then run "codex mcp login hustl" (run /mcp to confirm it connected).',
      'Headless or sandboxed and the local callback can\'t open? Set '
          'mcp_oauth_callback_port in config.toml and retry the login.',
    ],
    commandLabel: '~/.codex/config.toml (CLI option)',
    command: '[mcp_servers.hustl]\nurl = "$kConnectorUrl"',
  ),
  ConnectHelpClient(
    id: 'chatgpt',
    title: 'ChatGPT',
    vendor: ConnectionVendor.chatgpt,
    fallbackIcon: Icons.chat_bubble_outline,
    steps: [
      'Use ChatGPT on the web (chatgpt.com). Open Settings, then Apps & '
          'Connectors, then Advanced settings, and turn on Developer mode. '
          'It\'s available across plans on the web; on a Business/Enterprise '
          'workspace an admin may need to allow it first.',
      'Developer mode is what lets ChatGPT use a connector\'s tools (read and '
          'propose), not just search — so it\'s required here.',
      'Back in Apps & Connectors, click Create. Enter a name (Hustl) and a '
          'short description, paste the connector URL above into the Server URL '
          'field, and leave Authentication on OAuth (the default — Hustl signs '
          'you in per-user). Then click Create.',
      'When prompted, sign in with Google on the Hustl consent screen and '
          'choose what to allow. ChatGPT then validates the server and shows '
          'Hustl\'s available tools.',
      'In a new chat, click the + next to the message box, choose More, then '
          'pick Hustl — now ask, e.g. "summarize my last two weeks of '
          'training" or "draft a push day as a Hustl template."',
    ],
  ),
];

/// Look up a platform's help by its route slug, or null for an unknown id.
ConnectHelpClient? connectHelpClientById(String? id) {
  for (final client in connectHelpClients) {
    if (client.id == id) return client;
  }
  return null;
}
