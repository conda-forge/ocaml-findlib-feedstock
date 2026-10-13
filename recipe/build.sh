#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

./configure \
  -bindir "${PREFIX}"/bin \
  -sitelib "${PREFIX}"/lib/ocaml/site-lib \
  -config "${PREFIX}"/etc/findlib.conf \
  -mandir "${PREFIX}"/share/man || { cat ocargs.log; exit 1; }

# Patch findlib_config.mlp BEFORE compilation to use runtime env vars
# This ensures both bytecode (.cma) and native (.cmxa) use dynamic paths
# Use Sys.getenv_opt with fallback to avoid crashes if OCAMLLIB not set
sed -i 's#let ocaml_stdlib = "@STDLIB@";;#let ocaml_stdlib = match Sys.getenv_opt "OCAMLLIB" with Some v -> v | None -> failwith "OCAMLLIB environment variable not set";;#g' src/findlib/findlib_config.mlp

make all
make opt
make install

# Move topfind to correct location and fix hardcoded paths
# On Unix: topfind is at ${BUILD_PREFIX}/lib/ocaml/topfind
TOPFIND_SRC=""
if [[ -f "${BUILD_PREFIX}/lib/ocaml/topfind" ]]; then
  TOPFIND_SRC="${BUILD_PREFIX}/lib/ocaml/topfind"
fi

if [[ -n "${TOPFIND_SRC}" ]]; then
  mv "${TOPFIND_SRC}" "${LIBDIR}/lib/ocaml/"
fi

sed -i "s@${BUILD_PREFIX}@${PREFIX}@g" "${LIBDIR}"/etc/findlib.conf "${LIBDIR}"/lib/ocaml/site-lib/findlib/Makefile.config

for CHANGE in "activate" "deactivate"
do
  mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
  cp "${RECIPE_DIR}/scripts/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
