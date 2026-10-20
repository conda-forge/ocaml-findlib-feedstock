#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if [[ "${target_platform}" == win-* ]]; then
  ./configure \
    -bindir "${LIBRARY_PREFIX}"/bin \
    -sitelib "${LIBRARY_PREFIX}"/lib/ocaml/site-lib \
    -config "${LIBRARY_PREFIX}"/etc/findlib.conf \
    -mandir "${LIBRARY_PREFIX}"/share/man || { cat ocargs.log; exit 1; }
else
  ./configure \
    -bindir "${PREFIX}"/bin \
    -sitelib "${PREFIX}"/lib/ocaml/site-lib \
    -config "${PREFIX}"/etc/findlib.conf \
    -mandir "${PREFIX}"/share/man || { cat ocargs.log; exit 1; }
fi

# Patch findlib_config.mlp BEFORE compilation to use runtime env vars
# This ensures both bytecode (.cma) and native (.cmxa) use dynamic paths
# Use Sys.getenv_opt with fallback to avoid crashes if OCAMLLIB not set
sed -i 's#let ocaml_stdlib = "@STDLIB@";;#let ocaml_stdlib = match Sys.getenv_opt "OCAMLLIB" with Some v -> v | None -> failwith "OCAMLLIB environment variable not set";;#g' src/findlib/findlib_config.mlp

make all
make opt
make install

# Move topfind to correct location and fix hardcoded paths
# On Unix: topfind is at ${BUILD_PREFIX}/lib/ocaml/topfind
# On non-unix: topfind is at ${BUILD_PREFIX}/Library/lib/ocaml/topfind
TOPFIND_SRC="${BUILD_PREFIX}/lib/ocaml/topfind"
if [[ -f "${TOPFIND_SRC}" ]]; then
  mv "${TOPFIND_SRC}" "${PREFIX}/lib/ocaml/"
fi
TOPFIND_SRC="${BUILD_PREFIX}/Library/lib/ocaml/topfind"
if [[ -f "${TOPFIND_SRC}" ]]; then
  mv "${TOPFIND_SRC}" "${LIBRARY_PREFIX}/lib/ocaml/"
fi

if [[ "${target_platform}" == win-* ]]; then
  # rattler-build hands PREFIX to bash in native (backslash) form on Windows;
  # findlib.conf is META syntax, where backslash is an escape character.
  PREFIX_FWD="${PREFIX//\\//}"

  sed -i "s@destdir=\"[^\"]*\"@destdir=\"${PREFIX_FWD}/Library/lib/ocaml/site-lib\"@g" "${LIBRARY_PREFIX}"/etc/findlib.conf
  sed -i "s@path=\"[^\"]*\"@path=\"${PREFIX_FWD}/Library/lib/ocaml;${PREFIX_FWD}/Library/lib/ocaml/site-lib\"@g" "${LIBRARY_PREFIX}"/etc/findlib.conf

  # Replace build_env with h_env in Makefile.config, keep forward slashes
  sed -i 's@build_env@h_env@g' "${LIBRARY_PREFIX}"/lib/ocaml/site-lib/findlib/Makefile.config
else
  # Cross: configure takes the stdlib from ocamlc -where, the cross stdlib under
  # BUILD_PREFIX; topfind is installed there and findlib.conf's path names it
  if [[ "${build_platform}" != "${target_platform}" ]]; then
    OCAML_STDLIB="$(ocamlc -where)"
    mv "${OCAML_STDLIB}/topfind" "${PREFIX}/lib/ocaml/"
    sed -i "s@${OCAML_STDLIB}@${PREFIX}/lib/ocaml@g" "${PREFIX}"/etc/findlib.conf "${PREFIX}"/lib/ocaml/site-lib/findlib/Makefile.config
  fi
  sed -i "s@${BUILD_PREFIX}@${PREFIX}@g" "${PREFIX}"/etc/findlib.conf "${PREFIX}"/lib/ocaml/site-lib/findlib/Makefile.config
fi

for CHANGE in "activate" "deactivate"
do
  mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
  if [[ "${target_platform}" == win-* ]]; then
    cp "${RECIPE_DIR}/scripts/${CHANGE}.bat" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.bat"
  else
    cp "${RECIPE_DIR}/scripts/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
  fi
done
