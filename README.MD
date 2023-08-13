# What's this?
AOSP created `build.sh`, a canonical way to compile their kernels but [deprecated them since Android 13](https://android.googlesource.com/kernel/build/+/670b2ff547c0739352a200422e4e8a7149145947), replacing it with [kleaf](https://android.googlesource.com/kernel/build/+/refs/heads/main/kleaf/README.md)  

This project aims to maintain `build.sh` and its friends

# [About the bulid.config file](build_config.md)
In most cases, you will have to specify BUILD_CONFIG=path/to/build.config as a prefix before any of these script

# Scripts details
## build.sh
Usage:  
    build/build.sh <make options>*  
or:  
    To define custom out and dist directories:  
      `OUT_DIR=<out dir> DIST_DIR=<dist dir> build/build.sh <make options>*`  
    To use a custom build config:  
      `BUILD_CONFIG=<path to the build.config> <make options>*`

Examples:  
    To define custom out and dist directories:  

```shellscript
OUT_DIR=output DIST_DIR=dist build/build.sh -j24 V=1
```  

   To use a custom build config:  

```shellscript
BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh -j24 V=1
```

## config.sh
Runs a configuration editor inside kernel/build environment.   
Usage:  
    `build/config.sh <config editor> <make options>*`

Example:  

```shellscript
build/config.sh menuconfig|config|nconfig|... (default to menuconfig)
```