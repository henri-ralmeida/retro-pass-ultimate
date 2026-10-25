#!/usr/bin/env bash
# Run from any directory. Requires Godot 4.6.3+ and Python 3.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
# Never read or mutate a developer/user catalog, credentials or controls during QA.
verify_root="$(mktemp -d "${TMPDIR:-/tmp}/retropass-verify.XXXXXX")"
trap 'rm -rf -- "$verify_root"' EXIT
# Integration suites explicitly opt out of the welcome modal; its own tests exercise it.
export RETROPASS_DISABLE_AUTOMATIC_TOUR=1
export XDG_DATA_HOME="$verify_root/data"
export XDG_CONFIG_HOME="$verify_root/config"
export XDG_CACHE_HOME="$verify_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
if [[ "${RETROPASS_SKIP_IMPORT:-0}" == "1" ]]; then
  echo "IMPORT NOT RUN: explicit RETROPASS_SKIP_IMPORT=1; this is a tests-only run, not a clean aggregate PASS."
else
  "$GODOT" --headless --path "$ROOT" --editor --quit
fi
for name in manual_pdf_boundary manual_pdf_manifest media_tour_main media_binding_store media_first_use_tour media_host_restore achievements media_release_gate media_opening_gesture media_host_resume_applied media_layout media_catalog_refresh media_confirmation_consent media_optin media_review_regressions media_service_panel media_host_store media_result_association media_host_integration sms_insertion_natural sms_insertion_path sms_mechanical_loader sms_insertion_library visit_autostart automatic_entry atari_insertion_library atari_private_media atari_proof_input atari_library_view atari_library_input atari_main_integration atari_material_budget selection history inspection focus_visibility controls controls_propagation controller_stage controller_store controller_panel controller_gui_propagation controller_layout controller_host controller_home_picker library library_view library_propagation library_catalog catalog_choice catalog_choice_integration catalog_import library_inventory_labels library_window library_artwork_cache library_virtualization library_wheel library_presentation box_presentation manual_reader manual_integration manual_book manual_book_reader manual_release_path manual_release_lateral manual_viewport collection_scan game_media hardware_media controller_connector controller_cable box_hinge box_dual_hinge box_sleeve_margin perspective_box_view perspective_home exhibit exhibit_integration zoom_stress; do
  "$GODOT" --headless --path "$ROOT" --script "cosmic/test_${name}.gd"
done
# Local media journal/settings persistence across fresh processes (synthetic only).
media_restart_data="$(mktemp -d "${TMPDIR:-/tmp}/retropass-media-restart.XXXXXX")"
for stage in write resume recover; do
  XDG_DATA_HOME="$media_restart_data" "$GODOT" --headless --path "$ROOT" --script cosmic/test_media_optin_persistence.gd -- "$stage"
done
rm -rf -- "$media_restart_data"
# Exact media overlays and tour decision across four fresh processes.
binding_restart_data="$(mktemp -d "${TMPDIR:-/tmp}/retropass-binding-restart.XXXXXX")"
for stage in write restore recover reject_changed; do
  XDG_DATA_HOME="$binding_restart_data" "$GODOT" --headless --path "$ROOT" --script cosmic/test_media_binding_restart.gd -- "$stage"
done
rm -rf -- "$binding_restart_data"
# Two distinct processes with isolated user data verify gameplay-only persistence.
restart_data="$(mktemp -d "${TMPDIR:-/tmp}/retropass-controller-restart.XXXXXX")"
XDG_DATA_HOME="$restart_data" "$GODOT" --headless --path "$ROOT" --script cosmic/test_controller_restart.gd -- --write
XDG_DATA_HOME="$restart_data" "$GODOT" --headless --path "$ROOT" --script cosmic/test_controller_restart.gd
rm -rf -- "$restart_data"
cd "$ROOT"
python3 tools/audit_public_assets.py
python3 tools/test_card_recess.py
