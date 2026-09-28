#!/bin/zsh

set -eu

script_directory="${0:A:h}"
repository_directory="${script_directory:h}"
capstone_directory="${repository_directory:h}"
runs_directory="$capstone_directory/runs"
link_path="$runs_directory/simulator-current"
simulator_id="${1:-booted}"
bundle_id="${2:-com.dev.inkpad}"

container_path="$(xcrun simctl get_app_container "$simulator_id" "$bundle_id" data)"
debug_path="$container_path/Documents/InkPadDebug"

mkdir -p "$debug_path" "$runs_directory"

if [[ -e "$link_path" && ! -L "$link_path" ]]; then
    print -u2 "Refusing to replace non-symlink path: $link_path"
    exit 1
fi

ln -sfn "$debug_path" "$link_path"
print "$link_path -> $debug_path"
