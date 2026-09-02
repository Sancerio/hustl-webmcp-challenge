#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const automationRoot = path.resolve(process.argv[2] ?? '.github');
if (!fs.statSync(automationRoot).isDirectory()) {
  throw new Error(`GitHub automation directory is missing: ${automationRoot}`);
}

const automationFiles = [];
function visit(directory) {
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      visit(absolute);
    } else if (entry.isFile() && /\.ya?ml$/i.test(entry.name)) {
      automationFiles.push(absolute);
    }
  }
}
visit(automationRoot);

if (automationFiles.length === 0) {
  throw new Error('No GitHub automation YAML files were found.');
}

const failures = [];
for (const file of automationFiles.sort()) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const hasUsesKey = /(?:^|[,{\s-])["']?uses["']?\s*:/.test(lines[index]);
    if (!hasUsesKey) continue;
    const match = lines[index].match(
      /^\s*(?:-\s*)?["']?uses["']?\s*:\s*["']?([^\s"'#]+)["']?(?:\s*#.*)?$/,
    );
    if (!match) {
      failures.push(
        `${path.relative(automationRoot, file)}:${index + 1}: unparseable uses entry`,
      );
      continue;
    }
    const reference = match[1];
    if (reference.startsWith('./')) {
      failures.push(
        `${path.relative(automationRoot, file)}:${index + 1}: local actions are not permitted`,
      );
      continue;
    }
    if (!/^[^@\s]+@[0-9a-f]{40}$/i.test(reference)) {
      failures.push(`${path.relative(automationRoot, file)}:${index + 1}: ${reference}`);
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) console.error(failure);
  throw new Error('Every non-local GitHub Action must use a full commit SHA.');
}

console.log(
  `Verified action references in ${automationFiles.length} GitHub automation file(s).`,
);
