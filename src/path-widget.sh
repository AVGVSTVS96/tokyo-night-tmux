#!/usr/bin/env bash

# check if enabled
ENABLED=$(tmux show-option -gqv @tokyo-night-tmux_show_path 2>/dev/null || true)
[[ ${ENABLED} != "1" ]] && exit 0

# Imports
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
. "${ROOT_DIR}/lib/coreutils-compat.sh"

PATH_FORMAT=$(tmux show-option -gv @tokyo-night-tmux_path_format 2>/dev/null) # full | relative
RESET="#[fg=brightwhite,bg=#15161e,nobold,noitalics,nounderscore,nodim]"

current_path="${1}"
default_path_format="relative"
PATH_FORMAT="${PATH_FORMAT:-$default_path_format}"

# check user requested format
if [[ ${PATH_FORMAT} == "relative" ]]; then
  current_path="$(echo "${current_path}" | sed 's#'"$HOME"'#~#g')"
fi

# Render all parent directories muted, with the rightmost directory highlighted.
if [[ "${current_path}" == "/" ]]; then
  parent_path=""
  current_dir="/"
else
  current_path="${current_path%/}"
  parent_path="${current_path%/*}"
  current_dir="${current_path##*/}"

  if [[ "${parent_path}" == "${current_path}" ]]; then
    parent_path=""
  else
    parent_path="${parent_path}/"
  fi
fi

printf '#[fg=blue,bg=default]░   #[fg=#565f89,bg=default]%s#[fg=#a9b1d6,bg=default]%s ' "${parent_path}" "${current_dir}"
