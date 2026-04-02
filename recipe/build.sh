#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# CRITICAL: Ensure we're using conda bash 5.2+, not system bash
# ==============================================================================
if [[ ${BASH_VERSINFO[0]} -lt 5 || (${BASH_VERSINFO[0]} -eq 5 && ${BASH_VERSINFO[1]} -lt 2) ]]; then
  echo "re-exec with conda bash..."
  if [[ -x "${BUILD_PREFIX}/bin/bash" ]]; then
    exec "${BUILD_PREFIX}/bin/bash" "$0" "$@"
  else
    echo "ERROR: Could not find conda bash at ${BUILD_PREFIX}/bin/bash"
    exit 1
  fi
fi

source "${RECIPE_DIR}/building/build_functions.sh"

if is_non_unix; then
  LIBDIR="${PREFIX}/Library"
else
  LIBDIR="${PREFIX}"
fi

./configure \
  -bindir "${LIBDIR}"/bin \
  -sitelib "${LIBDIR}"/lib/ocaml/site-lib \
  -config "${LIBDIR}"/etc/findlib.conf \
  -mandir "${LIBDIR}"/share/man || { cat ocargs.log; exit 1; }

# Patch findlib_config.mlp BEFORE compilation to use runtime env vars
# This ensures both bytecode (.cma) and native (.cmxa) use dynamic paths
# Use Sys.getenv_opt with fallback to avoid crashes if OCAMLLIB not set
sed -i 's#let ocaml_stdlib = "@STDLIB@";;#let ocaml_stdlib = match Sys.getenv_opt "OCAMLLIB" with Some v -> v | None -> failwith "OCAMLLIB environment variable not set";;#g' src/findlib/findlib_config.mlp

if is_cross_compile; then
  # CROSS-COMPILATION STRATEGY:
  # ocaml_<arch> packages provide cross-compiler wrappers that automatically
  # set OCAMLLIB, CONDA_OCAML_CC, etc. We only need to swap bare compiler
  # names so findlib's Makefile finds the cross-compilers.
  #
  # - ocamlfind is a BUILD TOOL - must be built with NATIVE compiler
  # - Libraries (.cma, .cmxa) should be built with CROSS compiler

  echo "=== STEP 1: Build ocamlfind with NATIVE compiler ==="
  make all

  echo "=== STEP 2: Build cross-compiled libraries ==="
  echo "  DEBUG: CONDA_OCAML_* environment variables:"
  env | grep CONDA_OCAML || echo "  DEBUG: No CONDA_OCAML_* variables found"
  echo "  DEBUG: target_platform=${target_platform:-unset}"
  echo "  DEBUG: build_platform=${build_platform:-unset}"
  swap_ocaml_compilers
  # CC/AR/RANLIB may not be set without compiler('c') activation.
  # OCaml cross-compiler packages set CONDA_OCAML_${target_id}_CC etc.
  target_id="${target_platform//-/_}"
  eval "cross_cc=\${CONDA_OCAML_${target_id}_CC}"
  eval "cross_ar=\${CONDA_OCAML_${target_id}_AR}"
  eval "cross_ranlib=\${CONDA_OCAML_${target_id}_RANLIB}"
  make opt CC="${CC:-${cross_cc}}" AR="${AR:-${cross_ar}}" RANLIB="${RANLIB:-${cross_ranlib}}"

  make install
else
  make all
  make opt
  make install
fi

# Move topfind to correct location and fix hardcoded paths
# On Unix: topfind is at ${BUILD_PREFIX}/lib/ocaml/topfind
# On non-unix: topfind is at ${BUILD_PREFIX}/Library/lib/ocaml/topfind
TOPFIND_SRC=""
if [[ -f "${BUILD_PREFIX}/lib/ocaml/topfind" ]]; then
  TOPFIND_SRC="${BUILD_PREFIX}/lib/ocaml/topfind"
elif [[ -f "${BUILD_PREFIX}/Library/lib/ocaml/topfind" ]]; then
  TOPFIND_SRC="${BUILD_PREFIX}/Library/lib/ocaml/topfind"
fi

if [[ -n "${TOPFIND_SRC}" ]]; then
  mv "${TOPFIND_SRC}" "${LIBDIR}/lib/ocaml/"
fi

# For non-unix: use forward slashes consistently (rattler-build uses forward slashes for prefix)
if is_non_unix; then
  # Write findlib.conf with forward slashes - Windows OCaml handles this fine
  sed -i "s@destdir=\"[^\"]*\"@destdir=\"${_PREFIX_}/Library/lib/ocaml/site-lib\"@g" "${LIBDIR}"/etc/findlib.conf
  sed -i "s@path=\"[^\"]*\"@path=\"${_PREFIX_}/Library/lib/ocaml;${_PREFIX_}/Library/lib/ocaml/site-lib\"@g" "${LIBDIR}"/etc/findlib.conf

  # Replace build_env with h_env in Makefile.config, keep forward slashes
  sed -i 's@build_env@h_env@g' "${LIBDIR}"/lib/ocaml/site-lib/findlib/Makefile.config
else
  sed -i "s@${BUILD_PREFIX}@${PREFIX}@g" "${LIBDIR}"/etc/findlib.conf "${LIBDIR}"/lib/ocaml/site-lib/findlib/Makefile.config
fi

for CHANGE in "activate" "deactivate"
do
  mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
  if is_non_unix; then
    cp "${RECIPE_DIR}/scripts/${CHANGE}.bat" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.bat"
  else
    cp "${RECIPE_DIR}/scripts/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
  fi
done
