#!/bin/bash
[[ -z "$PS1" ]] || {
  echo "ERROR: Automatic search cannot run in non-interctive shell."
  echo "Please set BUILD_CONFIG variable manually."
  exit 1
}
set +e
declare -ag found
declare -g selected_opt

choose() {
  local array=("$@")
  local array_length=${#array[@]}
  if [ "$array_length" -eq 0 ]; then
    echo "Couldn't find. Please set BUILD_CONFIG variable manually."
    exit 1
  fi
  echo "Found $array_length configs in $(pwd)"
  for i in "${!array[@]}"; do
    echo "$((i+1))) ${array[$i]}"
  done
  echo

  while true; do
    read -p "Select config (1-$array_length): " selected_index
    if [[ "$selected_index" =~ ^[1-9][0-9]*$ && "$selected_index" -le "$array_length" ]]; then
      selected_opt="${array[$(($selected_index-1))]}"
      echo "Selecting ${selected_opt}"
      break
    else
      echo "Invalid selection."
      echo
      fi
  done   
}

yn() {
    local prompt="$1 (Y/n): "
    local response
    while true; do
        read -p "$prompt" response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) return 1
        esac
    done
}


parent_dir_files=($(find .. -mindepth 1 -maxdepth 2 -name "build.config*" -type f))
found+=("${parent_dir_files[@]}")
all_folders_files=($(find . -maxdepth 2 -name "build.config*" -type f))
found+=("${all_folders_files[@]}")

if [[ -e ./build.config ]]; then
  echo "Found saved build.config in working directory"
  export BUILD_CONFIG=./build.config
else
  choose "${found[@]}"
  export BUILD_CONFIG="${selected_opt}"
  if yn "Create symlink 'build.config' in current directory for subsequent builds?"; then
    echo "Done."
    if [[ -e build_utils.sh ]]; then
      cd ..
      ln -sf $(echo ${selected_opt} | sed 's/^\.\.\///g') build.config
      cd $(dirname $0)
    else
      ln -sf ${selected_opt} ./build.config
    fi
  fi
  echo
fi

set -e