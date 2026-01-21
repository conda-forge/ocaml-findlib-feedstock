# ==============================================================================
# This file contains all reusable helper functions for the opam build process.
# Sourced by build.sh for cleaner organization.
# ==============================================================================

is_cross_compile() { [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; }
is_macos() { [[ "${target_platform}" == "osx-"* ]]; }
is_linux() { [[ "${target_platform}" == "linux-"* ]]; }
is_non_unix() { [[ "${target_platform}" != "linux-"* ]] && [[ "${target_platform}" != "osx-"* ]]; }

# Convenience wrappers for readability
get_target_c_compiler() { get_compiler "${CONDA_TOOLCHAIN_HOST:-}"; }
get_build_c_compiler() { get_compiler "${CONDA_TOOLCHAIN_BUILD:-}"; }

# Get compiler path based on type and toolchain
# Usage: get_compiler "c" [toolchain_prefix]  -> returns gcc/clang path
#        get_compiler "cxx" [toolchain_prefix] -> returns g++/clang++ path
get_compiler() {
  local toolchain_prefix="${1:-}"

  local c_compiler
  if [[ -n "${toolchain_prefix}" ]]; then
    if [[ "${toolchain_prefix}" == *"apple-darwin"* ]]; then
      c_compiler="${toolchain_prefix}-clang"
    else
      c_compiler="${toolchain_prefix}-gcc"
    fi
  else
    if is_macos; then
      c_compiler="clang"
    else
      c_compiler="gcc"
    fi
  fi

  echo "${c_compiler}"
}

# ==============================================================================
# CROSS-COMPILATION SETUP FUNCTIONS
# ==============================================================================

swap_ocaml_compilers() {
  echo "  Swapping OCaml compilers to cross-compilers..."
  pushd "${BUILD_PREFIX}/bin" > /dev/null
    for tool in ocamlc ocamldep ocamlopt ocamlobjinfo; do
      if [[ -f "${tool}" ]] || [[ -L "${tool}" ]]; then
        mv "${tool}" "${tool}.build"
        ln -sf "${CONDA_TOOLCHAIN_HOST}-${tool}" "${tool}"
      fi
      if [[ -f "${tool}.opt" ]] || [[ -L "${tool}.opt" ]]; then
        mv "${tool}.opt" "${tool}.opt.build"
        ln -sf "${CONDA_TOOLCHAIN_HOST}-${tool}.opt" "${tool}.opt"
      fi
    done
  popd > /dev/null
}

setup_cross_c_compilers() {
  echo "  Setting up C cross-compiler symlinks..."
  local target_cc="$(get_target_c_compiler)"

  pushd "${BUILD_PREFIX}/bin" > /dev/null
    for tool in gcc cc; do
      if [[ -f "${tool}" ]] || [[ -L "${tool}" ]]; then
        mv "${tool}" "${tool}.build" 2>/dev/null || true
      fi
      ln -sf "${target_cc}" "${tool}"
      echo "    Linked ${tool} -> ${target_cc}"
    done
  popd > /dev/null
}

configure_cross_environment() {
  echo "  Configuring cross-compilation environment variables..."

  # For conda-ocaml-cc wrapper (Dune reads c_compiler from ocamlc -config)
  export CONDA_OCAML_CC="$(get_target_c_compiler)"
  if is_macos; then
    export CONDA_OCAML_MKEXE="${CONDA_OCAML_CC}"
    export CONDA_OCAML_MKDLL="${CONDA_OCAML_CC} -dynamiclib"
  else
    export CONDA_OCAML_MKEXE="${CONDA_OCAML_CC} -Wl,-E -ldl"
    export CONDA_OCAML_MKDLL="${CONDA_OCAML_CC} -shared"
  fi
  export CONDA_OCAML_AR="${CONDA_TOOLCHAIN_HOST}-ar"
  export CONDA_OCAML_AS="${CONDA_TOOLCHAIN_HOST}-as"
  export CONDA_OCAML_LD="${CONDA_TOOLCHAIN_HOST}-ld"

  echo "    Cross-compiler environment:"
  echo "      CC=${CC}, AR=${AR}, CONDA_OCAML_CC=${CONDA_OCAML_CC}"

  # Set QEMU_LD_PREFIX for binfmt_misc/QEMU to find aarch64 dynamic linker
  export QEMU_LD_PREFIX="${BUILD_PREFIX}/${CONDA_TOOLCHAIN_HOST}/sysroot"

  # Get the cross-compiled OCaml stdlib path from the swapped ocamlc
  local cross_ocaml_lib
  cross_ocaml_lib="$(ocamlc -where)"
  echo "    ocamlc -where reports: ${cross_ocaml_lib}"

  # CRITICAL DEBUG: Verify the architecture of runtime libraries using readelf
  echo "    Verifying libcamlrun.a architecture (cross-compiled, for ocamlc -custom):"
  if [[ -f "${cross_ocaml_lib}/libcamlrun.a" ]]; then
    # Extract first object and check its ELF header
    local tmpdir
    tmpdir="$(mktemp -d)"
    pushd "${tmpdir}" > /dev/null
    ar x "${cross_ocaml_lib}/libcamlrun.a" 2>/dev/null
    local first_obj
    first_obj="$(ls *.o 2>/dev/null | head -1)"
    if [[ -n "${first_obj}" ]]; then
      echo "    First object file: ${first_obj}"
      readelf -h "${first_obj}" 2>&1 | grep -E "Class:|Machine:" || true
    fi
    popd > /dev/null
    rm -rf "${tmpdir}"
  else
    echo "    WARNING: libcamlrun.a not found at ${cross_ocaml_lib}"
  fi

  # Also check libasmrun.a (native-code runtime, for ocamlopt)
  echo "    Verifying libasmrun.a architecture (cross-compiled, for ocamlopt):"
  if [[ -f "${cross_ocaml_lib}/libasmrun.a" ]]; then
    local tmpdir
    tmpdir="$(mktemp -d)"
    pushd "${tmpdir}" > /dev/null
    ar x "${cross_ocaml_lib}/libasmrun.a" 2>/dev/null
    local first_obj
    first_obj="$(ls *.o 2>/dev/null | head -1)"
    if [[ -n "${first_obj}" ]]; then
      echo "    First object file: ${first_obj}"
      readelf -h "${first_obj}" 2>&1 | grep -E "Class:|Machine:" || true
    fi
    popd > /dev/null
    rm -rf "${tmpdir}"
  else
    echo "    WARNING: libasmrun.a not found at ${cross_ocaml_lib}"
  fi

  # Show native stdlib for comparison
  echo "    Native (build) stdlib path: ${BUILD_PREFIX}/lib/ocaml"
  echo "    Verifying libcamlrun.a architecture (native):"
  if [[ -f "${BUILD_PREFIX}/lib/ocaml/libcamlrun.a" ]]; then
    local tmpdir
    tmpdir="$(mktemp -d)"
    pushd "${tmpdir}" > /dev/null
    ar x "${BUILD_PREFIX}/lib/ocaml/libcamlrun.a" 2>/dev/null
    local first_obj
    first_obj="$(ls *.o 2>/dev/null | head -1)"
    if [[ -n "${first_obj}" ]]; then
      echo "    First object file: ${first_obj}"
      readelf -h "${first_obj}" 2>&1 | grep -E "Class:|Machine:" || true
    fi
    popd > /dev/null
    rm -rf "${tmpdir}"
  fi

  # Set OCAMLLIB, LIBRARY_PATH and LDFLAGS so ocamlmklib can find cross-compiled OCaml runtime
  if [[ -d "${cross_ocaml_lib}" ]]; then
    export OCAMLLIB="${cross_ocaml_lib}"
    export LIBRARY_PATH="${cross_ocaml_lib}:${PREFIX}/lib:${LIBRARY_PATH:-}"
    export LDFLAGS="-L${cross_ocaml_lib} -L${PREFIX}/lib ${LDFLAGS:-}"
    echo "    Set OCAMLLIB: ${OCAMLLIB}"
    echo "    Set LIBRARY_PATH: ${cross_ocaml_lib}"
    echo "    Set LDFLAGS: ${LDFLAGS}"
    # Debug: show what's in the cross-compiler lib
    echo "    Cross-compiled OCaml runtime files:"
    ls -la "${cross_ocaml_lib}/"*.a 2>/dev/null | head -5 || echo "      (no .a files found)"
  fi
}

patch_ocaml_makefile_config() {
  echo "  Patching OCaml Makefile.config for target architecture..."
  local ocaml_lib=$(ocamlc -where)
  local ocaml_config="${ocaml_lib}/Makefile.config"

  if [[ -f "${ocaml_config}" ]]; then
    echo "    Patching: ${ocaml_config}"
    cp "${ocaml_config}" "${ocaml_config}.bak"
    local target_cc="$(get_target_c_compiler)"
    sed -i "s|^CC=.*|CC=${target_cc}|" "${ocaml_config}"
    sed -i "s|^NATIVE_C_COMPILER=.*|NATIVE_C_COMPILER=${target_cc}|" "${ocaml_config}"
    sed -i "s|^BYTECODE_C_COMPILER=.*|BYTECODE_C_COMPILER=${target_cc}|" "${ocaml_config}"
    sed -i "s|^PACKLD=.*|PACKLD=${CONDA_TOOLCHAIN_HOST}-ld -r -o \$(EMPTY)|" "${ocaml_config}"
    sed -i "s|^ASM=.*|ASM=${CONDA_TOOLCHAIN_HOST}-as|" "${ocaml_config}"
    sed -i "s|^TOOLPREF=.*|TOOLPREF=${CONDA_TOOLCHAIN_HOST}-|" "${ocaml_config}"
    echo "    Patched config entries:"
    grep -E "^(CC|NATIVE_C_COMPILER|BYTECODE_C_COMPILER|PACKLD|ASM|TOOLPREF)=" "${ocaml_config}"
  else
    echo "    WARNING: OCaml Makefile.config not found at ${ocaml_config}"
  fi
}
