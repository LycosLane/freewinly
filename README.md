# 🐋 FreeWinly

> **Keep Windows fast, clean, and up-to-date—without bloatware, background services, or subscriptions.**  
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

## ⚖️ Comparison: Traditional Commercial Cleaners vs. FreeWinly

| Feature | Traditional Tools (e.g. CCleaner) | FreeWinly |
| :--- | :--- | :--- |
| **Price** | Free version displays upgrade prompts; Pro is \$30–\$50/yr | **100% Free & Open Source forever** (no subscriptions) |
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

## 🚀 3 Ways to Use FreeWinly

### Method 1: Direct Download (For Everyday Users & Non-Techies)
*No Git, coding skills, or technical setup needed:*
1. Go to **[Releases](https://github.com/LycosLane/FreeWinly/releases)** and download **`FreeWinly.zip`** (pure tool, zero AI files, ~29 KB).
2. Right-click the `.zip`, click **Extract All**, and double-click **`freewinly.cmd`**.

A clean window will open with a countdown:
* **Do nothing:** Runs safe maintenance automatically and quietly exits when done.
* **Press any key:** Customize which tasks run, or press **`[ I ]`** to add a permanent shortcut to your Windows Start Menu!

---

### Method 2: One-Prompt Setup for AI Assistants (Antigravity, Claude Code, Cursor)
If you already use an AI coding assistant on Windows, simply paste this prompt into your AI chat:

```text
Clone https://github.com/LycosLane/FreeWinly into a subfolder, read its SKILL.md, and learn the skill. Whenever I ask you to check, maintain, update, or optimize my PC, use FreeWinly.
```
Your AI will clone the repo, ingest the pre-digested diagnostics in 1 turn (~300 tokens), configure your exclusions in `config.json`, and set up your Start Menu shortcut!

---

### Method 3: AI Skill Bundle (`FreeWinly4LLM.zip`)
Download **`FreeWinly4LLM.zip`** from [Releases](https://github.com/LycosLane/FreeWinly/releases) and extract it directly into your AI assistant's `skills/` or `tools/` folder. It includes both the native PowerShell engine and the complete `SKILL.md` playbook.

---

## 🎛️ Interactive TUI Controls

```text
============================================================
           FreeWinly - Open Source Windows Engine           
        Freeing Windows from bloatware, caches & fees       
============================================================
Use [Up/Down] arrows to navigate, [Space] to toggle, [Enter] to run:

  [x] Hardware & Driver Health
  [x] System Stability & Event Logs (Last 7 days)
  [x] Software Updates (Winget)
  [x] Safe Cache & Temp Cleanup (>7 days)
  [x] SSD TRIM Optimization [Admin]
  [ ] Windows OS & Security Updates [Admin]

------------------------------------------------------------
> [ Enter ]  Run All Checked Tasks [x]
  [   C   ]  Dry-Run Check / Diagnostic Audit (No changes)
  [   T   ]  Auto-Start Countdown: [ 10s ] (Press T to cycle: 0s, 3s, 5s, 10s, 20s, 30s)
  [   W   ]  Schedule Maintenance in Windows Task Scheduler
  [   S   ]  Save Selection as Default
  [   O   ]  Run First-Time Onboarding Wizard
  [   I   ]  Install / Update Start Menu Shortcut
  [   U   ]  Uninstall FreeWinly Completely
  [   Q   ]  Quit Without Running
```

| Key | Action |
| :--- | :--- |
| **`Up` / `Down`** | Navigate between modules and actions |
| **`Space`** | Toggle module checkbox `[x]` / `[ ]` |
| **`Enter`** | Run all currently checked modules (triggers Just-in-Time UAC only if required) |
| **`C` / `A`** | Run **Dry-Run Check / Diagnostic Audit** (inspects hardware, logs, updates, and cache without modifying system) |
| **`T`** | Cycle **Auto-Start Countdown** duration (`0s Instant`, `3s`, `5s`, `10s Default`, `20s`, `30s`) |
| **`W`** | Open **Windows Task Scheduler** configurator (Weekly, Monthly, at Logon, or Remove) |
| **`S`** | Save current checkbox selection and timer to `config.json` as permanent defaults |
| **`O`** | Run onboarding wizard (scans for standalone apps and suggests exclusions) |
| **`I`** | Install or update Start Menu shortcut |
| **`U`** | Complete **Uninstaller** (previews and removes Task Scheduler tasks, shortcuts, and files) |
| **`Q`** | Exit without making any changes |

---

## ⏰ Background Scheduled Maintenance (Windows Task Scheduler)

FreeWinly can run completely automatically in the background using native Windows Task Scheduler. **Zero background services, zero system tray daemons, and zero battery drain.**

Run the task scheduler installer anytime:
```powershell
# Interactive schedule menu
powershell -ExecutionPolicy Bypass -File .\install-task.ps1

# Or automate directly from CLI:
.\install-task.ps1 -Action Weekly -DayOfWeek Sunday -At 12:00
.\install-task.ps1 -Action Logon
.\install-task.ps1 -Action Remove
```
* Or simply press **`[ W ]`** inside the FreeWinly interactive menu.

---

## 🗑️ Clean Uninstallation (`uninstall.ps1`)

FreeWinly respects your system and leaves zero digital debris behind. It includes a dedicated, safe uninstaller that previews every single component before removal:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```
* Or press **`[ U ]`** directly inside the FreeWinly TUI menu.

**What it does:**
1. Scans for and displays all active components:
   - Windows Task Scheduler job (`FreeWinly`)
   - Start Menu shortcut (`FreeWinly.lnk`)
   - Application folder (including local configs and logs)
2. Asks for explicit confirmation: `Are you sure you want to completely remove FreeWinly? (y/N)`
3. Cleanly unregisters the scheduled task, deletes the shortcut, and self-deletes the application directory via a detached background process. Zero residual registry keys or background files!

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
* **Temporary Postponements (Ideal for AI Assistants):**  
  Want to postpone an update for a few days or weeks while working on a critical project? You don't have to edit JSON manually—simply tell your AI:  
  > *"Hey, don't update Blender or Audacity for the next week, I'm in the middle of a project."*  
  
  Your AI assistant automatically calculates the date and stages the postponement in `config.json`:  
  ```json
  { "id": "Audacity.Audacity", "until": "2026-10-29", "reason": "Active project deadline" }
  ```  
  FreeWinly respects the deadline, skips the app during upgrades, and **automatically cleans up and removes the expired postponement** once the date passes. Zero manual maintenance required!

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
