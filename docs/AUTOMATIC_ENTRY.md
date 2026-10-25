# Automatic Atari entry

Historical baseline: published commit `aa0dafbd37e10ff3b02916ba9b2dc0af473e1f23`.

Selecting a console retains its existing catalog policy. The Atari library uses `CatalogChoice` and currently has only the explicitly supplied Adventure entry. This hook does not implement a multi-entry Atari media library: the Atari UI and source assets remain bound to one explicit manifest. Repeated catalog preparation within the same visit is idempotent; closing ends the visit. Exact catalog IDs, including variant IDs, are preserved. Inventory availability is not inferred from local ROM bytes. No ROMs are read, downloaded or executed.

A real `enter_library` request arms a one-shot intention for that visit. Only after the entry movement and reveal veil finish may the eligible Atari cartridge sequence start. It uses the existing source-bound session and the same canonical cartridge. Missing or changed media leaves honest inspection/manual controls without substitution. The manual insertion button remains available for deliberate repetition.

Two guards protect delayed work: a main transition generation plus the target library instance ID, and an Atari visit token bound to its selected catalog ID. Close, console replacement, Back and deliberate inspection/manual insertion invalidate pending intentions. Stale interpolation, transition completion and reveal callbacks cannot mutate a newer visit. Returning the cartridge to its box does not arm another automatic start.

Focus loss before automatic start cancels the pending intention, including during the reveal veil. Refocusing does not rearm it; the user can use the manual insertion button. Focus loss after insertion has begun pauses the existing path without accumulating elapsed time. Reduced motion reaches coherent entry/insertion endpoints without waiting for an animation.

Master System retains its existing catalog choice and approved HOME views. Its separate library insertion hook is conditional on a validated private mechanical override and matching local media; see [SMS insertion](SMS_INSERTION.md). Without those prerequisites it does not start an insertion or reroll the selected entry. This does not imply that all inventory entries have animation-ready media. SMS catalog visits and per-entry automatic-start tokens have distinct lifecycles, as documented there.

Verification covers the pure one-shot token, idempotent catalog draw, stale callbacks after close/reopen and console swap, pending versus active focus loss, Back-to-box without restart, missing media, reduced motion, and natural asynchronous transition completion. Rendered GUI review is separate from headless behavioral tests. Source assets, approved cameras and the insertion rig are unchanged by this integration.
