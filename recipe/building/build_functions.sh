# ==============================================================================
# OCaml-findlib Build Helper Functions
# ==============================================================================
# This file contains all reusable helper functions for the build process.
# Sourced by build.sh for cleaner organization.
# ==============================================================================

# ==============================================================================
# HELPER FUNCTIONS - Error Handling & Utilities
# ==============================================================================

warn() {
  echo "WARNING: $*" >&2
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

try_or_warn() {
  local msg="${1}"
  shift
  "$@" 2>/dev/null || warn "${msg}"
}

try_or_fail() {
  local msg="${1}"
  shift
  "$@" || fail "${msg}"
}

create_wrapper_script() {
  local wrapper_path="${1}"
  local target_binary="${2}"
  local extra_args="${3:-}"

  cat > "${wrapper_path}" << WRAPPER_EOF
#!/bin/bash
exec "${target_binary}" ${extra_args} "\$@"
WRAPPER_EOF
  chmod +x "${wrapper_path}"
  echo "  Created wrapper: ${wrapper_path} -> ${target_binary}"
}

# ==============================================================================
# PLATFORM DETECTION
# ==============================================================================

is_cross_compile() { [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; }
is_macos() { [[ "${target_platform}" == "osx-"* ]]; }
is_linux() { [[ "${target_platform}" == "linux-"* ]]; }
is_linux_cross() { [[ "${target_platform}" == *"-aarch64" ]] || [[ "${target_platform}" == *"-ppc64le" ]] || [[ "${target_platform}" == *"-riscv64" ]]; }
is_non_unix() { [[ "${target_platform}" != "linux-"* ]] && [[ "${target_platform}" != "osx-"* ]]; }
build_is_macos() { [[ "${build_platform:-${target_platform}}" == "osx-"* ]]; }

# Convenience wrappers for readability
get_target_c_compiler() { get_compiler "c" "${CONDA_TOOLCHAIN_HOST:-}"; }
get_target_cxx_compiler() { get_compiler "cxx" "${CONDA_TOOLCHAIN_HOST:-}"; }
get_build_c_compiler() { get_compiler "c" "${CONDA_TOOLCHAIN_BUILD:-}"; }
get_build_cxx_compiler() { get_compiler "cxx" "${CONDA_TOOLCHAIN_BUILD:-}"; }

# Get compiler path based on type and toolchain
# Usage: get_compiler "c" [toolchain_prefix]  -> returns gcc/clang path
#        get_compiler "cxx" [toolchain_prefix] -> returns g++/clang++ path
get_compiler() {
  local compiler_type="${1}"  # "c" or "cxx"
  local toolchain_prefix="${2:-}"

  local c_compiler cxx_compiler
  if [[ -n "${toolchain_prefix}" ]]; then
    if [[ "${toolchain_prefix}" == *"apple-darwin"* ]]; then
      c_compiler="${toolchain_prefix}-clang"
      cxx_compiler="${toolchain_prefix}-clang++"
    else
      c_compiler="${toolchain_prefix}-gcc"
      cxx_compiler="${toolchain_prefix}-g++"
    fi
  else
    if is_macos; then
      c_compiler="clang"
      cxx_compiler="clang++"
    else
      c_compiler="gcc"
      cxx_compiler="g++"
    fi
  fi

  if [[ "${compiler_type}" == "c" ]]; then
    echo "${c_compiler}"
  else
    echo "${cxx_compiler}"
  fi
}

# ==============================================================================
# CROSS-COMPILATION SETUP FUNCTIONS
# ==============================================================================

swap_ocaml_compilers() {
  echo "  Swapping OCaml compilers to cross-compilers..."
  pushd "${BUILD_PREFIX}/bin" > /dev/null
    for tool in ocamlc ocamldep ocamlopt ocamlobjinfo ocamlmklib; do
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
  echo "  Setting up C/C++ cross-compiler symlinks..."
  local target_cc="$(get_target_c_compiler)"
  local target_cxx="$(get_target_cxx_compiler)"

  pushd "${BUILD_PREFIX}/bin" > /dev/null
    for tool in gcc cc; do
      if [[ -f "${tool}" ]] || [[ -L "${tool}" ]]; then
        mv "${tool}" "${tool}.build" 2>/dev/null || true
      fi
      ln -sf "${target_cc}" "${tool}"
      echo "    Linked ${tool} -> ${target_cc}"
    done
    for tool in g++ c++; do
      if [[ -f "${tool}" ]] || [[ -L "${tool}" ]]; then
        mv "${tool}" "${tool}.build" 2>/dev/null || true
      fi
      ln -sf "${target_cxx}" "${tool}"
      echo "    Linked ${tool} -> ${target_cxx}"
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
  echo "      CC=${CC}, CXX=${CXX:-}, AR=${AR}"
  echo "      CONDA_OCAML_CC=${CONDA_OCAML_CC}"

  # Set QEMU_LD_PREFIX for binfmt_misc/QEMU to find aarch64 dynamic linker
  export QEMU_LD_PREFIX="${BUILD_PREFIX}/${CONDA_TOOLCHAIN_HOST}/sysroot"

  # Set OCAMLLIB, LIBRARY_PATH and LDFLAGS so ocamlmklib can find cross-compiled OCaml runtime
  # OCAMLLIB is CRITICAL - ocamlmklib uses it to find libasmrun.a and other runtime libs
  local cross_ocaml_lib="${BUILD_PREFIX}/lib/ocaml-cross-compilers/${CONDA_TOOLCHAIN_HOST}/lib/ocaml"
  if [[ -d "${cross_ocaml_lib}" ]]; then
    export OCAMLLIB="${cross_ocaml_lib}"
    export LIBRARY_PATH="${cross_ocaml_lib}:${PREFIX}/lib:${LIBRARY_PATH:-}"
    export LDFLAGS="-L${cross_ocaml_lib} -L${PREFIX}/lib ${LDFLAGS:-}"
    echo "    Set OCAMLLIB for ocamlmklib: ${OCAMLLIB}"
    echo "    Set LIBRARY_PATH: ${cross_ocaml_lib}"
    echo "    Set LDFLAGS: ${LDFLAGS}"

    # OCAMLPATH strategy for cross-compilation:
    # - Cross path FIRST: so compiler finds cross-compiled libraries for linking
    # - Native path SECOND: so dune's runtime can load native stub libraries (dllunixbyt.so)
    # This ordering ensures compilation uses cross libs while dune can still run
    local native_ocaml_lib="${BUILD_PREFIX}/lib/ocaml"
    export OCAMLPATH="${cross_ocaml_lib}:${native_ocaml_lib}"
    echo "    Set OCAMLPATH (cross-first, native-fallback): ${OCAMLPATH}"

    # CAML_LD_LIBRARY_PATH: OCaml's stub library search path (takes precedence over OCAMLPATH)
    # OCaml bytecode runtime (used by dune) dynamically loads .so stub files.
    # Dune is native x86_64, so it needs native .so files, not cross-compiled aarch64 ones.
    # CAML_LD_LIBRARY_PATH is checked BEFORE OCAMLPATH-derived stublibs directories.
    local native_stublibs="${native_ocaml_lib}/stublibs"
    export CAML_LD_LIBRARY_PATH="${native_stublibs}"
    echo "    Set CAML_LD_LIBRARY_PATH (native stublibs): ${CAML_LD_LIBRARY_PATH}"

    # Also set LD_LIBRARY_PATH as fallback (for dlopen() after OCaml finds the library)
    export LD_LIBRARY_PATH="${native_stublibs}:${LD_LIBRARY_PATH:-}"
    echo "    Set LD_LIBRARY_PATH (native stublibs): ${native_stublibs}"

    # Debug: show what's in the cross-compiler lib
    echo "    Cross-compiled OCaml runtime files:"
    ls -la "${cross_ocaml_lib}/"*.a 2>/dev/null | head -5 || echo "      (no .a files found)"
    echo "    Cross-compiled OCaml packages:"
    ls -d "${cross_ocaml_lib}"/*/ 2>/dev/null | head -10 || echo "      (no subdirectories found)"
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

# NOTE: create_macos_ocamlmklib_wrapper is no longer needed.
# ocaml >=5.3.0 build_12+ includes patch 0002-ocamlmklib-conda-env-vars.patch
# which makes ocamlmklib read CONDA_OCAML_AR and CONDA_OCAML_MKDLL env vars.
# The ${target}-ocamlmklib wrapper sets these vars and handles macOS -undefined.

clear_build_caches() {
  echo "  Clearing build caches for cross-compilation..."

  # Clear any _build directories from previous builds
  rm -rf "${SRC_DIR}/_build" 2>/dev/null || true

  # Remove any object files from previous builds
  find "${SRC_DIR}" -name "*.o" -delete 2>/dev/null || true
  echo "  Build caches cleared"
}
