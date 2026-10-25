#!/usr/bin/env bash
# Run from any directory. Requires Godot 4.6.3+ and Python 3.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path "$ROOT" --editor --quit
for name in selection history inspection focus_visibility controls controls_propagation library library_view library_propagation library_catalog library_presentation box_presentation manual_reader manual_integration collection_scan game_media hardware_media controller_connector controller_cable box_hinge box_dual_hinge box_sleeve_margin perspective_box_view perspective_home exhibit exhibit_integration zoom_stress; do
  "$GODOT" --headless --path "$ROOT" --script "cosmic/test_${name}.gd"
done
cd "$ROOT"
python3 tools/audit_public_assets.py
python3 tools/test_card_recess.py
