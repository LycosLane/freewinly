# 🐋 FreeWinly

> **Free Windows from bloatware, aggressive cleaners, and subscription traps.**  
> *A transparent, modular, 100% native Windows maintenance engine.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows 10 / 11](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6.svg)]()
[![Shell: PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)]()
[![Zero Bloatware](https://img.shields.io/badge/Bloatware-0%25-brightgreen.svg)]()

```text
       .
      ":"
    ___:____     |"\/"|
  ,'        `.    \  /
  |  O        \___/  |    FreeWinly
~^~^~^~^~^~^~^~^~^~^~^~^~ Freeing your PC from the CCleaner trap.
```

---

## 💡 Why FreeWinly?

In the movie *Free Willy*, the captive orca was trapped in a theme park until he was finally freed. 

For years, Windows users have been trapped by proprietary "PC Cleaners" and "Driver Updaters" that charge annual subscriptions, install background telemetry, break modern Windows with aggressive registry cleaning, and nag you with scary warnings.

**FreeWinly breaks that cycle.**  
It proves that everything a modern Windows PC actually needs—keeping all applications updated like Linux `apt upgrade`, cleaning safe cache leftovers, running SSD TRIM, and auditing system health—can be done **100% cleanly using native Windows board tools** (`winget`, PowerShell, COM APIs, DISM).

---

## ✨ Features

- 📦 **The `apt update && apt upgrade` for Windows**  
  Uses Microsoft's official `winget` engine to update software silently one by one, with smart version-mismatch detection.
- ⏱️ **10-Second Auto-Start Countdown**  
  Launch and walk away! Ideal for family members or automated scheduled tasks: counts down 10 seconds, runs default tasks, and quietly exits.
- 🎛️ **Interactive Checkbox Menu (TUI)**  
  Press any key during countdown to open a clean terminal UI. Toggle tasks on/off with `[Space]`, run ad-hoc with `[Enter]`, or save as default with `[S]`.
- 💽 **SSD-Safe Maintenance**  
  Modern SSDs should never be defragmented. FreeWinly executes native NVMe/SATA TRIM (`Optimize-Volume -ReTrim`) to maintain flash memory longevity and performance.
- 🧹 **Safe Temp & Cache Cleaning**  
  Reclaims disk space from user and system temp folders, WinGet download caches, and DirectX shader caches—only purging files older than 7 days to prevent application crashes.
- 🔌 **Extensible Plugin Modules**  
  Add new maintenance routines in seconds! Just drop a numbered `.ps1` file into `modules/`, and FreeWinly automatically discovers it and adds it to the interactive menu.
- 🩺 **Hardware & Stability Doctor**  
  Scans Device Manager and Windows Event Logs, translating cryptic codes into human-actionable fixes (e.g. Code 28 driver updates, recurring application crashes, and dirty shutdowns).
- 🤖 **AI-Native Diagnostic Readiness**  
  Includes `SKILL.md` ready to pair with AI coding assistants (Antigravity, Claude Code, Cursor) to analyze system health in 1 single turn (~300 tokens) without burning context.

---

## 🚀 Quick Start

### Option 1: Double-Click (Zero Setup)
Clone or download this repository and simply double-click **`freewinly.cmd`**. It starts immediately without annoying UAC prompts, elevating Just-in-Time only if administrative tasks are selected.

### Option 2: Add to Windows Start Menu (Recommended)
Run the dynamic shortcut installer once:
```powershell
powershell -ExecutionPolicy Bypass -File .\install-shortcut.ps1
```
Now, whenever your computer needs a tune-up:
1. Press the **Windows Key**.
2. Type **`FreeWinly`** and hit **Enter**.
3. Let it run automatically (or press any key to customize tasks).

---

## 🎛️ Interactive TUI Controls

```text
============================================================
           FreeWinly - Open Source Windows Engine           
        Freeing Windows from bloatware, caches & fees       
============================================================
Use [Up/Down] arrows to navigate, [Space] to toggle, [Enter] to run:

  [x] Software Updates (Winget)
  [x] Safe Cache & Temp Cleanup (>7 days)
  [x] SSD TRIM Optimization [Admin]
  [ ] Windows OS & Security Updates [Admin]

------------------------------------------------------------
> [ Enter ]  Run All Checked Tasks [x]
  [   C   ]  Dry-Run Check Preview (No changes)
  [   A   ]  Run System Diagnostic Audit (Read-Only)
  [   S   ]  Save Selection as Default
  [   O   ]  Run First-Time Onboarding Wizard
  [   I   ]  Reinstall Start Menu Shortcut
  [   Q   ]  Quit Without Running
```

| Key | Action |
| :--- | :--- |
| **`Up` / `Down`** | Navigate between modules and actions |
| **`Space`** | Toggle module checkbox `[x]` / `[ ]` |
| **`Enter`** | Run all currently checked modules (triggers Just-in-Time UAC only if required) |
| **`C`** | Run **Dry-Run Check** preview (inspects changes without modifying system state) |
| **`A`** | Run **System Diagnostic Audit** (100% read-only diagnostic scanner) |
| **`S`** | Save current checkbox selection to `config.json` as permanent default |
| **`O`** | Run onboarding wizard (scans for standalone apps and suggests exclusions) |
| **`I`** | Reinstall Start Menu shortcut |
| **`Q`** | Exit without making any changes |

---

## ⚡ CLI & Headless Automation

FreeWinly works seamlessly from PowerShell scripts, CI pipelines, and terminal shortcuts:

```powershell
# Interactive mode (unelevated start, 10s countdown, TUI menu)
.\freewinly.ps1

# Dry-run preview mode (checks pending updates, temp sizes, and SSD TRIM without changing anything)
.\freewinly.ps1 -Check

# Headless run of default enabled modules (JIT elevates only if admin tasks are queued)
.\freewinly.ps1 -Run

# 100% read-only hardware, process, and event log diagnostic audit
.\freewinly.ps1 -Audit

# Run with a custom config JSON file
.\freewinly.ps1 -ConfigPath "custom-profile.json" -Run

# Run specific modules by name
.\freewinly.ps1 -Modules 05_hardware_health,10_software_updates -Run

# Show help
.\freewinly.ps1 -HelpMe
```

---

## 🧩 Modular Architecture

Every maintenance routine lives in [`modules/`](modules/) as an independent script conforming to a simple native parameter contract (`Info`, `Check`, `Run`):

```text
FreeWinly/
├── freewinly.ps1                <-- Master runner (CLI + TUI + JIT elevation + -ConfigPath)
├── freewinly.cmd                <-- Double-clickable launcher
├── install-shortcut.ps1         <-- Start Menu shortcut generator
├── config.json                  <-- Exclusions, enabled modules & drive settings
├── SKILL.md                     <-- AI Agent Playbook
└── modules/
    ├── 05_hardware_health.ps1   <-- Device Manager & driver faults with actionable advice
    ├── 06_event_log_health.ps1  <-- Recurring crashes & BSODs with plain-language fixes
    ├── 10_software_updates.ps1  <-- Winget updates
    ├── 20_cache_cleanup.ps1     <-- Temp & cache cleaning (> 7 days)
    ├── 30_ssd_trim.ps1          <-- Multi-SSD TRIM optimization
    ├── 35_hdd_defrag.ps1        <-- Mechanical HDD Defragmentation (auto-skips on SSD-only PCs)
    └── 40_windows_updates.ps1   <-- Windows Update COM API
```

### Module Contract (`Info / Check / Run`)

Each module can be executed directly as a standalone CLI tool:

```powershell
.\modules\30_ssd_trim.ps1 -Action Info
.\modules\30_ssd_trim.ps1 -Action Check
.\modules\30_ssd_trim.ps1 -Action Run -Options @{ Drives = @('C', 'D') }
```

### Adding Your Own Module
Create `modules/25_my_task.ps1`:
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
        Description   = "Describe your task here"
        Default       = $true
        RequiresAdmin = $false
        Options       = @{}
    }
}

if ($Action -eq 'Check') {
    Write-Host "Dry run preview: would perform my task." -ForegroundColor Yellow
    return
}

Write-Host "Executing custom task..." -ForegroundColor Green
```
FreeWinly will automatically discover it, query its metadata, add it to the menu, and handle execution/checks in numerical order!

---

## 🔒 Configuration & Exclusions (`config.json`)

FreeWinly stores rules in a human-readable `config.json`:

```json
{
  "excluded": [
    "Blizzard.BattleNet",
    "EpicGames.EpicGamesLauncher"
  ],
  "enabledModules": [
    "10_software_updates",
    "20_cache_cleanup",
    "30_ssd_trim"
  ],
  "cleanupTempMinAgeDays": 7
}
```

* **Excluding Self-Updating Launchers:** Add app IDs or names to `excluded` so Winget skips them.
* **Temporary Postponements:** Want to postpone an update for a week?  
  `{ "id": "Audacity.Audacity", "until": "2026-10-28", "reason": "Active project" }`  
  When the date expires, FreeWinly automatically removes the exclusion!

---

## 🛡️ Privacy & Zero Telemetry Pledge

* **0% Analytics:** FreeWinly sends zero telemetry, collects zero metrics, and makes zero phone-home calls.
* **100% Transparent:** Everything is open-source PowerShell that you can read, audit, and modify in seconds.

---

## 🤝 Contributing

Contributions, bug reports, and new modules are welcome! Feel free to open an issue or submit a pull request on GitHub.

---

## 📄 License

Distributed under the [MIT License](LICENSE).
