#!/usr/bin/env bash

# Check TMUX_PLUGIN_MANAGER_PATH first if set
if [ -n "$TMUX_PLUGIN_MANAGER_PATH" ]; then
    continuum_path="$TMUX_PLUGIN_MANAGER_PATH/tmux-continuum/scripts/continuum_save.sh"
    if [ -f "$continuum_path" ]; then
        echo "#($continuum_path)"
        exit 0
    fi
fi

# Check tmux plugin locations when TPM isn't used to manage plugins
plugin_dirs=(
    "$HOME/.tmux/plugins"
    "$HOME/.config/tmux/plugins"
)

for plugin_dir in "${plugin_dirs[@]}"; do
    continuum_path="${plugin_dir}/tmux-continuum/scripts/continuum_save.sh"
    if [ -f "$continuum_path" ]; then
        echo "#($continuum_path)"
        exit 0
    fi
done

# If continuum not found, output nothing
exit 0
