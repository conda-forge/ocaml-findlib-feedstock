#!/usr/bin/env bash
# Native tests for ocaml-findlib (full test suite)
set -euo pipefail

echo "=== Native test suite for ocaml-findlib ==="

# Basic help test
echo "Testing ocamlfind install -help..."
ocamlfind install -help

# Basic functionality tests
echo "Testing ocamlfind printconf..."
ocamlfind printconf
ocamlfind printconf conf
ocamlfind printconf path
ocamlfind printconf stdlib

# List installed packages (findlib should find itself and stdlib packages)
echo "Testing ocamlfind list..."
ocamlfind list
ocamlfind list | grep -q findlib

# Query findlib package metadata
echo "Testing ocamlfind query..."
ocamlfind query findlib
ocamlfind query findlib -format '%v'

# Verify configuration file is readable
echo "Checking configuration file..."
test -f "$CONDA_PREFIX/etc/findlib.conf"

# Test ocamlfind can locate OCaml compiler
echo "Testing ocamlfind ocamlc/ocamlopt..."
ocamlfind ocamlc -version
ocamlfind ocamlopt -version

# Test compilation with ocamlfind (simple program)
echo "Testing bytecode compilation..."
echo 'print_endline "Hello from ocamlfind"' > test_hello.ml
ocamlfind ocamlc -o test_hello test_hello.ml
./test_hello

# Test native compilation
echo "Testing native compilation..."
ocamlfind ocamlopt -o test_hello_opt test_hello.ml
./test_hello_opt

# Test linking against findlib package (bytecode and native)
echo "Testing linking with findlib package..."
ocamlfind ocamlc -package findlib -linkpkg -o test_findlib test_hello.ml
./test_findlib
ocamlfind ocamlopt -package findlib -linkpkg -o test_findlib_opt test_hello.ml
./test_findlib_opt

# Test topfind in OCaml toplevel (verifies path relocation works)
echo "Testing topfind in toplevel..."
# Use echo with heredoc for better compatibility, capture output for debugging
TOPFIND_OUTPUT=$(printf '%s\n' '#use "topfind";;' '#list;;' '#quit;;' | ocaml -stdin 2>&1) || true
echo "Toplevel output:"
echo "$TOPFIND_OUTPUT"
echo "$TOPFIND_OUTPUT" | grep -q findlib || {
  echo "ERROR: 'findlib' not found in toplevel output"
  exit 1
}

# Cleanup
rm -f test_hello.ml test_hello test_hello_opt test_findlib test_findlib_opt

echo "=== All native tests passed ==="
