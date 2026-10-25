# Isolated Master System controller geometry

`SMS_Controller_neutral.glb` is a texture-free derivative of the project's existing `SMS_Assembly.glb`, not a new controller design or a purchased third-party model. The source file is preserved unchanged. Its SHA-256 and the output SHA-256 are in `SMS_Controller_validation.json`.

## What was retained

The 22 non-photographic meshes under `SMS_CONTROLLER_ROOT`, their existing solid material colors and local transforms except the explicitly documented strain-relief correction below. The original root's exhibit-world translation was removed; root is now identity. Original dimensions and detail geometry were not remodeled. Normal-map texture references were removed as well, so the output has no external or embedded image dependencies. No console, cartridge, box, original cable, unrelated mesh or unused photograph payload is retained.

Two photographic planes, `Pad_direction_frame_print` and `Pad_SEGA_and_button_print`, were omitted. The actual controller reference pixels were inspected: CONTROL PAD, 1 START, 2 and a SEGA wordmark are visible. This neutral derivative intentionally does not reproduce those markings, decorative frame printing, or the wordmark; no invented logo or substituted branding was added. Therefore this is reusable neutral geometry, not a claim of complete decorated fidelity. A separately verified, rights-cleared vector artwork pass remains possible.

## Placement contract

- glTF and Godot convention: meters, Y up; pad face points +Y.
- Approximate shell width: 0.1071 m; depth: 0.0441 m. Shell underside Y: 0.001 m; maximum upper geometry Y: 0.0178 m.
- Named empty `ControllerCableAnchor`: (0.011, 0.010500014, -0.0265), at the corrected rear-entry strain-relief tip.
- Cable starts in controller-local -Z direction. The anchor is rotated +90 degrees around Y, so its own basis.x is the actual outward cable tangent. The strain relief has the same rotation and center (0.011, 0.010500014, -0.0235). Its original mesh vertices/materials are unchanged; only this derivative node transform and named anchor were corrected. The unmodified legacy source uses side entry, whereas the inspected photograph clearly shows rear/top entry. The horizontal position X=0.011 m is estimated from perspective photo proportions, with roughly ±0.004 m uncertainty, not a measured hardware dimension. Y and relief dimensions are retained from the original geometry; Z provides approximately 1.4–1.5 mm shell overlap. This is a bounded reference-based correction, not a claim about every controller variant.
- Instance one asset twice if two pads are desired; this does not represent two distinct source designs.

## Cable strategy, not baked cable geometry

The source `Controller_cable` is parented to the console, with a pose tied to the old assembly layout. It is deliberately excluded. At exhibit runtime, transform the pad anchor and departure tangent into exhibit space, then create an independent smooth tube curve to the selected console socket. Use a short initial tangent along the strain relief, a slack loop above the presentation surface, and an endpoint tangent normal to the front socket. Avoid the cartridge, box, other cable, and controller face. Recompute endpoints if layout moves. A roughly 0.0015 m cable radius, 8 radial segments and 32-48 curve samples are a starting performance budget, not a measured historical specification.

## Validation and limits

Extraction validates GLB header/length, finite position values, triangle index bounds, source preservation and zero image/texture tables. The output contains 22 meshes and 6,832 triangles, 279,736 bytes. No heavy Blender or Godot session was run during concurrent graphical QA. Runtime import, camera views and cable intersection QA remain the integrating exhibit's responsibility. The extraction script is editable and reproducible using an explicitly supplied local source path.

Removing third-party photography makes this derivative photo-free, but does not independently establish the underlying legacy geometry's ownership or confer trademark rights. This file records technical provenance, not a legal license determination. No source reference photograph, private instructions, or unrelated file is included.

## Optional editable wording source

`SMS_Controller_verified_labels.svg` independently typesets only the three verified labels CONTROL PAD, 1 START and 2, with no source photograph pixels and no SEGA wordmark. Its generic font choices are not exact historical typography. Relative placement follows the visible layout and mesh coordinates, but remains an approximate overlay requiring visual verification at integration. It is deliberately not embedded in the neutral GLB or enabled automatically. The SVG maps local X/Z in millimeters to its 107 × 44 canvas by adding (53.5, 22). A future face overlay should sit above Y=0.01438 with transparent alpha, avoiding depth fighting. The source is vector/editable, not a raster photo derivative.
