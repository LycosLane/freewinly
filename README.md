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
~^~^~^~^~^~^~^~^~^~^~^~^~ Pure, bloatware-free Windows maintenance.
```

---

## 💡 In Plain English: What FreeWinly Does

> **If you don't care about technical details and just want your PC fast, clean, and up-to-date:**  
> Download **`FreeWinly.zip`**, double-click **`freewinly.cmd`**, and walk away.  
> FreeWinly automatically checks your hardware, updates your programs, purges old junk files, and tunes your storage using official Windows tools. It won't break your system, it has zero ads, and it is 100% free forever.

---

## ⚖️ Comparison: Traditional "PC Cleaners" (like CCleaner) vs. FreeWinly

| Feature | Traditional Tools (e.g. CCleaner) | FreeWinly |
| :--- | :--- | :--- |
| **Price** | Free version nags you; Pro costs \$30–\$50/year | **100% Free & Open Source forever** (no subscriptions) |
| **Updating Your Programs** | Locked behind paid/Pro paywall | **Included free** (updates apps via official Microsoft Winget) |
| **Annoying Popups & Ads** | Sits in your system tray; pops up "Your PC is slow!" | **Zero background processes, zero tray icons, zero ads** |
| **1-Click "Launch & Walk Away"** | Multi-step wizards and confirmation screens | **10-second countdown**: runs safe defaults & cleanly exits |
| **Safety (No Broken Windows)** | Cleans the registry (which Microsoft warns against) | **Zero registry hacking**; only deletes old temp files (>7 days) |
| **Storage Optimization** | May blindly defrag modern SSDs, wearing them out | **Hardware-aware**: sends TRIM to SSDs, defrags only HDDs |
| **Setup & Installation** | Requires installer, setup wizards, and desktop bloat | **No installation needed**: unzip and run anywhere |
| **Offline Privacy** | Collects telemetry, analytics, and usage data | **100% offline & local**: sends zero data anywhere |

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

## 🚀 Quick Start (No Git or Technical Skills Needed)

### 1. Download and Run
1. Go to **[Releases](https://github.com/LycosLane/FreeWinly/releases)** and download **`FreeWinly.zip`**.
2. Right-click the `.zip`, choose **Extract All**, and double-click **`freewinly.cmd`**.

A clean window will open with a 10-second countdown:
* **Do nothing:** It runs safe maintenance automatically and quietly closes when finished.
* **Press any key:** Opens the interactive menu to customize tasks or press **`[ I ]`** to add a permanent shortcut directly into your Windows Start Menu!

### 2. Launch Anytime from Start Menu
Once installed, whenever your computer needs a tune-up:
1. Press the **Windows Key**.
2. Type **`FreeWinly`** and hit **Enter**.

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
