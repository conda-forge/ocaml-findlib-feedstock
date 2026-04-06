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

# ==============================================================================
# CROSS-COMPILATION SETUP FUNCTIONS
# ==============================================================================
# With ocaml_<arch> packages, cross-compiler wrappers automatically set
# OCAMLLIB, CONDA_OCAML_CC, etc. We only need to redirect bare compiler
# names so findlib's Makefile finds the cross-compilers.
# ==============================================================================

get_cross_prefix() {
  # 3-tier fallback for cross-compiler prefix:
  # 1. CONDA_TOOLCHAIN_HOST (set on Linux by GCC activation)
  # 2. HOST (conda-build host triplet)
  # 3. Auto-discover from *-ocamlc binaries in BUILD_PREFIX/bin
  if [[ -n "${CONDA_TOOLCHAIN_HOST:-}" ]]; then
    echo "${CONDA_TOOLCHAIN_HOST}"
  elif [[ -n "${HOST:-}" ]]; then
    echo "${HOST}"
  else
    local cross_ocamlc
    cross_ocamlc=$(find "${BUILD_PREFIX}/bin" -name '*-ocamlc' ! -name 'ocamlc' | head -1)
    if [[ -n "${cross_ocamlc}" ]]; then
      basename "${cross_ocamlc}" | sed 's/-ocamlc$//'
    else
      echo "ERROR: Cannot determine cross-compiler prefix" >&2
      return 1
    fi
  fi
}

swap_ocaml_compilers() {
  echo "  Swapping OCaml compilers to cross-compilers..."
  local cross_prefix
  cross_prefix=$(get_cross_prefix)
  echo "  Cross-compiler prefix: ${cross_prefix}"
  pushd "${BUILD_PREFIX}/bin" > /dev/null
    for tool in ocamlc ocamldep ocamlopt ocamlobjinfo ocamlmklib; do
      if [[ -f "${tool}" ]] || [[ -L "${tool}" ]]; then
        mv "${tool}" "${tool}.build"
        ln -sf "${cross_prefix}-${tool}" "${tool}"
      fi
      if [[ -f "${tool}.opt" ]] || [[ -L "${tool}.opt" ]]; then
        mv "${tool}.opt" "${tool}.opt.build"
        ln -sf "${cross_prefix}-${tool}.opt" "${tool}.opt"
      fi
    done
  popd > /dev/null
}
