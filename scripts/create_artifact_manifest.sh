#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: create_artifact_manifest.sh <build-directory> <output-directory>" >&2
  exit 64
fi

build_dir="$(cd "$1" && pwd -P)"
output_parent="$(cd "$(dirname "$2")" && pwd -P)"
output_dir="$output_parent/$(basename "$2")"
if [[ -e "$output_dir" ]]; then
  echo "Artifact manifest output already exists: $output_dir" >&2
  exit 64
fi
case "$output_dir" in
  "$build_dir"|"$build_dir"/*)
    echo "Artifact metadata must be outside the build directory." >&2
    exit 64
    ;;
esac
mkdir "$output_dir"

manifest="$output_dir/build.sha256"
files="$output_dir/files.txt"
while IFS= read -r -d '' path; do
  relative="${path#"$build_dir"/}"
  if [[ "$relative" == *$'\n'* ]]; then
    echo "Build contains a filename with a newline." >&2
    exit 1
  fi
  printf '%s\n' "$relative"
done < <(find "$build_dir" -type f -print0) | LC_ALL=C sort > "$files"
if [[ ! -s "$files" ]]; then
  echo "Build directory contains no files." >&2
  exit 1
fi

while IFS= read -r relative; do
  digest="$(shasum -a 256 "$build_dir/$relative" | awk '{print $1}')"
  printf '%s  %s\n' "$digest" "$relative" >> "$manifest"
done < "$files"

source_commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"
if [[ ! "$source_commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "Source commit must be a full 40-character Git object ID." >&2
  exit 1
fi
flutter_version="$(flutter --version --machine | node -e '
let input = "";
process.stdin.on("data", chunk => { input += chunk; });
process.stdin.on("end", () => {
  const parsed = JSON.parse(input);
  process.stdout.write(parsed.frameworkVersion);
});
')"
if [[ ! "$flutter_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "Flutter returned an unexpected framework version." >&2
  exit 1
fi
node_version="$(node --version)"
if [[ ! "$node_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Node returned an unexpected version." >&2
  exit 1
fi
manifest_digest="$(shasum -a 256 "$manifest" | awk '{print $1}')"
file_count="$(wc -l < "$files" | tr -d ' ')"
SOURCE_COMMIT="$source_commit" \
FLUTTER_VERSION="$flutter_version" \
NODE_VERSION="$node_version" \
FILE_COUNT="$file_count" \
MANIFEST_DIGEST="$manifest_digest" \
node - "$output_dir/provenance.json" <<'NODE'
const fs = require('node:fs');

const optional = value => value && value.length > 0 ? value : null;
const provenance = {
  schemaVersion: 1,
  sourceCommit: process.env.SOURCE_COMMIT,
  flutterVersion: process.env.FLUTTER_VERSION,
  nodeVersion: process.env.NODE_VERSION,
  fileCount: Number.parseInt(process.env.FILE_COUNT, 10),
  manifestSha256: process.env.MANIFEST_DIGEST,
  runner: {
    os: optional(process.env.RUNNER_OS) ?? process.platform,
    arch: optional(process.env.RUNNER_ARCH) ?? process.arch,
    imageOs: optional(process.env.ImageOS),
    imageVersion: optional(process.env.ImageVersion),
  },
};
fs.writeFileSync(process.argv[2], `${JSON.stringify(provenance, null, 2)}\n`);
NODE

rm "$files"
echo "Artifact manifest created at $output_dir"
