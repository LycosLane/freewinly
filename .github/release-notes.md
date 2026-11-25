## FreeWinly v1.7.3

Bug fixes and hardening following the v1.7.2 codebase audit:

- **Hook State & Retry Accounting:** Fixed unary-comma array wrapping in `Invoke-SecuredCommandsHook` and `Invoke-SecuredPackagesHook` so cleared hooks are properly removed from `config.json`, and preserved non-retryable module error counts during `[R]` retries.
- **Standalone Self-Updater:** Fixed nested directory copying in `core/freewinly-self-update.ps1` so subdirectories like `assets\icons\` are updated in place without creating duplicate nested folders.
- **Event Log & Dry-Run Status Accuracy:** Fixed false `[ Notice ]` output on clean event logs, surfaced detected hardware/applaunch/Windows Update findings as `[ Notice ]` in `-Check` Standard Mode, and eliminated duplicate WinGet scans when zero updates are pending.
- **Task Scheduler & Packaging:** Fixed the Logon task trigger `.Delay` property, stripped gitignored `*_local_*.ps1` and `*_custom_*.ps1` modules in `tools/bundle.ps1`, and added UTF-8 encoding wrappers for standalone `freewinly-update-software.ps1 -Action Run`.
- **Hardening & Exit Codes:** Resolved relative non-existent `-ConfigPath` values against PowerShell `$PWD`, validated config integer and schedule defaults safely, fixed WinGet cache prefix matching in `freewinly-clean-cache.ps1`, guarded `Clear-Host` in headless `-Run` mode, and improved exit code / cleanup status reporting in PATH and uninstall helpers.
