#!/usr/bin/env bash
# non-unix native tests for ocaml-findlib (run under MSYS2)
set -euo pipefail

echo "=== non-unix test suite for ocaml-findlib ==="

# Basic help test
echo "Testing ocamlfind install -help..."
ocamlfind install -help

# Basic functionality tests
echo "Testing ocamlfind printconf..."
ocamlfind printconf
ocamlfind printconf conf
ocamlfind printconf path
ocamlfind printconf stdlib

# List installed packages
echo "Testing ocamlfind list..."
ocamlfind list
ocamlfind list | grep -q findlib

# Query findlib package metadata
echo "Testing ocamlfind query..."
ocamlfind query findlib
ocamlfind query findlib -format '%v'

# Verify configuration file is readable
echo "Checking configuration file..."
test -f "$CONDA_PREFIX/etc/findlib.conf" || test -f "$CONDA_PREFIX/Library/etc/findlib.conf"

# Test ocamlfind can locate OCaml compiler
echo "Testing ocamlfind ocamlc/ocamlopt..."
ocamlfind ocamlc -version
ocamlfind ocamlopt -version

# Test compilation with ocamlfind (simple program)
echo "Testing bytecode compilation..."
echo 'print_endline "Hello from ocamlfind"' > test_hello.ml
ocamlfind ocamlc -o test_hello.exe test_hello.ml
./test_hello.exe

# Test native compilation
echo "Testing native compilation..."
ocamlfind ocamlopt -o test_hello_opt.exe test_hello.ml
./test_hello_opt.exe

# Cleanup
rm -f test_hello.ml test_hello.exe test_hello_opt.exe *.cmi *.cmo *.cmx *.o

echo "=== All non-unix tests passed ==="
