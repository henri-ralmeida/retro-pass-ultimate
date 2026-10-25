# Atari insertion integration

Historical baseline: published commit `35dae57d4141695be232c85fe36ebcc6ddfb25d7`.

The Atari library uses its existing orthographic camera, frontend theme/background and Portuguese controls. `Inserir cartucho` owns the one existing canonical cartridge for opening native carton flaps, extraction, alignment and axial insertion. `Voltar` during any phase retraces the same path and returns to the collection only after reaching the exact inside-box transform; a subsequent Back exits the library. Repeated starts are idempotent and repeated Back cannot skip reversal. No reparent or duplicate cartridge.

The source-bound session is prepared while the exhibit is hidden before the collection is shown. Existing box/cartridge/manual inspections remain independent. Returning from inspection closes/restores source layout while hidden, then prepares the inside-box cartridge again. Forced library close hides before teardown; reopening restores a fresh closed session. Manual leaves retain their native controls.

Animation owns model transforms exclusively. Inspection, rotation and zoom cannot overwrite the animated pose. Collection pointer gestures no longer drag models; voluntary manipulation remains available in explicit inspection. Window-focus loss or inactive host freezes time without catch-up. The existing reduced-motion preference reaches coherent endpoints without animation.

Only the explicitly supplied Adventure entry is offered for Atari. No inferred titles, ROM reads, ROM downloads, emulator execution or asset substitution. Missing source hashes/media disable insertion honestly while original available inspections remain usable. The source's exact retail pairing is still unverified; no new authenticity claim.

Geometry is a source-model candidate, not measured hardware depth. At seat panel-local Y = −8 mm it avoids source ribs/guide interference; sampled source-triangle tests establish only sampled noninterference. Camera remains the approved orthographic view; the separate perspective diagnostic exposed source/render stippling and was rejected. No free camera angles are added during animation.

Tests: `test_insertion.gd`: 339 checks; `test_atari_insertion_library.gd`: 88 private / 3 absent checks; full aggregate includes the latter's absent-media path and preserves all former tests. GUI/visual validation and release manifest are separate gates. The integration preserves HOME/main, SMS geometry and the source assets.

Unexpected guard failure latches an honest error. The next Back hides before teardown/exit; removed canonical, box or console roots are rebuilt on reopening. Close is idempotent, including repeated close after failure. Variant guards reject freed object references before any typed assignment.

Confirm while the transient insertion state owns input is consumed without reactivating the focused Back control, avoiding accidental cancellation from repeated confirm. Explicit Back/Escape/gamepad-back and the visible Back button still reverse the path. Failure before the first animation tick uses the same safe latch as mid-animation failure.
