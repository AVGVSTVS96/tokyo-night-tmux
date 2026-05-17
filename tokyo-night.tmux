#!/usr/bin/env bash
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# title      Tokyo Night                                              +
# version    1.0.0                                                    +
# repository https://github.com/logico-dev/tokyo-night-tmux           +
# author     Lógico                                                   +
# email      hi@logico.com.ar                                         +
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_PATH="$CURRENT_DIR/src"

source "$SCRIPTS_PATH/themes.sh"
# shellcheck source=lib/number-format.sh
source "$CURRENT_DIR/lib/number-format.sh"

tmux_option() {
  tmux show-option -gqv "$1" 2>/dev/null || true
}

# Widget gate: opt-in semantics. Match upstream's current behavior while
# keeping disabled widgets completely off the tmux redraw path: if this
# returns false, no #(...) job is emitted for that widget.
widget_enabled() {
  [[ "$(tmux_option "$1")" == "1" ]]
}

tmux set -g status-left-length 80
tmux set -g status-right-length 150

RESET="#[fg=${THEME[foreground]},bg=${THEME[background]},nobold,noitalics,nounderscore,nodim]"
# Highlight colors
tmux set -g mode-style "fg=${THEME[bgreen]},bg=${THEME[bblack]}"

tmux set -g message-style "bg=${THEME[blue]},fg=${THEME[bblack]}"
tmux set -g message-command-style "fg=${THEME[blue]},bg=${THEME[bblack]}"

tmux set -g pane-border-style "fg=${THEME[bblack]}"
tmux set -g pane-active-border-style "fg=${THEME[blue]}"
tmux set -g pane-border-status off

tmux set -g status-style bg="${THEME[background]}"
tmux set -g popup-border-style "fg=${THEME[blue]}"

TMUX_VARS="$(tmux show -g)"

default_window_id_style="digital"
default_pane_id_style="hsquare"
default_zoom_id_style="dsquare"

default_terminal_icon=""
default_active_terminal_icon=""

window_id_style="$(echo "$TMUX_VARS" | grep '@tokyo-night-tmux_window_id_style' | cut -d" " -f2)"
pane_id_style="$(echo "$TMUX_VARS" | grep '@tokyo-night-tmux_pane_id_style' | cut -d" " -f2)"
zoom_id_style="$(echo "$TMUX_VARS" | grep '@tokyo-night-tmux_zoom_id_style' | cut -d" " -f2)"
terminal_icon="$(echo "$TMUX_VARS" | grep '@tokyo-night-tmux_terminal_icon' | cut -d" " -f2)"
active_terminal_icon="$(echo "$TMUX_VARS" | grep '@tokyo-night-tmux_active_terminal_icon' | cut -d" " -f2)"
window_tidy="$(echo "$TMUX_VARS" | grep '@tokyo-night-tmux_window_tidy_icons' | cut -d" " -f2)"

window_id_style="${window_id_style:-$default_window_id_style}"
pane_id_style="${pane_id_style:-$default_pane_id_style}"
zoom_id_style="${zoom_id_style:-$default_zoom_id_style}"
terminal_icon="${terminal_icon:-$default_terminal_icon}"
active_terminal_icon="${active_terminal_icon:-$default_active_terminal_icon}"
window_space="${window_tidy:-0}"

window_space=$([[ $window_tidy == "0" ]] && echo " " || echo "")

window_number="$(number_format "#{window_index}" "$window_id_style")"
custom_pane="$(number_format "#{pane_index}" "$pane_id_style")"
zoom_number="$(number_format "#{pane_index}" "$zoom_id_style")"

# Resolved once at plugin load via $(...) — the captured string is embedded
# directly into status-left, so tmux never forks a shell for it on redraw.
hostname=""
if widget_enabled "@tokyo-night-tmux_show_hostname"; then
  hostname="$("$SCRIPTS_PATH/hostname-widget.sh")"
fi

#+--- Bars LEFT ---+
# Session name
tmux set -g status-left "#[fg=${THEME[bblack]},bg=${THEME[blue]},bold] #{?client_prefix,󰠠 ,#[dim]󰤂 }#[bold,nodim]#S$hostname "

#+--- Windows ---+
# Focus
tmux set -g window-status-current-format "$RESET#[fg=${THEME[green]},bg=${THEME[bblack]}] #{?#{==:#{pane_current_command},ssh},󰣀 ,$active_terminal_icon $window_space}#[fg=${THEME[foreground]},bold,nodim]$window_number#W#[nobold]#{?window_zoomed_flag, $zoom_number, $custom_pane}#{?window_last_flag, , }"
# Unfocused
tmux set -g window-status-format "$RESET#[fg=${THEME[foreground]}] #{?#{==:#{pane_current_command},ssh},󰣀 ,$terminal_icon $window_space}${RESET}$window_number#W#[nobold,dim]#{?window_zoomed_flag, $zoom_number, $custom_pane}#[fg=${THEME[yellow]}]#{?window_last_flag,󰁯  , }"

#+--- Bars RIGHT ---+
# Build the status-right content
status_right_content=""

if widget_enabled "@tokyo-night-tmux_show_battery_widget"; then
  status_right_content="${status_right_content}#($SCRIPTS_PATH/battery-widget.sh)"
fi

if widget_enabled "@tokyo-night-tmux_show_path"; then
  status_right_content="${status_right_content}#($SCRIPTS_PATH/path-widget.sh #{pane_current_path})"
fi

if widget_enabled "@tokyo-night-tmux_show_music"; then
  status_right_content="${status_right_content}#($SCRIPTS_PATH/music-tmux-statusbar.sh)"
fi

if widget_enabled "@tokyo-night-tmux_show_netspeed"; then
  status_right_content="${status_right_content}#($SCRIPTS_PATH/netspeed.sh)"
fi

if widget_enabled "@tokyo-night-tmux_show_git"; then
  status_right_content="${status_right_content}#($SCRIPTS_PATH/git-status.sh #{pane_current_path})"
fi

if widget_enabled "@tokyo-night-tmux_show_wbg"; then
  status_right_content="${status_right_content}#($SCRIPTS_PATH/wb-git-status.sh #{pane_current_path})"
fi

if widget_enabled "@tokyo-night-tmux_show_datetime"; then
  status_right_content="${status_right_content}$($SCRIPTS_PATH/datetime-widget.sh)"
fi

tmux set -g status-right "$status_right_content"
tmux set -g window-status-separator ""
