---
name: freewinly
description: FreeWinly - Open source, bloatware-free Windows PC maintenance & diagnostic engine using native Windows board tools (Winget, PowerShell 5.1+, COM APIs, DISM, and TRIM). Use whenever the user asks to check, maintain, update, audit, or clean their PC.
---

# FreeWinly – Open Source Windows Maintenance & AI Agent Playbook

FreeWinly is a 100% native Windows maintenance engine built without third-party dependencies. It operates in two modes:
1. **Human Mode:** Pure standalone PowerShell/TUI with zero AI dependencies (ideal for family PCs, offline environments, and purists).
2. **AI Harness Mode:** Pairs with AI assistants (Antigravity, Claude Code, Cursor) as a token-efficient diagnostic and configuration toolbelt.

---

## Repository Architecture

```text
FreeWinly/
├── freewinly.ps1                <-- Master runner (CLI + TUI + JIT elevation + -ConfigPath)
├── freewinly.cmd                <-- Double-clickable batch launcher (%* arguments)
├── install-shortcut.ps1         <-- Dynamic Start Menu shortcut installer
├── config.json                  <-- Exclusions, enabled modules, generic hooks
├── SKILL.md                     <-- AI Agent Playbook
└── modules/
    ├── 05_hardware_health.ps1   <-- Device Manager & driver faults with actionable advice
    ├── 06_event_log_health.ps1  <-- Recurring crashes & BSODs with plain-language fixes
    ├── 10_software_updates.ps1  <-- Winget updates (respects config exclusions)
    ├── 20_cache_cleanup.ps1     <-- Safe temp/cache cleaning (> 7 days)
    ├── 30_ssd_trim.ps1          <-- SSD NVMe TRIM ReTrim optimization
    ├── 35_hdd_defrag.ps1        <-- Mechanical HDD Defrag (auto-skips on SSD-only PCs)
    └── 40_windows_updates.ps1   <-- Native Windows OS & Defender Updates
```

---

## AI Agent Playbook (How LLMs Use FreeWinly)

### The Problem: The Windows Elevation & Token Trap
1. **Background AI agents cannot click UAC desktop dialogs.** If an LLM tries to run an elevated command in a headless console, Windows blocks or hangs the session waiting for desktop confirmation.
2. **Raw diagnostic discovery burns thousands of tokens.** If an AI runs 15 exploratory PowerShell commands across 10 chat turns, it exhausts context and time.

### The Solution: The 4-Step Agent Workflow

```
[User asks AI to check PC]
        │
        ▼
Step 1: AI runs `.\freewinly.ps1 -Check` (or -Audit)
        └── FreeWinly executes all modules in < 1 second.
        └── Returns condensed, pre-digested health summary in 1 turn (~300 tokens).
        │
        ▼
Step 2: AI analyzes findings & updates `config.json`
        └── Excludes failing packages or adds uninstalls.
        └── Stages natural language postponements (e.g. "skip Blender for 1 week").
        └── Configures desired cleanup thresholds or pre/post commands.
        │
        ▼
Step 3: AI sets up Start Menu shortcut (if not present)
        └── Runs `.\install-shortcut.ps1`
        │
        ▼
Step 4: AI informs user to execute elevated maintenance
        └── "I audited your PC and prepared the optimizations in config.json.
             Simply press Windows Key, type 'FreeWinly', and hit Enter!"
```

### Natural Language Postponements (Zero-Friction User Experience)
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
4. Confirm to the user: *"Done! Blender updates are postponed until October 29th. FreeWinly will automatically clean up the exclusion once that date passes."*

---

## Usability & TUI Features

### 1. 10-Second Auto-Start Countdown
* When launched (`freewinly.cmd` or Start Menu `FreeWinly.lnk`), it displays scheduled tasks and counts down from 10 seconds.
* **Unattended Mode:** If no key is pressed, it executes default tasks and cleanly exits.
* **Interactive Mode:** Pressing any key opens the interactive console menu.

### 2. Interactive Checkbox Menu & Hotkeys
* Navigate with **[Up/Down]** arrows.
* Toggle individual modules with **[Space]** (`[x]` / `[ ]`).
* **[ Enter ]** $\rightarrow$ **Run All Checked Tasks [x]** (executes all checked modules immediately; triggers UAC only if required).
* **[ C ] / [ A ]** $\rightarrow$ **Dry-Run Check / Diagnostic Audit** (inspects pending updates, hardware errors, and cache savings without modifying system state).
* **[ S ]** $\rightarrow$ **Save Selection as Default** (persists current checkboxes to `config.json` for future unattended runs).
* **[ O ]** $\rightarrow$ **Run First-Time Onboarding Wizard** (detects standalone/unknown packages).
* **[ I ]** $\rightarrow$ **Reinstall Start Menu Shortcut** (dynamically updates shortcut).
* **[ Q ]** $\rightarrow$ **Quit Without Running**.

### 3. Modular Extensibility (`Info / Check / Run`)
Every module is 100% self-contained and implements the standard contract:
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
