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
    local list=("$@")
    local listlen=${#list[@]}

    if [[ $listlen == 0 ]]; then
        echo "Couldn't find. Please set BUILD_CONFIG variable manually."
        exit 1
    fi

    echo "Found $listlen configs in $(pwd)"

    while true; do
        for i in "${!list[@]}"; do
            echo "$((i+1))) ${list[$i]}"
        done
        echo
        read -p "Select config (1-$listlen): " selected_index

        if [[ "$selected_index" =~ ^[1-9][0-9]*$ && "$selected_index" -le "$listlen" ]]; then
            selected_opt="${list[$(($selected_index-1))]}"
            echo "Selecting ${selected_opt}"
            break
        elif [[ -z "$selected_index" ]]; then
            exit
        else
            echo "Invalid selection"
            echo "hint: Leave blank to cancel"
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
# main
found=($(find . -maxdepth 2 -name "build.config*" -type f))

if [[ -e build.config ]]; then
    echo "Found saved build.config in working directory"
    export BUILD_CONFIG=build.config
else
    choose "${found[@]}"
    export BUILD_CONFIG="${selected_opt}"
    if yn "Create symlink 'build.config' for subsequent builds?"; then
        ln -sf ${selected_opt} build.config
        echo "Done."
    fi
fi

echo

set -e