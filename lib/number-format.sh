#!/usr/bin/env bash
#
# number_format builds a tmux-native format-string expression that
# substitutes each digit of a runtime target (e.g. #{window_index}) with
# a styled glyph at draw time. The substitution is performed by tmux's
# format engine — no shell is forked on redraw.
#
# Usage:
#   number_format "#{window_index}" digital
#   number_format "#{pane_index}"   hide
#
# Styles: hide, none, digital, fsquare, hsquare, dsquare, roman, super, sub
#
# Special case: the "roman" style only defines glyphs for digits 1-9 (and
# the empty string for 0), so multi-digit targets are passed through
# unchanged using a tmux conditional — matching the original
# custom-number.sh behavior.

number_format() {
  local target="$1"
  local style="${2:-none}"
  local digits expr digit replacement

  case "$style" in
  "hide")
    printf ""
    return
    ;;
  "none")
    digits=("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")
    ;;
  "digital")
    digits=("🯰" "🯱" "🯲" "🯳" "🯴" "🯵" "🯶" "🯷" "🯸" "🯹")
    ;;
  "fsquare")
    digits=("󰎡" "󰎤" "󰎧" "󰎪" "󰎭" "󰎱" "󰎳" "󰎶" "󰎹" "󰎼")
    ;;
  "hsquare")
    digits=("󰎣" "󰎦" "󰎩" "󰎬" "󰎮" "󰎰" "󰎵" "󰎸" "󰎻" "󰎾")
    ;;
  "dsquare")
    digits=("󰎢" "󰎥" "󰎨" "󰎫" "󰎲" "󰎯" "󰎴" "󰎷" "󰎺" "󰎽")
    ;;
  "roman")
    digits=("" "󱂈" "󱂉" "󱂊" "󱂋" "󱂌" "󱂍" "󱂎" "󱂏" "󱂐")
    ;;
  "super")
    digits=("⁰" "¹" "²" "³" "⁴" "⁵" "⁶" "⁷" "⁸" "⁹")
    ;;
  "sub")
    digits=("₀" "₁" "₂" "₃" "₄" "₅" "₆" "₇" "₈" "₉")
    ;;
  *)
    printf "%s " "$target"
    return
    ;;
  esac

  expr="$target"
  for digit in {9..0}; do
    replacement="${digits[$digit]} "
    expr="#{s|$digit|$replacement|:$expr}"
  done

  if [ "$style" = "roman" ]; then
    # For roman, only substitute when the target is a single digit; pass it
    # through verbatim otherwise. #{=1:X} truncates X to 1 character; if the
    # truncation equals the original, X is single-character.
    printf '#{?#{==:#{=1:%s},%s},%s,%s }' "$target" "$target" "$expr" "$target"
    return
  fi

  printf '%s' "$expr"
}
