# FreeWinly

> Keep Windows fast, clean, and up to date without bloatware, background services, or subscriptions.  
> *A transparent, modular, native Windows maintenance engine.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows 11](https://img.shields.io/badge/Platform-Windows%2011-0078D6.svg)]()
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

## Why I Built This

I don't want to spend time managing my PC; I just want to use it.

Windows already has solid built-in tools for almost everything (official package management via Winget, native SSD TRIM, and system health logs). Yet traditional cleaner utilities wrap these basic functions in paid subscriptions, background tray icons, and upgrade notifications.

I built FreeWinly for three simple reasons:

1. **Use standard Windows tools:** No third-party background services, no registry clutter (all settings stay in local JSON), and no subscription fees.
2. **Turn Windows error noise into clear actions:** Instead of digging through cryptic Device Manager error codes or thousands of Event Viewer logs, the script filters out the noise, spots actual problems (like crashing apps or missing drivers), and tells you what to do.
3. **Make diagnostics easy for AI assistants:** Asking an AI to read raw event logs or run exploratory commands wastes tokens and fills up context quickly. FreeWinly runs the checks locally and produces a short, structured summary, so your AI assistant can spot issues and suggest fixes immediately.

If you just want your PC clean, fast, and updated:
1. Download **`FreeWinly.zip`** from [Releases](https://github.com/LycosLane/freewinly/releases) and extract it.
2. Double-click **`freewinly.cmd`**.

It will check your system health, update your programs, clean old temp files, and optimize your drives.

---

## Comparison: Traditional Cleaners vs. FreeWinly

| Feature | Traditional Tools (e.g. CCleaner) | FreeWinly |
| :--- | :--- | :--- |
| **Price** | Free version displays upgrade prompts; Pro is \$30-\$50/year | **Free and Open Source forever** (no subscriptions) |
| **Software Updates** | Locked behind paid/Pro paywall | **Included free** (updates apps via official Microsoft Winget) |
| **Notifications and Ads** | Sits in your system tray; shows popups | **No background processes, no tray icons, no ads** |
| **Unattended Execution** | Multi-step wizards and confirmation screens | **10-second countdown**: runs safe defaults automatically |
| **System Safety** | Blanket "registry cleaners" delete thousands of keys (which Microsoft advises against) | **Safe by design**: Never touches working registry entries, keeps settings in JSON, and only cleans verified dead launch pointers |
| **Storage Optimization** | May defragment modern SSDs, causing wear | **Hardware-aware**: sends TRIM to SSDs, defragments only HDDs |
| **Setup** | Requires installer and setup wizards | **No installation needed**: unzip and run |
| **Privacy** | Collects telemetry and analytics | **Fully offline and local**: sends no data anywhere |

---

## Features

Each feature is a self-contained script in `modules/` that can be run directly from PowerShell or automated through the FreeWinly runner.

- **Software Updates via Winget:** Uses Microsoft's official `winget` engine to update software silently, with version mismatch detection.
- **Auto-Start Countdown:** Counts down 10 seconds before running default tasks automatically. Press any key to open the interactive menu.
- **Expandable Tree-View Menu (`[+]` / `[-]`):** Pure 7-bit ASCII tree view. Toggle tasks with `[Space]`, expand/collapse per-module sub-options with `[Tab]` or `[Left/Right]`, adjust numeric sliders, cycle view modes with `[E]`, reorder with `[+]` / `[-]`, and run immediately with `[Enter]`.
- **Browser & App Cache Cleanup:** Purges disposable shader, code, and disk caches across Microsoft Edge, Chrome, Firefox, LibreWolf, Brave, Vivaldi, Opera, Discord, Teams, Slack, Spotify, Steam, and VS Code. Strictly preserves cookies, logins, and sessions; automatically skips running applications.
- **Network Cache & Connectivity Diagnostics:** Tests active adapters, default gateway reachability, and DNS resolution latency. Flushes the DNS resolver cache, purges stale ARP neighbor routes, and provides optional NetBIOS reload and Winsock reset.
- **Windows Component Store Cleanup (DISM):** Analyzes component store health and safely purges superseded Windows Update payloads from `C:\Windows\WinSxS` via native DISM, with optional `/ResetBase` and System File Checker (`sfc /verifyonly`) validation.
- **Hardware-Aware Storage Maintenance:** Executes native TRIM (`Optimize-Volume -ReTrim`) on NVMe/SATA SSDs. Defragments mechanical HDDs only. Expanding either module (`[-]`) reveals interactive per-drive `[x]` / `[ ]` checkboxes that directly manage `excludedDrives` in `config.json`, alongside cadence interval sliders.
- **Safe Cache and Temp Cleanup:** Clears user and system temp folders, WinGet download caches, and DirectX shader caches. Only removes files older than configured threshold (default: 7 days) to prevent application errors.
- **Hardware and Stability Diagnostics:** Scans Device Manager and Windows Event Logs for driver issues, recurring crashes, and unclean shutdowns, providing practical guidance for fixes.
- **App Launch Repair:** Detects and restores applications that fail to launch (with "Windows cannot find 'app.exe'") due to dead pointers left behind by uninstalled utilities. [Learn more](#deep-dive-app-launch-interceptions--sleep-tools)
- **Modular Architecture & CLI Auto-Complete:** Every core tool and maintenance task uses standardized `freewinly-<verb>-<noun>.ps1` names with optional User `PATH` registration (`[P]`) and strict AST/metadata validation. [Read the architecture deep dive](#modular-architecture)
- **AI-Ready:** Includes a `SKILL.md` playbook allowing AI assistants (such as Antigravity, Claude Code, or Cursor) to run health audits in a single step with minimal token usage.

---

## Getting Started

### Option 1: Direct Download (Recommended for most users)

1. Go to **[Releases](https://github.com/LycosLane/freewinly/releases)** and download **`FreeWinly.zip`**.
2. Right-click the `.zip`, click **Extract All**, and double-click **`freewinly.cmd`**.

A console window opens with a countdown:
* **Wait 10 seconds:** Runs safe maintenance automatically and exits when done.
* **Press any key:** Customize which tasks run, reorder modules with **`[ + ]`** / **`[ - ]`**, or press **`[ I ]`** to add a shortcut to your Windows Start Menu.

---

### Option 2: AI Assistant Prompt

If you use an AI coding assistant on Windows, paste this prompt into your assistant's chat:

```text
Download and extract https://github.com/LycosLane/freewinly/releases/latest/download/FreeWinly4LLM.zip into a subfolder, read its SKILL.md, and learn the skill. Whenever I ask you to check, maintain, update, or optimize my PC, use FreeWinly.
```

Your assistant will download and extract the tested release package, read the diagnostic output, configure exclusions in `config.json`, and set up the Start Menu shortcut.

---

### Option 3: AI Skill Bundle (`FreeWinly4LLM.zip`)

Download **`FreeWinly4LLM.zip`** from [Releases](https://github.com/LycosLane/freewinly/releases) and extract it into your assistant's `skills/` or `tools/` folder. It includes both the PowerShell engine and the complete `SKILL.md` playbook.

---

## Interactive Controls

```text
============================================================
         FreeWinly v1.5.0 - Open Source Windows Engine      
        Freeing Windows from bloatware, caches & fees       
============================================================
Use [Up/Down] to navigate, [Space] to toggle, [Tab/Arrows] for sub-options, [+/-] to reorder:

  [x]     Hardware & Driver Health
  [x] [-] System Stability & Event Logs (Last 7d)
            < 7d > Number of days back to scan Windows Event Logs
  [x]     App Launch Repair (Sleep Hooks)
  [x]     Software Updates (Winget)
  [ ]     Windows OS & Security Updates [Admin]
  [x] [+] Safe Cache & Temp Cleanup (>7 days)
  [x] [-] Browser Cache Cleanup
            < 3d > Minimum file age in days before purging cache files
            [x] Microsoft Edge disk & shader caches (skips if open)
            [x] Google Chrome disk & shader caches (skips if open)
            [x] Mozilla Firefox & LibreWolf disk cache (skips if open)
            [x] Brave, Vivaldi & Opera Chromium caches (skips if open)
  [x] [-] Desktop App Cache Cleanup
            < 3d > Minimum file age in days before purging cache files
            [x] Discord cache (skips if open)
            [x] Microsoft Teams cache (skips if open)
            [x] Slack cache (skips if open)
            [x] Steam web & HTML cache (skips if open)
            [x] Visual Studio Code cache (skips if open)
            [ + Add new app... ]
  [x] [+] Network Cache & Connectivity
  [ ] [+] Windows Component Store Cleanup (DISM) [Admin]
  [x] [-] SSD TRIM Optimization [Admin]
            < 0d > Minimum days between SSD TRIM runs (0 = every run)
            [x] Optimize Drive C: (OS - WD_BLACK SN770M 2TB, 1833.7 GB)

------------------------------------------------------------
> [ Enter ]  Run All Checked Tasks [x]
  [   C   ]  Dry-Run Check / Diagnostic Audit (No changes)
  [   E   ]  Sub-Options View: [ Custom ] (Press E: Hidden, Custom, Expanded)
  [   T   ]  Auto-Start Countdown: [ 10s ] (Press T to cycle)
  [   W   ]  Task Scheduler: [ Weekly on Sunday at 12:00 ] (Press W to configure)
  [   P   ]  User PATH CLI Auto-Complete: [ Disabled ] (Press P to toggle)
  [   S   ]  Save Selection & Order as Default
  [   O   ]  Run Configuration & Exclusion Wizard
  [   I   ]  Install / Update Start Menu Launcher
  [   U   ]  Uninstall FreeWinly Completely
  [   Q   ]  Quit Without Running
```

| Key | Action |
| :--- | :--- |
| **`Up` / `Down`** | Navigate between modules, editable sub-options, and action items |
| **`Space`** | Toggle module / boolean sub-option `[x]` / `[ ]`, cycle integer slider preset, or execute selected action |
| **`Tab`** | Expand or collapse sub-options `[+]` / `[-]` for the highlighted module |
| **`Left` / `Right`** | Collapse / expand module tree, toggle sub-option, or step integer sliders down / up |
| **`+` / `-`** | Move highlighted module up or down in the execution pipeline order |
| **`Delete` / `Back`** | Remove highlighted custom application cache entry (prompts for confirmation; built-ins can only be toggled) |
| **`Enter`** | Run all currently checked modules (prompts for UAC only if admin tasks are selected) |
| **`C` / `A`** | Run **Dry-Run Check / Diagnostic Audit** (inspects hardware, logs, updates, caches without modifying system) |
| **`E`** | Cycle **Sub-Options View Mode** (`Hidden` -> `Custom` -> `Expanded`) |
| **`T`** | Cycle **Auto-Start Countdown** duration (`0s Instant`, `3s`, `5s`, `10s Default`, `20s`, `30s`) |
| **`W`** | Open **Windows Task Scheduler** panel (press `D` to cycle weekdays, `+`/`-` to adjust hours, `Enter` to save) |
| **`P`** | Toggle **User `PATH` CLI Auto-Complete** (registers FreeWinly in your user `PATH` without needing Admin rights) |
| **`S`** | Save current module selection, order, sub-options, and view mode to `config.json` as permanent defaults |
| **`O`** | Run configuration & exclusion wizard (scans for standalone apps and suggests exclusions) |
| **`I`** | Install or update Start Menu launcher (`FreeWinly.lnk`) |
| **`U`** | Complete **Uninstaller** (previews and cleanly removes Task Scheduler tasks, all shortcuts, and User `PATH` integrations) |
| **`Q`** | Exit without making any changes |

---

## Scheduled Maintenance

FreeWinly can run on a schedule using Windows Task Scheduler. It runs only when scheduled and leaves no background services or system tray icons running.

Inside the interactive panel (or by pressing **`[ W ]`** in the main menu):
* Press **`D`** (or Space) to cycle through weekdays (`Sunday` -> `Monday` -> ...).
* Press **`+`** / **`-`** to adjust the scheduled hour.
* Press **`Enter`** (or **`S`**) to save the schedule to `config.json` and register or update the task in Windows Task Scheduler.
* Press **`R`** to delete the scheduled task from Windows.

You can also run the scheduler directly:
```powershell
# Interactive schedule panel
powershell -ExecutionPolicy Bypass -File .\core\freewinly-setup-schedule.ps1

# Or automate directly from CLI:
.\core\freewinly-setup-schedule.ps1 -Action Weekly -DayOfWeek Sunday -At 12:00
.\core\freewinly-setup-schedule.ps1 -Action Logon
.\core\freewinly-setup-schedule.ps1 -Action Remove
```

---

## Uninstallation & Artifact Cleanup

FreeWinly leaves no background services or persistent system modifications behind. You can cleanly remove all Windows integrations, shortcuts, and scheduled tasks anytime using the uninstaller:

```powershell
powershell -ExecutionPolicy Bypass -File .\core\freewinly-uninstall.ps1
```
* Or press **`[ U ]`** directly inside the FreeWinly interactive menu.

**What it does:**
1. Scans for and displays all active Windows system artifacts:
   - Windows Task Scheduler job (`FreeWinly`)
   - Shortcuts across Start Menu, Desktop, and Windows Startup folder (`shell:startup`)
   - User `PATH` CLI environment registration
2. Asks for explicit confirmation: `Remove all FreeWinly Windows integrations, shortcuts, and scheduled tasks? (y/N)`
3. Cleanly unregisters the scheduled task, removes all shortcuts, and removes User `PATH` entries.
4. **Protects your files:** The FreeWinly script folder itself is left intact, preventing accidental deletion of Git repositories, working trees, or local files. You can safely delete or archive the folder at your convenience.

---

## Command-Line Usage

FreeWinly can be run directly from PowerShell scripts, CI workflows, or custom shortcuts. If you toggle **`[ P ]`** in the menu (or run `.\core\freewinly-setup-path.ps1 -Action Add`), you can type `freewinly-` and press `Tab` from any terminal to auto-complete any tool or module:

```powershell
# Interactive mode (unelevated start, 10s countdown, menu)
.\freewinly.ps1

# Dry-run preview mode (checks pending updates, temp sizes, and SSD TRIM without changing anything)
.\freewinly.ps1 -Check

# Headless run of default enabled modules (prompts for UAC only if admin tasks are queued)
.\freewinly.ps1 -Run

# Read-only hardware, process, and event log diagnostic audit
.\freewinly.ps1 -Audit

# Run with a custom config JSON file
.\freewinly.ps1 -ConfigPath "custom-profile.json" -Run

# Run specific modules by name
.\freewinly.ps1 -Modules freewinly-check-hardware,freewinly-update-software -Run

# Show help
.\freewinly.ps1 -Help
```

---

## Modular Architecture

Every maintenance routine lives in [`modules/`](modules/) as an independent script conforming to a standardized `<prefix>-<verb>-<noun>.ps1` naming convention and parameter contract (`Info`, `Check`, `Run`).

Execution order is controlled via `modulesExecutionOrder` in `config.json` (and can be reordered live in the TUI with `[+]` / `[-]`), following a logical cause-and-effect sequence by default:
1. **Diagnostics & System Integrity (`Order 10–19`):** Checks baseline hardware health, scans recent crash event logs, and repairs broken application launch hooks before attempting updates.
2. **Software & OS Updates (`Order 20–29`):** Updates user applications via Winget and applies pending Windows OS/Defender definitions.
3. **Storage & Disk Maintenance (`Order 30–39`):** Purges expired caches and temp files, immediately followed by physical SSD TRIM and HDD defragmentation on the newly freed disk sectors.

```text
FreeWinly/
├── freewinly.ps1                        <-- Master runner (CLI + high-level orchestrator + JIT elevation)
├── freewinly.cmd                        <-- Double-clickable launcher
├── config.json                          <-- Execution order & per-module scoped settings
├── config.previous.json                 <-- Rolling backup created on configuration modification
├── config.last-good.json                <-- Verified configuration preserved after successful runs
├── SKILL.md                             <-- AI Agent Playbook
├── core/
│   ├── freewinly-config-io.ps1          <-- Atomic config writer, rolling backup manager & recovery
│   ├── freewinly-discovery.ps1          <-- AST contract gatekeeper, module discovery & sub-options builder
│   ├── freewinly-tui.ps1                <-- Interactive ASCII tree-view menu, countdown & key dispatcher
│   ├── freewinly-add-app.ps1            <-- Custom app cache manager (add/remove with safety checks)
│   ├── freewinly-init-config.ps1        <-- First-run setup & exclusion wizard
│   ├── freewinly-setup-schedule.ps1     <-- Windows Task Scheduler automation
│   ├── freewinly-setup-launcher.ps1     <-- Start Menu launcher manager
│   ├── freewinly-setup-path.ps1         <-- User PATH CLI auto-complete manager
│   └── freewinly-uninstall.ps1          <-- Uninstaller with preview & confirmation
└── modules/
    ├── freewinly-check-hardware.ps1     <-- Device Manager & driver faults with actionable advice (Order 10)
    ├── freewinly-check-eventlog.ps1     <-- Recurring crashes & BSODs with plain-language fixes (Order 11)
    ├── freewinly-repair-applaunch.ps1   <-- Restores apps broken by dead sleep hooks & debuggers (Order 12)
    ├── freewinly-update-software.ps1    <-- Winget updates with per-app exclusions & postponements (Order 20)
    ├── freewinly-update-windows.ps1     <-- Windows Update COM API (Order 21)
    ├── freewinly-clean-cache.ps1        <-- Safe temp/cache cleaning (> 7 days) (Order 30)
    ├── freewinly-clean-browsers.ps1     <-- Disposable browser cache cleanup (Edge, Chrome, Firefox, Brave) (Order 31)
    ├── freewinly-clean-apps.ps1         <-- Desktop app cache cleanup (Discord, Teams, Slack, Steam, VS Code, custom) (Order 32)
    ├── freewinly-clean-network.ps1      <-- Network cache flush & latency diagnostics (Order 33)
    ├── freewinly-clean-winsxs.ps1       <-- Windows Component Store DISM cleanup & SFC verification (Order 34)
    ├── freewinly-trim-ssd.ps1           <-- Multi-SSD TRIM optimization (Order 35)
    └── freewinly-defrag-hdd.ps1         <-- Mechanical HDD Defragmentation (auto-skips on SSD-only PCs) (Order 36)
```

### Module Contract (`Info / Check / Run`) & AST Gatekeeper

Each module works both as a standalone CLI tool (using its own built-in `DefaultSettings`) and as an orchestrated module inside `freewinly.ps1` (which overlays the module's block from `config.json` and passes it via `-Settings`):

```powershell
# Standalone execution with custom options
.\modules\freewinly-trim-ssd.ps1 -Action Info
.\modules\freewinly-trim-ssd.ps1 -Action Check
.\modules\freewinly-trim-ssd.ps1 -Action Run -Settings @{ excludedDrives = @('D'); minIntervalDays = 30 }

# Targeted event log & crash debugging over custom timeframes:
.\modules\freewinly-check-eventlog.ps1 -Days 14
.\modules\freewinly-check-eventlog.ps1 -StartDate "2026-10-18"                        # Inspects from start date until today
.\modules\freewinly-check-eventlog.ps1 -StartDate "2026-10-17" -EndDate "2026-10-19" # Exact window (e.g. debugging last weekend)
```

Before loading any `.ps1` file in `modules/`, FreeWinly runs a static **AST & Metadata Gatekeeper (`Test-ModuleContract`)**:
- Verifies zero PowerShell syntax errors via `[System.Management.Automation.Language.Parser]::ParseFile` before executing a single line.
- Verifies `-Action Info` returns a valid `Name` (3–50 characters, single-line so TUI borders never break), `Description` ($\le 120$ chars), and boolean `Default` / `RequiresAdmin`.
- If a script fails validation, FreeWinly safely skips it and displays `[Module Ignored] '<file>' was not loaded: <Reason>`.
- Brand-new valid modules dropped into `modules/` when `config.json` already exists are automatically appended and default to **disabled (`[ ]`)** until explicitly enabled by the user.

### Adding Your Own Module

Create `modules/freewinly-clean-custom.ps1`:
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
        Name            = "My Custom Cleanup"
        Description     = "Describe your task here (max 120 chars)"
        Order           = 35
        Default         = $false
        RequiresAdmin   = $false
        DefaultSettings = [ordered]@{
            maxDays = 14
        }
    }
}

$maxDays = if ($Settings -and $null -ne $Settings.maxDays) { [int]$Settings.maxDays } else { 14 }

if ($Action -eq 'Check') {
    Write-Host "Dry run preview: would clean items older than $maxDays days." -ForegroundColor Yellow
    return
}

Write-Host "Executing custom task (maxDays=$maxDays)..." -ForegroundColor Green
```

---

## Deep Dive: App Launch Interceptions & Sleep Tools

Windows includes a feature called *Image File Execution Options (IFEO)*. Originally intended for developers to attach debuggers, some PC optimization tools (such as CCleaner, Avast Cleanup, or AVG TuneUp) use it for "Sleep Mode / Performance Optimizer" to intercept an application when you click it and wake up background services before launching.

**What happens if the tool is uninstalled?**  
If a cleanup utility is uninstalled while applications are in sleep mode, the registry pointer remains behind pointing to a helper file that no longer exists on disk.
When you try to start Steam, Epic Games, Zoom, OneDrive, or any affected app, Windows looks for the missing helper and displays the misleading error:
> `Windows cannot find 'C:\...\app.exe'. Make sure you've typed the name correctly, then try again.`

**How FreeWinly safely handles this:**
* **Active tools are ignored:** If an interceptor file exists on your drive (e.g. you still actively use CCleaner or Process Explorer), FreeWinly reports it as an informational note and leaves it completely untouched. You can run FreeWinly alongside any tools you choose.
* **Broken pointers are repaired:** FreeWinly only acts when the target helper file no longer exists on disk. It safely deletes the dead pointer, immediately restoring direct launching without touching your files or shortcuts.
* **Migration tip:** If you plan to uninstall CCleaner or similar tools, open their Performance Optimizer first and wake up all sleeping apps before uninstalling. If you already uninstalled it, FreeWinly's module `freewinly-repair-applaunch` fixes it in one click.

---

## Configuration and Exclusions

FreeWinly stores global settings and per-module scoped settings in `config.json`. The top-to-bottom key order inside `modulesExecutionOrder` defines the exact sequence in which modules are displayed and executed:

```json
{
  "countdownSeconds": 10,
  "scheduleType": "Disabled",
  "scheduleDay": "Sunday",
  "scheduleTime": "12:00",
  "modulesExecutionOrder": {
    "freewinly-check-hardware": {
      "enabled": true
    },
    "freewinly-check-eventlog": {
      "enabled": true,
      "lookbackDays": 7
    },
    "freewinly-repair-applaunch": {
      "enabled": true
    },
    "freewinly-update-software": {
      "enabled": true,
      "excluded": [
        "Blizzard.BattleNet",
        "EpicGames.EpicGamesLauncher"
      ]
    },
    "freewinly-update-windows": {
      "enabled": false
    },
    "freewinly-clean-cache": {
      "enabled": true,
      "minAgeDays": 7,
      "cleanRecycleBin": false
    },
    "freewinly-clean-browsers": {
      "enabled": true,
      "minAgeDays": 3,
      "cleanEdge": true,
      "cleanChrome": true,
      "cleanFirefox": true,
      "cleanBrave": true
    },
    "freewinly-clean-apps": {
      "enabled": true,
      "minAgeDays": 3,
      "discord": true,
      "teams": true,
      "slack": true,
      "steam": true,
      "vscode": true,
      "customApps": {}
    },
    "freewinly-clean-network": {
      "enabled": true,
      "flushDns": true,
      "clearArpCache": true,
      "checkConnectivity": true,
      "clearNetBios": false,
      "resetWinsock": false
    },
    "freewinly-clean-winsxs": {
      "enabled": false,
      "verifySystemFiles": false,
      "resetBase": false
    },
    "freewinly-trim-ssd": {
      "enabled": true,
      "excludedDrives": [
        "D"
      ],
      "minIntervalDays": 30,
      "lastRun": null
    },
    "freewinly-defrag-hdd": {
      "enabled": true,
      "excludedDrives": [],
      "minIntervalDays": 30,
      "lastRun": null
    }
  }
}
```

* **Desktop Application Cache Cleaner (`freewinly-clean-apps`):** Data-driven cleanup for application caches. Built-in definitions (Discord, Teams, Slack, Steam web cache, and VS Code) live in module code so future updates apply automatically without config bloat. `config.json` stores only your enable toggles and custom apps.
* **Adding & Removing Custom Apps:** Add custom applications via the interactive TUI menu (`[ + Add new app... ]`) or via CLI:
  ```powershell
  # Add a custom application cache with running process detection
  .\core\freewinly-add-app.ps1 -Name "Spotify" -Process "Spotify" -Path "%LOCALAPPDATA%/Spotify/Data"

  # Remove a custom application
  .\core\freewinly-add-app.ps1 -Remove "Spotify"
  ```
  *(Note: Forward slashes `/` and backslashes `\` are normalized automatically. Paths must reside under `%APPDATA%`, `%LOCALAPPDATA%`, or `%TEMP%` at least two segments below base).*
* **Configuration Safety, Atomic Writes & Backups:**  
  - **Atomic writes:** Every configuration save writes to a temporary file before atomically replacing `config.json`.
  - **`config.previous.json`:** A rolling copy of your prior configuration is preserved whenever content changes.
  - **`config.last-good.json`:** A verified snapshot is saved after runs that finish without unhandled errors.
  - **Syntax corruption recovery:** Corrupted JSON files are never overwritten or deleted. In interactive mode, FreeWinly displays the error and offers `[R]` to restore from backup; in automated runs, it runs safely in memory using the last good configuration.
* **Per-Drive Storage Controls (`excludedDrives` & `minIntervalDays`):** Exclude specific drive letters (e.g. `"D"`) from SSD TRIM or HDD Defrag, or set `minIntervalDays` (e.g. `30` for monthly TRIM) so FreeWinly automatically records `lastRun` and skips the drive until the interval elapses.
* **Excluding Self-Updating Launchers:** Add app IDs or names to `modulesExecutionOrder.freewinly-update-software.excluded` so Winget skips them.
* **Temporary Postponements:**  
  To postpone an update while working on an important project, you can add an entry with an expiration date:  
  ```json
  { "id": "Audacity.Audacity", "until": "2026-10-29", "reason": "Active project deadline" }
  ```  
  If using an AI assistant, you can simply say:  
  > *"Don't update Blender or Audacity for the next week, I'm working on a deadline."*  
  
  Your AI assistant will calculate the date and add the entry to `config.json`. FreeWinly skips the app during updates and automatically removes the postponement once the date passes.

---

## Privacy

* **No telemetry:** FreeWinly sends no network requests, collects no analytics, and makes no external calls.
* **Local logs only:** Run logs and diagnostic records are saved strictly to your local `logs/` folder for your own inspection, never sent anywhere, and completely removed if you uninstall.
* **Transparent:** Open-source PowerShell scripts that you can read, audit, and modify.

---

## Contributing

Contributions, bug reports, and new modules are welcome. Feel free to open an issue or submit a pull request on GitHub.

---

## License

Distributed under the [MIT License](LICENSE).
