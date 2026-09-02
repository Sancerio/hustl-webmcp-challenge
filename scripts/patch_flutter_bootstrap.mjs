import { readFileSync, writeFileSync } from 'node:fs';

const bootstrapPath = process.argv[2];
if (!bootstrapPath) {
  throw new Error('Usage: patch_flutter_bootstrap.mjs <flutter_bootstrap.js>');
}

const source = readFileSync(bootstrapPath, 'utf8');
const defaultLoader = '_flutter.loader.load();';
const localFallbackLoader =
  '_flutter.loader.load({config:{fontFallbackBaseUrl:"assets/"}});';
const matches = source.split(defaultLoader).length - 1;

if (matches !== 1 || source.includes(localFallbackLoader)) {
  throw new Error(
    `Expected exactly one unpatched Flutter loader call; found ${matches}.`,
  );
}

writeFileSync(
  bootstrapPath,
  source.replace(defaultLoader, localFallbackLoader),
  'utf8',
);
