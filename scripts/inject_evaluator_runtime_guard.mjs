import { access, copyFile, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const appDirectory = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const cliArguments = process.argv.slice(2);
const requireReleaseManifest = cliArguments.includes(
  '--require-release-manifest',
);
const pathArguments = cliArguments.filter(
  (argument) => argument !== '--require-release-manifest',
);
if (
  pathArguments.length > 1 ||
  pathArguments.some((argument) => argument.startsWith('--'))
) {
  throw new Error(
    'Usage: node scripts/inject_evaluator_runtime_guard.mjs [BUILD_DIRECTORY] [--require-release-manifest]',
  );
}
const buildDirectory = path.resolve(
  pathArguments[0] || path.join(appDirectory, 'build', 'web'),
);
const sourceGuard = path.join(
  appDirectory,
  'evaluator_assets',
  'evaluator_runtime_guard.js',
);
const builtGuard = path.join(buildDirectory, 'evaluator_runtime_guard.js');
const sourceBootstrap = path.join(
  appDirectory,
  'evaluator_assets',
  'evaluator_bootstrap.js',
);
const builtBootstrap = path.join(buildDirectory, 'evaluator_bootstrap.js');
const builtIndex = path.join(buildDirectory, 'index.html');
const builtFlutterBootstrap = path.join(buildDirectory, 'flutter_bootstrap.js');
const builtFontManifest = path.join(
  buildDirectory,
  'assets',
  'FontManifest.json',
);
const sourceReleaseManifest = path.join(
  appDirectory,
  'config',
  'webmcp_evaluator.release.json',
);
const builtReleaseManifest = path.join(buildDirectory, 'release.json');
const builtVercelConfig = path.join(buildDirectory, 'vercel.json');
const guardTag = '  <script src="evaluator_runtime_guard.js"></script>';
const expectedHeaders = new Map([
  ['cache-control', 'public, max-age=0, must-revalidate'],
  ['clear-site-data', '"cookies", "storage"'],
  [
    'content-security-policy',
    "default-src 'self'; base-uri 'self'; connect-src 'self'; font-src 'self' data:; form-action 'none'; frame-ancestors 'none'; frame-src 'none'; img-src 'self' data: blob:; manifest-src 'self'; media-src 'self' data: blob:; object-src 'none'; sandbox allow-same-origin allow-scripts; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; worker-src 'self' blob:",
  ],
  ['x-robots-tag', 'noindex'],
  ['referrer-policy', 'no-referrer'],
  ['x-content-type-options', 'nosniff'],
]);

async function validateVercelConfig() {
  let config;
  try {
    config = JSON.parse(await readFile(builtVercelConfig, 'utf8'));
  } catch (error) {
    throw new Error(
      `Evaluator Vercel config is missing or invalid: ${builtVercelConfig}`,
      { cause: error },
    );
  }

  const configuredHeaders = config?.headers;
  const globalHeaderRules = Array.isArray(configuredHeaders)
    ? configuredHeaders.filter((rule) => rule?.source === '/(.*)')
    : [];
  if (
    !Array.isArray(configuredHeaders) ||
    configuredHeaders.length !== 1 ||
    globalHeaderRules.length !== 1
  ) {
    throw new Error(
      'Evaluator Vercel config must contain exactly one global security-header rule.',
    );
  }
  const headers = globalHeaderRules[0]?.headers;
  if (!Array.isArray(headers) || headers.length !== expectedHeaders.size) {
    throw new Error(
      'Evaluator Vercel config does not contain the complete security-header contract.',
    );
  }

  const actualHeaders = new Map();
  for (const header of headers) {
    const key = typeof header?.key === 'string' ? header.key.toLowerCase() : '';
    if (!key || actualHeaders.has(key) || typeof header?.value !== 'string') {
      throw new Error(
        'Evaluator Vercel config contains an invalid or duplicate security header.',
      );
    }
    actualHeaders.set(key, header.value);
  }
  for (const [key, expectedValue] of expectedHeaders) {
    if (actualHeaders.get(key) !== expectedValue) {
      throw new Error(
        `Evaluator Vercel config has an invalid ${key} security header.`,
      );
    }
  }
}

await access(sourceGuard);
await access(sourceBootstrap);
await validateVercelConfig();
const originalIndex = await readFile(builtIndex, 'utf8');
const withoutExistingGuard = originalIndex.replace(
  /^\s*<script\s+src=["']evaluator_runtime_guard\.js["']><\/script>\s*$/gim,
  '',
);
const flutterBootstrapPattern =
  /^(\s*)<script\s+src=["']flutter_bootstrap\.js["'][^>]*><\/script>\s*$/im;
const evaluatorBootstrapPattern =
  /^(\s*)<script\s+src=["']evaluator_bootstrap\.js["'][^>]*><\/script>\s*$/im;
const webMcpBridgePattern =
  /^(\s*)<script\s+src=["']webmcp_bridge\.js["'][^>]*><\/script>\s*$/im;

if (
  !flutterBootstrapPattern.test(withoutExistingGuard) &&
  !evaluatorBootstrapPattern.test(withoutExistingGuard)
) {
  throw new Error(
    `Evaluator index is missing the Flutter bootstrap script: ${builtIndex}`,
  );
}

const gatedIndex = flutterBootstrapPattern.test(withoutExistingGuard)
  ? withoutExistingGuard.replace(
      flutterBootstrapPattern,
      '  <script src="evaluator_bootstrap.js"></script>',
    )
  : withoutExistingGuard;
const firstPartyScriptPattern = webMcpBridgePattern.test(gatedIndex)
  ? webMcpBridgePattern
  : evaluatorBootstrapPattern;
const guardedIndex = gatedIndex.replace(
  firstPartyScriptPattern,
  `${guardTag}\n$&`,
);
const guardPosition = guardedIndex.indexOf('evaluator_runtime_guard.js');
const bootstrapPosition = guardedIndex.indexOf('evaluator_bootstrap.js');
if (guardPosition < 0 || guardPosition >= bootstrapPosition) {
  throw new Error('Evaluator runtime guard must load before Flutter bootstrap.');
}

await copyFile(sourceGuard, builtGuard);
await copyFile(sourceBootstrap, builtBootstrap);
await writeFile(builtIndex, guardedIndex, 'utf8');

// CanvasKit otherwise downloads a default Roboto from fonts.gstatic.com even
// when every app style uses the bundled DM Sans family. Alias those same local
// files as Roboto in the evaluator manifest, without changing production's
// pubspec or web build.
const rawFontManifest = await readFile(builtFontManifest, 'utf8');
const fontManifest = JSON.parse(rawFontManifest);
if (!Array.isArray(fontManifest)) {
  throw new Error(`Evaluator font manifest is invalid: ${builtFontManifest}`);
}
const dmSans = fontManifest.find((family) => family?.family === 'DM Sans');
if (!Array.isArray(dmSans?.fonts) || dmSans.fonts.length === 0) {
  throw new Error('Evaluator build is missing its bundled DM Sans font family.');
}
const withoutRoboto = fontManifest.filter(
  (family) => family?.family !== 'Roboto',
);
const dmSansIndex = withoutRoboto.indexOf(dmSans);
withoutRoboto.splice(dmSansIndex + 1, 0, {
  family: 'Roboto',
  fonts: dmSans.fonts.map((font) => ({ ...font })),
});
await writeFile(
  builtFontManifest,
  `${JSON.stringify(withoutRoboto)}\n`,
  'utf8',
);

// Keep every future engine fallback request on the evaluator origin as an
// independent boundary, even for a glyph outside the aliased Roboto coverage.
const defaultLoaderCall = '_flutter.loader.load();';
const evaluatorLoaderCall =
  '_flutter.loader.load({config:{fontFallbackBaseUrl:"assets/"}});';
const rawFlutterBootstrap = await readFile(builtFlutterBootstrap, 'utf8');
const defaultLoaderCount =
  rawFlutterBootstrap.split(defaultLoaderCall).length - 1;
const evaluatorLoaderCount =
  rawFlutterBootstrap.split(evaluatorLoaderCall).length - 1;
if (defaultLoaderCount === 1 && evaluatorLoaderCount === 0) {
  await writeFile(
    builtFlutterBootstrap,
    rawFlutterBootstrap.replace(defaultLoaderCall, evaluatorLoaderCall),
    'utf8',
  );
} else if (defaultLoaderCount !== 0 || evaluatorLoaderCount !== 1) {
  throw new Error(
    `Evaluator Flutter loader call is ambiguous: ${builtFlutterBootstrap}`,
  );
}

try {
  const rawManifest = await readFile(sourceReleaseManifest, 'utf8');
  const manifest = JSON.parse(rawManifest);
  const objectIdPattern = /^[0-9a-f]{40,64}$/;
  const sourceSubdirectoryPattern =
    /^(?:\.|[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*)$/;
  const manifestKeys =
    manifest && typeof manifest === 'object' && !Array.isArray(manifest)
      ? Object.keys(manifest).sort()
      : [];
  if (
    manifestKeys.join(',') !==
      'schemaVersion,sourceSha,sourceSubdirectory,sourceTree' ||
    manifest.schemaVersion !== 1 ||
    !objectIdPattern.test(manifest.sourceSha) ||
    !objectIdPattern.test(manifest.sourceTree) ||
    typeof manifest.sourceSubdirectory !== 'string' ||
    !sourceSubdirectoryPattern.test(manifest.sourceSubdirectory) ||
    manifest.sourceSubdirectory.split('/').includes('..') ||
    (requireReleaseManifest && manifest.sourceSubdirectory !== 'hustl_app')
  ) {
    throw new Error(
      `Evaluator release manifest is invalid: ${sourceReleaseManifest}`,
    );
  }
  await writeFile(builtReleaseManifest, rawManifest, 'utf8');
  const builtManifest = await readFile(builtReleaseManifest, 'utf8');
  if (builtManifest !== rawManifest) {
    throw new Error(
      'Built evaluator release manifest does not exactly match its source manifest.',
    );
  }
} catch (error) {
  if (error?.code !== 'ENOENT') throw error;
  if (requireReleaseManifest) {
    throw new Error(
      `Release evaluator build requires a source provenance manifest: ${sourceReleaseManifest}`,
      { cause: error },
    );
  }
  await rm(builtReleaseManifest, { force: true });
}
