#!/bin/bash
#TODO: refuse to run if not interactive e.g. GitHub Actions
declare -ag found
declare -g selected_opt

parent_dir_files=($(find .. -maxdepth 1 -name "build.config*" -type f))
found+=("${parent_dir_files[@]}")
all_folders_files=($(find . -maxdepth 2 -name "build.config*" -type f))
found+=("${all_folders_files[@]}")

choose() {
    local array=("$@")
    local array_length=${#array[@]}

    if [ "$array_length" -eq 0 ]; then
        echo "No bulid configs found. Please set BUILD_CONFIG variable manually."
        exit 1
    fi

    for i in "${!array[@]}"; do
        echo "$((i+1))) ${array[$i]}"
    done
    echo

    while true; do
        read -p "Select a config (1-$array_length): " selected_index
        # Validate user input
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
    local prompt="$1 (Y/n) "
    local response
    while true; do
        read -p "$prompt" response
        case $response in
            [Yy]* ) return 0;;  # Return success (yes)
            [Nn]* ) return 1;;  # Return failure (no)
            * ) return 1
        esac
    done
}
[[ -e ./build.config ]] && export BUILD_CONFIG=./build.config ||
"
choose "${found[@]}"
export BUILD_CONFIG="${selected_opt}"
if ! [[ -z "${BUILD_CONFIG}" ]]; then
  if yn "Create symlink 'build.config' for this config?"; then
    echo "Done."
    ln -sf ${selected_opt} ./build.config
  fi
fi
echo
"