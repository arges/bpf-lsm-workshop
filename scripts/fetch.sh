#!/bin/sh
# Download URL to OUT and verify its SHA-512. OUT only ever exists complete
# and verified: the download goes to OUT.part and is renamed at the end.
set -eu
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 3 ] || die "usage: $0 <url> <sha512> <out>"
url=$1
want=$2
out=$3

need curl
[ -n "$want" ] || die "no checksum recorded for $(basename "$out"); add it to versions.mk"

if command -v sha512sum >/dev/null 2>&1; then
	sha512() { sha512sum "$1" | cut -d' ' -f1; }
else
	need shasum
	sha512() { shasum -a 512 "$1" | cut -d' ' -f1; }
fi

mkdir -p "$(dirname "$out")"
echo "fetching $url"
curl --fail --location --retry 3 --progress-bar --output "$out.part" "$url" ||
	die "download failed: $url"

got=$(sha512 "$out.part")
if [ "$got" != "$want" ]; then
	rm -f "$out.part"
	die "checksum mismatch for $(basename "$out")
  expected $want
  got      $got"
fi

mv "$out.part" "$out"
echo "verified $(basename "$out")"
