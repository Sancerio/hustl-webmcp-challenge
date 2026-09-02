#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "Usage: install_gitleaks.sh <absolute-destination>" >&2
  exit 64
fi
if [[ -e "$1" ]]; then
  echo "Gitleaks destination already exists: $1" >&2
  exit 64
fi

version=8.30.1
case "$(uname -s):$(uname -m)" in
  Linux:x86_64)
    archive_name="gitleaks_${version}_linux_x64.tar.gz"
    archive_sha256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
    ;;
  Darwin:arm64)
    archive_name="gitleaks_${version}_darwin_arm64.tar.gz"
    archive_sha256=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5
    ;;
  *)
    echo "Unsupported Gitleaks platform: $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

destination="$1"
parent="$(cd "$(dirname "$destination")" && pwd -P)"
scratch="$(mktemp -d "$parent/.gitleaks-install.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT
archive_url="https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive_name}"

curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  "$archive_url" --output "$scratch/$archive_name"
actual_sha256="$(shasum -a 256 "$scratch/$archive_name" | awk '{print $1}')"
if [[ "$actual_sha256" != "$archive_sha256" ]]; then
  echo "Gitleaks archive checksum mismatch." >&2
  exit 1
fi
mkdir "$destination"
tar -xzf "$scratch/$archive_name" -C "$destination" gitleaks
test "$("$destination/gitleaks" version)" = "$version"
