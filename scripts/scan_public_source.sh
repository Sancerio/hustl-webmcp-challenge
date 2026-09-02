#!/usr/bin/env bash
set -euo pipefail

root="${1:-.}"
root="$(cd "$root" && pwd -P)"

node - "$root" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const root = fs.realpathSync(process.argv[2]);
const ignoredRootDirectories = new Set([
  '.git',
  '.dart_tool',
  '.playwright-cli',
  'build',
]);
const forbidden = [
  /\.vercel\.app/i,
  /supabase\.co/i,
  /accounts\.google\.com/i,
  /\/Users\/[A-Za-z0-9._-]+/,
  /\/Volumes\/[A-Za-z0-9._-]+/,
  /BEGIN [A-Z ]*PRIVATE KEY/,
  /service[_-]?role/i,
  /SUPABASE_[A-Z_]*(KEY|TOKEN)/,
  /Bearer\s+[A-Za-z0-9._~+/-]{16,}/,
  /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/,
  /AKIA[0-9A-Z]{16}/,
  /gh[pousr]_[A-Za-z0-9]{36,}/,
  /github_pat_[A-Za-z0-9_]{60,}/,
  /sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}/,
  /sk_live_[A-Za-z0-9]{16,}/,
  /AIza[0-9A-Za-z_-]{35}/,
  /xox[baprs]-[0-9A-Za-z-]{16,}/,
  /(?:API|ACCESS|SECRET|PRIVATE|AUTH|CLIENT)[_-]?(?:KEY|TOKEN|SECRET|PASSWORD)\s*[:=]\s*["']?[A-Za-z0-9._~+/-]{12,}/i,
];
const forbiddenFileNames = [
  /^\.env(?:\.|$)/i,
  /(?:^|[._-])credentials?(?:[._-]|$)/i,
  /(?:^|[._-])secrets?(?:[._-]|$)/i,
  /(?:^|[._-])tokens?(?:[._-]|$)/i,
  /(?:^|[._-])private[_-]?key(?:[._-]|$)/i,
  /^id_(?:rsa|dsa|ecdsa|ed25519)(?:\.|$)/i,
  /\.(?:key|pem|p12|pfx)$/i,
];

const findings = [];
function visit(directory) {
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const absolute = path.join(directory, entry.name);
    const relative = path.relative(root, absolute);
    if (ignoredRootDirectories.has(relative)) continue;
    const stat = fs.lstatSync(absolute);
    if (stat.isSymbolicLink()) {
      findings.push(`${relative}: symbolic link`);
      continue;
    }
    if (stat.isDirectory()) {
      visit(absolute);
      continue;
    }
    if (!stat.isFile()) continue;
    if (forbiddenFileNames.some(pattern => pattern.test(entry.name))) {
      findings.push(`${relative}: credential-bearing filename`);
    }
    const contents = fs.readFileSync(absolute, 'utf8');
    const lines = contents.split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      if (forbidden.some(pattern => pattern.test(lines[index]))) {
        findings.push(`${relative}:${index + 1}`);
      }
    }
  }
}

visit(root);
if (findings.length > 0) {
  for (const finding of findings) console.error(finding);
  console.error(
    'Public source scan found a forbidden origin, path, key, token, or link.',
  );
  process.exit(1);
}
NODE

echo "Public source scan passed."
