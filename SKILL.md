---
name: freewinly
description: FreeWinly - Open source, bloatware-free Windows PC maintenance & diagnostic engine using native Windows board tools (Winget, PowerShell 5.1+, COM APIs, DISM, and TRIM). Use whenever the user asks to check, maintain, update, audit, or clean their PC.
---

# FreeWinly - Open Source Windows Maintenance & AI Agent Playbook

FreeWinly is a native Windows maintenance engine built without third-party dependencies. It operates in two modes:
1. **Human Mode:** Pure standalone PowerShell/TUI with zero AI dependencies (ideal for family PCs, offline environments, and purists).
2. **AI Harness Mode:** Pairs with AI assistants (Antigravity, Claude Code, Cursor) as a token-efficient diagnostic and configuration toolbelt.

---

## Repository Architecture

```text
FreeWinly/
├── freewinly.ps1                        <-- Master runner (CLI + TUI + AST Gatekeeper + JIT elevation)
├── freewinly.cmd                        <-- Double-clickable batch launcher (%* arguments)
├── config.json                          <-- Execution order, per-module settings, generic hooks
├── SKILL.md                             <-- AI Agent Playbook
├── core/
│   ├── freewinly-init-config.ps1        <-- First-run setup & exclusion wizard
│   ├── freewinly-setup-schedule.ps1     <-- Native Windows Task Scheduler installer (Weekly/Monthly/Logon/Remove)
│   ├── freewinly-setup-launcher.ps1     <-- Start Menu launcher manager (Install/Remove/Status)
│   ├── freewinly-setup-path.ps1         <-- User PATH CLI auto-complete manager (Add/Remove/Status/Toggle)
│   └── freewinly-uninstall.ps1          <-- Complete uninstaller with preview & confirmation
└── modules/
    ├── freewinly-check-hardware.ps1     <-- Device Manager & driver faults with actionable advice
    ├── freewinly-check-eventlog.ps1     <-- Recurring crashes & BSODs with plain-language fixes
    ├── freewinly-repair-applaunch.ps1   <-- Restores apps broken by dead sleep hooks & debuggers
    ├── freewinly-update-software.ps1    <-- Winget updates (respects per-module exclusions)
    ├── freewinly-update-windows.ps1     <-- Native Windows OS & Defender Updates
    ├── freewinly-clean-cache.ps1        <-- Safe temp/cache cleaning (> 7 days)
    ├── freewinly-clean-browsers.ps1     <-- Disposable browser & desktop app cache cleanup
    ├── freewinly-clean-network.ps1      <-- Network cache flush & latency diagnostics
    ├── freewinly-clean-winsxs.ps1       <-- Windows Component Store DISM cleanup & SFC verification
    ├── freewinly-trim-ssd.ps1           <-- SSD NVMe TRIM ReTrim optimization
    └── freewinly-defrag-hdd.ps1         <-- Mechanical HDD Defrag (auto-skips on SSD-only PCs)
```

---

## AI Agent Playbook (How LLMs Use FreeWinly)

### Background: Elevation and Context Limits
1. **Background AI agents cannot click UAC desktop prompts.** If an agent tries to run an elevated command in a headless console, Windows blocks the session waiting for desktop confirmation.
2. **Raw diagnostic queries consume unnecessary tokens.** Running exploratory PowerShell commands across multiple turns quickly exhausts context.

### The 4-Step Agent Workflow

```text
[User asks AI to check PC]
        |
        v
Step 1: AI runs `.\freewinly.ps1 -Check` (or -Audit)
        - FreeWinly executes all modules locally in seconds.
        - Returns a structured health summary (~300 tokens).
        |
        v
Step 2: AI analyzes findings & updates `config.json`
        - Excludes failing packages under `modulesExecutionOrder.freewinly-update-software.excluded` or adds uninstalls.
        - Stages natural language postponements (e.g. "skip Blender for 1 week").
        - Configures per-module settings (`minAgeDays`, `excludedDrives`, `minIntervalDays`) or pre/post commands.
        |
        v
Step 3: AI sets up Start Menu launcher (if not present)
        - Runs `.\core\freewinly-setup-launcher.ps1`
        |
        v
Step 4: AI informs user to execute elevated maintenance
        - "I checked your PC and updated config.json.
           Press Windows Key, type 'FreeWinly', and press Enter."

### Targeted Crash & Stability Debugging
When the user reports instability or asks what happened at a specific time (e.g., "my PC crashed last weekend" or "check errors over the last two weeks"):
* **Inspect specific day counts:** `.\modules\freewinly-check-eventlog.ps1 -Days 14`
* **Inspect from a start date until today:** `.\modules\freewinly-check-eventlog.ps1 -StartDate "2026-10-18"`
* **Inspect an exact historical window:** `.\modules\freewinly-check-eventlog.ps1 -StartDate "2026-10-17" -EndDate "2026-10-19"`
This gives instant, grouped crash forensics with root-cause advice without running full maintenance.
```

### Managing Postponements in Natural Language
When a user says:
* *"Don't update Photoshop for the next two weeks"*
* *"Hold off on updating Blender until next Monday, I'm working on a project"*

The AI agent should:
1. Identify the package ID (or name).
2. Calculate the target ISO date (`YYYY-MM-DD`).
3. Add a structured postponement object into `config.json` under `modulesExecutionOrder.freewinly-update-software.excluded`:
   ```json
   { "id": "BlenderFoundation.Blender", "until": "2026-10-29", "reason": "User requested hold during active project" }
   ```
4. Confirm to the user: *"Done. Blender updates are postponed until October 29th. FreeWinly will automatically remove the postponement once that date passes."*

---

## Usability & TUI Features

### 1. 10-Second Auto-Start Countdown
* When launched (`freewinly.cmd` or Start Menu `FreeWinly.lnk`), it displays scheduled tasks and counts down from 10 seconds.
* **Unattended Mode:** If no key is pressed, it executes default tasks and cleanly exits.
* **Interactive Mode:** Pressing any key opens the interactive console menu.

### 2. Interactive Tree-View Menu (`[+]` / `[-]`) & Hotkeys
* Navigate with **[Up/Down]** arrows across modules, editable sub-options, and action items.
* Toggle individual modules or boolean/per-drive sub-options with **[Space]** (`[x]` / `[ ]`).
* Expand or collapse sub-options for the highlighted module with **[Tab]**. Expanding `SSD TRIM Optimization` or `Mechanical HDD Defragmentation` exposes interactive per-drive `[x]` / `[ ]` checkboxes that directly manage `excludedDrives` in `config.json`.
* Fine-tune sub-options with **[Left/Right]** arrows (collapse/expand, toggle bools/drives, step integer slider presets).
* Reorder module execution sequence with **[+]** / **[-]** (`Move Up` / `Move Down`), keeping selection anchored.
* **[ Enter ]** -> **Run All Checked Tasks [x]** (executes all checked modules immediately; prompts for UAC only if required).
* **[ C ] / [ A ]** -> **Dry-Run Check / Diagnostic Audit** (inspects pending updates, hardware errors, and cache savings without modifying system state).
* **[ E ]** -> **Cycle Sub-Options View Mode** (`Hidden` -> `Custom` -> `Expanded`).
* **[ T ]** -> **Cycle Auto-Start Countdown** (`0s`, `3s`, `5s`, `10s`, `20s`, `30s`).
* **[ W ]** -> **Schedule Maintenance in Windows Task Scheduler** (interactive panel with `D` weekday cycler and `+`/`-` hour adjustments).
* **[ P ]** -> **Toggle User `PATH` CLI Auto-Complete** (adds/removes FreeWinly in the current User's `PATH` without requiring Admin rights).
* **[ S ]** -> **Save Selection & Order as Default** (saves current checkboxes, execution order, sub-options, view mode, and timer to `config.json`).
* **[ O ]** -> **Run Configuration & Exclusion Wizard** (detects standalone/unknown packages).
* **[ I ]** -> **Install or Update Start Menu Launcher**.
* **[ U ]** -> **Complete Uninstaller** (previews and removes Task Scheduler jobs, shortcuts, User `PATH`, and application directory).
* **[ Q ]** -> **Quit Without Running**.

### 3. Modular Extensibility (`Info / Check / Run`) & AST Gatekeeper
Every module is self-contained, works standalone via CLI (using `DefaultSettings`) or via `freewinly.ps1` (which merges `DefaultSettings` with the module's config block and passes `-Settings`), and is validated by `Test-ModuleContract` before execution:
```powershell
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [Parameter()]
    [PSObject]$Settings = $null,

    [Parameter()]
    [string]$LogFile = $null
)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name            = "My Custom Task"
        Description     = "Does specific cleanup (max 120 chars)"
        Order           = 35
        Default         = $false
        RequiresAdmin   = $false
        DefaultSettings = [ordered]@{
            maxDays = 14
        }
    }
}

if ($Action -eq 'Check') {
    Write-Host "Dry run preview: would perform my task." -ForegroundColor Yellow
    return
}

Write-Host "Executing task..." -ForegroundColor Green
```

---

## Configuration Schema (`config.json`)

- `countdownSeconds`: Seconds before auto-starting maintenance (default: 10).
- `scheduleType`, `scheduleDay`, `scheduleTime`: Task Scheduler configuration.
- `preCommands`: Arbitrary PowerShell commands to run before modules.
- `uninstall`: Package IDs to remove via Winget before installations.
- `install`: Package IDs to freshly install.
- `postCommands`: Arbitrary PowerShell commands to run after modules.
- `modulesExecutionOrder`: Ordered map of module base names defining top-to-bottom execution sequence and per-module settings:
  - `freewinly-check-hardware`: `{ "enabled": true }`
  - `freewinly-check-eventlog`: `{ "enabled": true, "lookbackDays": 7 }`
  - `freewinly-repair-applaunch`: `{ "enabled": true }`
  - `freewinly-update-software`: `{ "enabled": true, "excluded": [ ... ] }`
  - `freewinly-update-windows`: `{ "enabled": false }`
  - `freewinly-clean-cache`: `{ "enabled": true, "minAgeDays": 7, "cleanRecycleBin": false }`
  - `freewinly-trim-ssd`: `{ "enabled": true, "excludedDrives": [], "minIntervalDays": 0, "lastRun": null }`
  - `freewinly-defrag-hdd`: `{ "enabled": true, "excludedDrives": [], "minIntervalDays": 30, "lastRun": null }`
