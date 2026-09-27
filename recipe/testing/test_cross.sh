#!/usr/bin/env bash
# Cross-compilation tests for ocaml-findlib
# Run via QEMU emulation on build machine
set -euo pipefail

echo "=== Cross-compilation test for ocaml-findlib ==="

# Verify binary architecture
echo "Checking binary architecture..."
file "$CONDA_PREFIX/bin/ocamlfind"
# readelf is not guaranteed in a cross test env; `file` already reports class/machine
if command -v readelf >/dev/null 2>&1; then
  readelf -h "$CONDA_PREFIX/bin/ocamlfind" | grep -E "Class:|Machine:"
fi

# Basic functionality tests via QEMU
echo "Testing ocamlfind install -help..."
ocamlfind install -help

echo "Testing ocamlfind printconf..."
ocamlfind printconf

echo "Testing ocamlfind list..."
ocamlfind list

echo "Verifying findlib is listed..."
ocamlfind list | grep -q findlib

echo "Testing ocamlfind query findlib..."
ocamlfind query findlib

echo "=== All cross-compilation tests passed ==="
