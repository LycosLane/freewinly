## FreeWinly v1.7.2

Reliability, packaging determinism, and edge-case hardening release:

- **TUI Reorder Persistence:** Fixed `Save-ConfigState` so module reordering with `[+]` and `[-]` in the TUI is properly persisted to `config.json`.
- **Deterministic Release Packaging:** Renormalized repository line endings, enforced canonical EOLs and culture-invariant ordinal sorting in `tools/bundle.ps1` and `tools/bump-version.ps1`, and re-synced the Scoop manifest hash.
- **WinGet Scanning & Encoding:** Added support for `+` in WinGet package IDs, preserved full `< x.y.z` version strings without truncation, propagated WinGet scan failures instead of reporting clean updates, and wrapped all WinGet calls in UTF-8 console encoding.
- **Elevation & Output Propagation:** Quoted module lists across UAC elevation, failed fast with a clear message when `-Settings` requires elevation, propagated `Advanced` verbosity to storage modules via `FREEWINLY_OUTPUT_MODE`, and counted hardware/eventlog query failures in error totals.
- **System Integration & Hardening:** Broadcast `WM_SETTINGCHANGE` after User PATH updates, routed `freewinly-setup-schedule.ps1` through `Get-SafeConfigFile`, handled DISM exit code `3010` as a reboot-required notice, wrote UTF-8 without BOM in config I/O, and hardened `-LiteralPath`, `[int]::TryParse`, and nested JSON validation across core and modules.
