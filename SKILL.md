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
├── freewinly.ps1                <-- Master runner (CLI + TUI + JIT elevation + -ConfigPath)
├── freewinly.cmd                <-- Double-clickable batch launcher (%* arguments)
├── install-shortcut.ps1         <-- Start Menu shortcut manager (Install/Remove)
├── install-task.ps1             <-- Native Windows Task Scheduler installer (Weekly/Monthly/Logon/Remove)
├── uninstall.ps1                <-- Complete uninstaller with preview & confirmation
├── config.json                  <-- Exclusions, enabled modules, generic hooks
├── SKILL.md                     <-- AI Agent Playbook
└── modules/
    ├── 10_hardware_health.ps1   <-- Device Manager & driver faults with actionable advice
    ├── 11_event_log_health.ps1  <-- Recurring crashes & BSODs with plain-language fixes
    ├── 12_app_launch_repair.ps1 <-- Restores apps broken by dead sleep hooks & debuggers
    ├── 20_software_updates.ps1  <-- Winget updates (respects config exclusions)
    ├── 21_windows_updates.ps1   <-- Native Windows OS & Defender Updates
    ├── 30_cache_cleanup.ps1     <-- Safe temp/cache cleaning (> 7 days)
    ├── 31_ssd_trim.ps1          <-- SSD NVMe TRIM ReTrim optimization
    └── 32_hdd_defrag.ps1        <-- Mechanical HDD Defrag (auto-skips on SSD-only PCs)
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
        - Excludes failing packages or adds uninstalls.
        - Stages natural language postponements (e.g. "skip Blender for 1 week").
        - Configures cleanup thresholds or pre/post commands.
        |
        v
Step 3: AI sets up Start Menu shortcut (if not present)
        - Runs `.\install-shortcut.ps1`
        |
        v
Step 4: AI informs user to execute elevated maintenance
        - "I checked your PC and updated config.json.
           Press Windows Key, type 'FreeWinly', and press Enter."
```

### Managing Postponements in Natural Language
When a user says:
* *"Don't update Photoshop for the next two weeks"*
* *"Hold off on updating Blender until next Monday, I'm working on a project"*

The AI agent should:
1. Identify the package ID (or name).
2. Calculate the target ISO date (`YYYY-MM-DD`).
3. Add a structured postponement object into `config.json` under `excluded`:
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

### 2. Interactive Checkbox Menu & Hotkeys
* Navigate with **[Up/Down]** arrows.
* Toggle individual modules with **[Space]** (`[x]` / `[ ]`).
* **[ Enter ]** -> **Run All Checked Tasks [x]** (executes all checked modules immediately; prompts for UAC only if required).
* **[ C ] / [ A ]** -> **Dry-Run Check / Diagnostic Audit** (inspects pending updates, hardware errors, and cache savings without modifying system state).
* **[ T ]** -> **Cycle Auto-Start Countdown** (`0s`, `3s`, `5s`, `10s`, `20s`, `30s`).
* **[ W ]** -> **Schedule Maintenance in Windows Task Scheduler** (interactive panel with `D` weekday cycler and `+`/`-` hour adjustments).
* **[ S ]** -> **Save Selection as Default** (saves current checkboxes and timer to `config.json` for future runs).
* **[ O ]** -> **Run First-Time Onboarding Wizard** (detects standalone/unknown packages).
* **[ I ]** -> **Install or Update Start Menu Shortcut**.
* **[ U ]** -> **Complete Uninstaller** (previews and removes Task Scheduler jobs, shortcuts, and application directory).
* **[ Q ]** -> **Quit Without Running**.

### 3. Modular Extensibility (`Info / Check / Run`)
Every module is self-contained and implements the standard contract:
```powershell
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',
    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name          = "My Custom Task"
        Description   = "Does specific cleanup"
        Default       = $true
        RequiresAdmin = $false
        Options       = @{}
    }
}

if ($Action -eq 'Check') {
    Write-Host "Dry run preview: would perform my task." -ForegroundColor Yellow
    return
}

Write-Host "Executing task..." -ForegroundColor Green
```

---

## Generic Pipeline Hooks (`config.json`)

- `preCommands`: Arbitrary PowerShell commands to run before modules.
- `uninstall`: Package IDs to remove via Winget before installations.
- `install`: Package IDs to freshly install.
- `excluded`: Permanent string IDs or date-postponed objects (`{"id": "...", "until": "YYYY-MM-DD"}`). Expired dates are automatically removed.
- `postCommands`: Arbitrary PowerShell commands to run after modules.
- `enabledModules`: Array of module base names to run by default.
- `cleanupTempMinAgeDays`: Minimum age of temp files to purge (default: 7).
- `eventLogLookbackDays`: Number of lookback days for crash scanning (default: 7).
- `hddDefragMinDays`: Minimum days elapsed between mechanical HDD defrags (default: 30).
