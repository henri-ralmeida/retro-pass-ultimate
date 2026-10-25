#!/usr/bin/env bash
# Run from any directory. Requires Godot 4.6.3+ and Python 3.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path "$ROOT" --editor --quit
for name in visit_autostart automatic_entry atari_insertion_library atari_private_media atari_proof_input atari_library_view atari_library_input atari_main_integration atari_material_budget selection history inspection focus_visibility controls controls_propagation controller_stage controller_store controller_panel controller_gui_propagation controller_layout controller_host controller_home_picker library library_view library_propagation library_catalog catalog_choice catalog_choice_integration catalog_import library_inventory_labels library_window library_artwork_cache library_virtualization library_wheel library_presentation box_presentation manual_reader manual_integration manual_book manual_book_reader manual_release_path manual_release_lateral manual_viewport collection_scan game_media hardware_media controller_connector controller_cable box_hinge box_dual_hinge box_sleeve_margin perspective_box_view perspective_home exhibit exhibit_integration zoom_stress; do
  "$GODOT" --headless --path "$ROOT" --script "cosmic/test_${name}.gd"
done
# Two distinct processes with isolated user data verify gameplay-only persistence.
restart_data="$(mktemp -d "${TMPDIR:-/tmp}/retropass-controller-restart.XXXXXX")"
XDG_DATA_HOME="$restart_data" "$GODOT" --headless --path "$ROOT" --script cosmic/test_controller_restart.gd -- --write
XDG_DATA_HOME="$restart_data" "$GODOT" --headless --path "$ROOT" --script cosmic/test_controller_restart.gd
rm -rf -- "$restart_data"
cd "$ROOT"
python3 tools/audit_public_assets.py
python3 tools/test_card_recess.py
