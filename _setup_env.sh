# Copyright (C) 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This is an implementation detail of build.sh and friends. Do not source
# directly as it will spoil your shell and make build.sh unusable. You have
# been warned! If you have a good reason to source the result of this file into
# a shell, please let kernel-team@android.com know and we are happy to help
# with your use case.

[ -n "$_SETUP_ENV_SH_INCLUDED" ] && return || export _SETUP_ENV_SH_INCLUDED=1

# TODO: Use a $(gettop) style method.
export ROOT_DIR=$(readlink -f $PWD)

case "${LOG}" in
  "") ;;
  "1")  echo "Saving log to ${ROOT_DIR}/build.log"
        exec &> >(tee build.log)
        echo " $(date)" ;;
  *)  echo "Saving log to ${ROOT_DIR}/${LOG}"
      exec &> >(tee ${LOG})
      echo " $(date)"
esac

export BUILD_CONFIG=${BUILD_CONFIG:-build.config}

# Helper function to let build.config files add command to PRE_DEFCONFIG_CMDS, EXTRA_CMDS, etc.
# Usage: append_cmd PRE_DEFCONFIG_CMDS 'the_cmd'
function append_cmd() {
  if [ ! -z "${!1}" ]; then
    eval "$1=\"${!1} && \$2\""
  else
    eval "$1=\"\$2\""
  fi
}
export -f append_cmd

export KERNEL_DIR
# for case that KERNEL_DIR is not specified in environment
if [ -z "${KERNEL_DIR}" ]; then
    # for the case that KERNEL_DIR is not specified in the BUILD_CONFIG file
    # use the directory of the build config file as KERNEL_DIR
    # for the case that KERNEL_DIR is specified in the BUILD_CONFIG file,
    # or via the config files sourced, the value of KERNEL_DIR
    # set here would be overwritten, and the specified value would be used.
    #build_config_path=$(readlink -f ${ROOT_DIR}/${BUILD_CONFIG})
    #real_root_dir=${build_config_path%%${BUILD_CONFIG}}
    build_config_path=$(realpath ${ROOT_DIR}/${BUILD_CONFIG})
    build_config_dir=$(dirname ${build_config_path})
    build_config_dir=${build_config_dir##${ROOT_DIR}/}
    #build_config_dir=${build_config_dir##${real_root_dir}}
    KERNEL_DIR="${build_config_dir}"
    echo " Set default KERNEL_DIR: ${KERNEL_DIR}"
    if [ ${KERNEL_DIR} = ${ROOT_DIR} ]; then
      KERNEL_DIR=.
    fi
else 
    echo " User environment KERNEL_DIR: ${KERNEL_DIR}"
fi
echo " The final value for KERNEL_DIR: ${KERNEL_DIR}"

echo "========================================================"
echo " Build config: ${ROOT_DIR}/${BUILD_CONFIG}"
echo
cat ${ROOT_DIR}/${BUILD_CONFIG}


set -a
. ${ROOT_DIR}/${BUILD_CONFIG}
for fragment in ${BUILD_CONFIG_FRAGMENTS}; do
  . ${ROOT_DIR}/${fragment}
done
set +a

# Get a list of build configs sourced by this file"
set +e
FRGMNTS=""
FRGMNTS="$(grep -E '^\.\ ' ${ROOT_DIR}/${BUILD_CONFIG})"
FRGMNTS+="$(grep -E '^source\ ' ${ROOT_DIR}/${BUILD_CONFIG})"
if [ ! -z "$FRGMNTS" ]; then
  FRGMNTS=${FRGMNTS//. /}
  for frag in ${FRGMNTS[@]}; do
    #if [[ $frag = *'${ROOT_DIR}'* ]]; then
    #  frag=$(echo $frag | sed 's|${ROOT_DIR}/||g')
    #fi
    frag=$(eval echo $frag)
    echo "========================================================"
    echo " Sparse build config: $frag"
    echo
    cat $frag
  done
fi
set -e

# For incremental kernel development, it is beneficial to trade certain
# optimizations for faster builds.
if [[ -n "${FAST_BUILD}" ]]; then
  # Decrease lz4 compression level to significantly speed up ramdisk compression.
  : ${LZ4_RAMDISK_COMPRESS_ARGS:="--fast"}
  # Use ThinLTO for fast incremental compiles
  : ${LTO:="thin"}
  # skip installing kernel headers
  : ${SKIP_CP_KERNEL_HDR:="1"}
fi

export COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out${OUT_DIR_SUFFIX}/${BRANCH}})
export OUT_DIR=$(readlink -m ${COMMON_OUT_DIR}/${KERNEL_DIR})
export DIST_DIR=$(readlink -m ${DIST_DIR:-${COMMON_OUT_DIR}/dist})
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export UNSTRIPPED_MODULES_ARCHIVE=unstripped_modules.tar.gz
export MODULES_ARCHIVE=modules.tar.gz

export TZ=UTC
export LC_ALL=C
if [ -z "${SOURCE_DATE_EPOCH}" ]; then
  export SOURCE_DATE_EPOCH=$(git -C ${ROOT_DIR}/${KERNEL_DIR} log -1 --pretty=%ct)
fi
if [ -z "${KBUILD_BUILD_TIMESTAMP}" ]; then
  export KBUILD_BUILD_TIMESTAMP="$(date -d @${SOURCE_DATE_EPOCH})"
fi
# List of prebuilt directories shell variables to incorporate into PATH
prebuilts_paths=(
LINUX_GCC_CROSS_COMPILE_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_ARM32_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_COMPAT_PREBUILTS_BIN
CLANG_PREBUILT_BIN
LZ4_PREBUILTS_BIN
DTC_PREBUILTS_BIN
LIBUFDT_PREBUILTS_BIN
BUILDTOOLS_PREBUILT_BIN
)

# Have host compiler use LLD and compiler-rt.
LLD_COMPILER_RT="-fuse-ld=lld --rtlib=compiler-rt"
if [[ -n "${NDK_TRIPLE}" ]]; then
  NDK_DIR=${ROOT_DIR}/prebuilts/ndk-r23
  if [[ ! -d "${NDK_DIR}" ]]; then
    # Kleaf/Bazel will checkout the ndk to a different directory than
    # build.sh.
    NDK_DIR=${ROOT_DIR}/external/prebuilt_ndk
    if [[ ! -d "${NDK_DIR}" ]]; then
      echo "ERROR: NDK_TRIPLE set, but unable to find prebuilts/ndk." 1>&2
      echo "Did you forget to checkout prebuilts/ndk?" 1>&2
      exit 1
    fi
  fi
  USERCFLAGS="--target=${NDK_TRIPLE} "
  USERCFLAGS+="--sysroot=${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64/sysroot "
  # Some kernel headers trigger -Wunused-function for unused static functions
  # with clang; GCC does not warn about unused static inline functions. The
  # kernel sets __attribute__((maybe_unused)) on such functions when W=1 is
  # not set.
  USERCFLAGS+="-Wno-unused-function "
  # To help debug these flags, consider commenting back in the following, and
  # add `echo $@ > /tmp/log.txt` and `2>>/tmp/log.txt` to the invocation of $@
  # in scripts/cc-can-link.sh.
  #USERCFLAGS+=" -Wl,--verbose -v"
  # We need to set -fuse-ld=lld for Android's build env since AOSP LLVM's
  # clang is not configured to use LLD by default, and BFD has been
  # intentionally removed. This way CC_CAN_LINK can properly link the test in
  # scripts/cc-can-link.sh.
  USERLDFLAGS="${LLD_COMPILER_RT} "
  USERLDFLAGS+="--target=${NDK_TRIPLE} "
else
  USERCFLAGS="--sysroot=/dev/null"
fi
export USERCFLAGS USERLDFLAGS

if [ "${HERMETIC_TOOLCHAIN:-0}" -eq 1 ]; then
  HOST_TOOLS=${OUT_DIR}/host_tools
  rm -rf ${HOST_TOOLS}
  mkdir -p ${HOST_TOOLS}
  for tool in \
      bash \
      git \
      install \
      perl \
      rsync \
      sh \
      tar \
      ${ADDITIONAL_HOST_TOOLS}
  do
      ln -sf $(which $tool) ${HOST_TOOLS}
  done
  PATH=${HOST_TOOLS}

  # use relative paths for file name references in the binaries
  # (e.g. debug info)
  export KCPPFLAGS="-ffile-prefix-map=${ROOT_DIR}/${KERNEL_DIR}/= -ffile-prefix-map=${ROOT_DIR}/="

  # set the common sysroot
  sysroot_flags+="--sysroot=${ROOT_DIR}/build/kernel/build-tools/sysroot "

  # add openssl (via boringssl) and other prebuilts into the lookup path
  cflags+="-I${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/include "

  # add openssl and further prebuilt libraries into the lookup path
  ldflags+="-Wl,-rpath,${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/lib64 "
  ldflags+="-L ${ROOT_DIR}/prebuilts/kernel-build-tools/linux-x86/lib64 "
  ldflags+=${LLD_COMPILER_RT}

  export HOSTCFLAGS="$sysroot_flags $cflags"
  export HOSTLDFLAGS="$sysroot_flags $ldflags"
fi

for prebuilt_bin in "${prebuilts_paths[@]}"; do
    prebuilt_bin=\${${prebuilt_bin}}
    eval prebuilt_bin="${prebuilt_bin}"
    if [ -n "${prebuilt_bin}" ]; then
        # Mitigate dup paths
        PATH=${PATH//"${ROOT_DIR}\/${prebuilt_bin}:"}
        PATH=${ROOT_DIR}/${prebuilt_bin}:${PATH}
    fi
done
export PATH
echo "========================================================"
echo "PATH="
IFS=':' read -ra echopaths <<< "$PATH"
for lst in "${echopaths[@]}"; do
    echo "  $lst"
done


unset LD_LIBRARY_PATH
unset PYTHONPATH
unset PYTHONHOME
unset PYTHONSTARTUP

export HOSTCC HOSTCXX CC LD AR NM OBJCOPY OBJDUMP OBJSIZE READELF STRIP AS

tool_args=()

# LLVM=1 implies what is otherwise set below; it is a more concise way of
# specifying CC=clang LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy <etc>, for
# newer kernel versions.
if [[ -n "${LLVM}" ]]; then
  case ${LLVM} in
    -*) LLVM_SUFFIX=${LLVM} ;;
    */) LLVM_PREFIX=${LLVM}
  esac
  tool_args+=("LLVM=1")
  # Make $(LLVM) more flexible. Set a version suffix by leaving a dash
  # at beginning or set path to toolchain by leaving trailing slash.
  if [[ -n ${LLVM_SUFFIX} || -n ${LLVM_PREFIX} ]]; then
    set -a
    HOSTCC="${LLVM_PREFIX}clang${LLVM_SUFFIX}"
    HOSTCXX="${LLVM_PREFIX}clang++${LLVM_SUFFIX}"
    HOSTLD="${LLVM_PREFIX}ld.lld${LLVM_SUFFIX}"
    HOSTAR="${LLVM_PREFIX}llvm-ar${LLVM_SUFFIX}"
    CC="${LLVM_PREFIX}clang${LLVM_SUFFIX}"
    LD="${LLVM_PREFIX}ld.lld${LLVM_SUFFIX}"
    AR="${LLVM_PREFIX}llvm-ar${LLVM_SUFFIX}"
    NM="${LLVM_PREFIX}llvm-nm${LLVM_SUFFIX}"
    OBJCOPY="${LLVM_PREFIX}llvm-objcopy${LLVM_SUFFIX}"
    OBJDUMP="${LLVM_PREFIX}llvm-objdump${LLVM_SUFFIX}"
    OBJSIZE="${LLVM_PREFIX}llvm-size${LLVM_SUFFIX}"
    READELF="${LLVM_PREFIX}llvm-readelf${LLVM_SUFFIX}"
    STRIP="${LLVM_PREFIX}llvm-strip${LLVM_SUFFIX}"
    set +a
  fi

  # Reset a bunch of variables that the kernel's top level Makefile does, just
  # in case someone tries to use these binaries in this script such as in
  # initramfs generation below.
  HOSTCC=clang
  HOSTCXX=clang++
  CC=clang
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  OBJSIZE=llvm-size
  READELF=llvm-readelf
  STRIP=llvm-strip
else
  if [ -n "${HOSTCC}" ]; then
    tool_args+=("HOSTCC=${HOSTCC}")
  fi

  if [ -n "${CC}" ]; then
    tool_args+=("CC=${CC}")
    if [ -z "${HOSTCC}" ]; then
      tool_args+=("HOSTCC=${CC}")
    fi
  fi

  if [ -n "${LD}" ]; then
    tool_args+=("LD=${LD}" "HOSTLD=${LD}")
  fi

  if [ -n "${NM}" ]; then
    tool_args+=("NM=${NM}")
  fi

  if [ -n "${OBJCOPY}" ]; then
    tool_args+=("OBJCOPY=${OBJCOPY}")
  fi

  if [ -n "${AS}" ]; then
    if [ "${AS}" = "llvm-as" ]; then
      echo "warn: AS=llvm-as is not recommended, changing to clang"
      tool_args+=("LLVM_IAS=1")
    else
      tool_args+=("AS=${AS}")
    fi
  fi
fi

if [ -n "${LLVM_IAS}" ]; then
  tool_args+=("LLVM_IAS=${LLVM_IAS}")
  # Reset $AS for the same reason that we reset $CC etc above.
  AS=clang
fi

if [ -n "${DEPMOD}" ]; then
  tool_args+=("DEPMOD=${DEPMOD}")
fi

if [ -n "${DTC}" ]; then
  tool_args+=("DTC=${DTC}")
fi

export TOOL_ARGS="${tool_args[@]}"

export DECOMPRESS_GZIP DECOMPRESS_LZ4 RAMDISK_COMPRESS RAMDISK_DECOMPRESS RAMDISK_EXT

DECOMPRESS_GZIP="gzip -c -d"
DECOMPRESS_LZ4="lz4 -c -d -l"
if [ -z "${LZ4_RAMDISK}" ] ; then
  RAMDISK_COMPRESS="gzip -c -f"
  RAMDISK_DECOMPRESS="${DECOMPRESS_GZIP}"
  RAMDISK_EXT="gz"
else
  RAMDISK_COMPRESS="lz4 -c -l ${LZ4_RAMDISK_COMPRESS_ARGS:--12 --favor-decSpeed}"
  RAMDISK_DECOMPRESS="${DECOMPRESS_LZ4}"
  RAMDISK_EXT="lz4"
fi