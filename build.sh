#!/bin/sh
# Build the flashable Magisk module zip into dist/.
set -e
cd "$(dirname "$0")"
version=$(sed -n 's/^version=//p' module/module.prop)
[ -n "$version" ] || { echo "no version in module/module.prop"; exit 1; }
mkdir -p dist
out="dist/vpn-tether-$version.zip"
rm -f "$out"
(cd module && zip -qr -X "../$out" . -x '*.DS_Store')
echo "built $out"
unzip -l "$out"
