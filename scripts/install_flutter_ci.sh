#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "Usage: install_flutter_ci.sh <absolute-destination>" >&2
  exit 64
fi
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "The public CI Flutter installer supports Linux x86_64 only." >&2
  exit 1
fi
if [[ -e "$1" ]]; then
  echo "Flutter destination already exists: $1" >&2
  exit 64
fi

version=3.38.7
archive_name="flutter_linux_${version}-stable.tar.xz"
archive_sha256=2d72de31119ccba1421391aa9ab53891a3e4905987a13f8272766ad78e3bbf93
archive_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$archive_name"
destination="$1"
parent="$(cd "$(dirname "$destination")" && pwd -P)"
scratch="$(mktemp -d "$parent/.flutter-install.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  "$archive_url" --output "$scratch/$archive_name"
actual_sha256="$(shasum -a 256 "$scratch/$archive_name" | awk '{print $1}')"
if [[ "$actual_sha256" != "$archive_sha256" ]]; then
  echo "Flutter archive checksum mismatch." >&2
  exit 1
fi
tar -xJf "$scratch/$archive_name" -C "$scratch"
mv "$scratch/flutter" "$destination"
"$destination/bin/flutter" --version
