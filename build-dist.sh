#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${KASMVNC_DIST_DIR:-$SCRIPT_DIR/dist}"
KASMVNC_DIST_PATH="$DIST_DIR/kasmvnc"
KASMVNC_WWW_DIST_PATH="$DIST_DIR/kasmvnc-www"
KASMVNC_WEB_DIST_OVERRIDE="${KASMVNC_WEB_DIST_OVERRIDE:-}"

echo "📦 Building KasmVNC packages from local flake..."
echo "   flake: path:$SCRIPT_DIR"
echo "   dist:  $DIST_DIR"
if [ -n "$KASMVNC_WEB_DIST_OVERRIDE" ]; then
    echo "   web:   using prebuilt override at $KASMVNC_WEB_DIST_OVERRIDE"
else
    echo "   web:   building from flake package"
fi

mkdir -p "$DIST_DIR"

NIX_BUILD_ARGS=(--print-out-paths --no-link)
if [ -n "$KASMVNC_WEB_DIST_OVERRIDE" ]; then
    # Required for KASMVNC_WEB_DIST_OVERRIDE in flake evaluation.
    NIX_BUILD_ARGS+=(--impure)
fi

KASMVNC_OUT="$(nix build "${NIX_BUILD_ARGS[@]}" "path:$SCRIPT_DIR#kasmvnc" | tail -n1)"
if [ -n "$KASMVNC_WEB_DIST_OVERRIDE" ]; then
    KASMVNC_WWW_OUT="$KASMVNC_WEB_DIST_OVERRIDE"
else
    KASMVNC_WWW_OUT="$(nix build "${NIX_BUILD_ARGS[@]}" "path:$SCRIPT_DIR#kasmvnc-www" | tail -n1)"
fi

if [ ! -d "$KASMVNC_OUT" ]; then
    echo "❌ KasmVNC output path not found: $KASMVNC_OUT" >&2
    exit 1
fi

if [ ! -d "$KASMVNC_WWW_OUT" ]; then
    echo "❌ KasmVNC web output path not found: $KASMVNC_WWW_OUT" >&2
    exit 1
fi

rm -rf "$KASMVNC_DIST_PATH.tmp" "$KASMVNC_WWW_DIST_PATH.tmp"
mkdir -p "$KASMVNC_DIST_PATH.tmp" "$KASMVNC_WWW_DIST_PATH.tmp"

cp -a "$KASMVNC_OUT"/. "$KASMVNC_DIST_PATH.tmp"/
cp -a "$KASMVNC_WWW_OUT"/. "$KASMVNC_WWW_DIST_PATH.tmp"/

rm -rf "$KASMVNC_DIST_PATH" "$KASMVNC_WWW_DIST_PATH"
mv "$KASMVNC_DIST_PATH.tmp" "$KASMVNC_DIST_PATH"
mv "$KASMVNC_WWW_DIST_PATH.tmp" "$KASMVNC_WWW_DIST_PATH"

cat > "$DIST_DIR/BUILD_INFO" <<EOF_INFO
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
kasmvnc_out=$KASMVNC_OUT
kasmvnc_www_out=$KASMVNC_WWW_OUT
kasmvnc_www_override=$KASMVNC_WEB_DIST_OVERRIDE
EOF_INFO

echo "✅ Dist artifacts updated"
echo "   $KASMVNC_DIST_PATH"
echo "   $KASMVNC_WWW_DIST_PATH"
