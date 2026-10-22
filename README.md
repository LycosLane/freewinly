# FreeWinly

> Keep Windows fast, clean, and up to date without bloatware, background services, or subscriptions.  
> *A transparent, modular, native Windows maintenance engine.*

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
- **Interactive Console Menu:** Toggle tasks on or off with `[Space]`, run them immediately with `[Enter]`, or save your selection as default with `[S]`.
- **Hardware-Aware Storage Maintenance:** Executes native TRIM (`Optimize-Volume -ReTrim`) on NVMe/SATA SSDs. Defragments mechanical HDDs only.
- **Safe Cache and Temp Cleanup:** Clears user and system temp folders, WinGet download caches, and DirectX shader caches. Only removes files older than 7 days to prevent application errors.
- **Hardware and Stability Diagnostics:** Scans Device Manager and Windows Event Logs for driver issues, recurring crashes, and unclean shutdowns, providing practical guidance for fixes.
- **App Launch Repair:** Detects and restores applications that fail to launch (with "Windows cannot find 'app.exe'") due to dead pointers left behind by uninstalled utilities. [Learn more](#deep-dive-app-launch-interceptions--sleep-tools)
- **Modular Architecture:** Add or customize maintenance tasks by placing numbered `.ps1` files into the `modules/` folder. [Read the architecture deep dive](#modular-architecture)
- **AI-Ready:** Includes a `SKILL.md` playbook allowing AI assistants (such as Antigravity, Claude Code, or Cursor) to run health audits in a single step with minimal token usage.

---

## Getting Started

### Option 1: Direct Download (Recommended for most users)

1. Go to **[Releases](https://github.com/LycosLane/freewinly/releases)** and download **`FreeWinly.zip`**.
2. Right-click the `.zip`, click **Extract All**, and double-click **`freewinly.cmd`**.

A console window opens with a countdown:
* **Wait 10 seconds:** Runs safe maintenance automatically and exits when done.
* **Press any key:** Customize which tasks run, or press **`[ I ]`** to add a shortcut to your Windows Start Menu.

---

### Option 2: AI Assistant Prompt

If you use an AI coding assistant on Windows, paste this prompt into your assistant's chat:

```text
Clone https://github.com/LycosLane/freewinly into a subfolder, read its SKILL.md, and learn the skill. Whenever I ask you to check, maintain, update, or optimize my PC, use FreeWinly.
```

Your assistant will clone the repository, read the diagnostic output, configure exclusions in `config.json`, and set up the Start Menu shortcut.

---

### Option 3: AI Skill Bundle (`FreeWinly4LLM.zip`)

Download **`FreeWinly4LLM.zip`** from [Releases](https://github.com/LycosLane/freewinly/releases) and extract it into your assistant's `skills/` or `tools/` folder. It includes both the PowerShell engine and the complete `SKILL.md` playbook.

---

## Interactive Controls

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
  [   W   ]  Task Scheduler: [ Weekly on Sunday at 12:00 ] (Press W to configure)
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
| **`Enter`** | Run all currently checked modules (prompts for UAC only if admin tasks are selected) |
| **`C` / `A`** | Run **Dry-Run Check / Diagnostic Audit** (inspects hardware, logs, updates, and cache without modifying system) |
| **`T`** | Cycle **Auto-Start Countdown** duration (`0s Instant`, `3s`, `5s`, `10s Default`, `20s`, `30s`) |
| **`W`** | Open **Windows Task Scheduler** panel (press `D` to cycle weekdays, `+`/`-` to adjust hours, `Enter` to save) |
| **`S`** | Save current checkbox selection and timer to `config.json` as permanent defaults |
| **`O`** | Run onboarding wizard (scans for standalone apps and suggests exclusions) |
| **`I`** | Install or update Start Menu shortcut |
| **`U`** | Complete **Uninstaller** (previews and removes Task Scheduler tasks, shortcuts, and files) |
| **`Q`** | Exit without making any changes |

---

## Scheduled Maintenance

FreeWinly can run on a schedule using Windows Task Scheduler. It runs only when scheduled and leaves no background services or system tray icons running.

Inside the interactive panel (or by pressing **`[ W ]`** in the main menu):
* Press **`D`** (or Space) to cycle through weekdays (`Sunday` -> `Monday` -> ...).
* Press **`+`** / **`-`** to adjust the scheduled hour.
* Press **`Enter`** (or **`S`**) to save the schedule to `config.json` and register or update the task in Windows Task Scheduler.
* Press **`R`** to delete the scheduled task from Windows.

You can also run the installer directly:
```powershell
# Interactive schedule panel
powershell -ExecutionPolicy Bypass -File .\install-task.ps1

# Or automate directly from CLI:
.\install-task.ps1 -Action Weekly -DayOfWeek Sunday -At 12:00
.\install-task.ps1 -Action Logon
.\install-task.ps1 -Action Remove
```

---

## Uninstallation

FreeWinly leaves no background services, registry entries, or leftover files behind. You can remove it anytime using the uninstaller:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```
* Or press **`[ U ]`** directly inside the FreeWinly interactive menu.

**What it does:**
1. Scans for and displays all active components:
   - Windows Task Scheduler job (`FreeWinly`)
   - Start Menu shortcut (`FreeWinly.lnk`)
   - Application folder (including local configs and logs)
2. Asks for explicit confirmation: `Are you sure you want to completely remove FreeWinly? (y/N)`
3. Cleanly unregisters the scheduled task, deletes the shortcut, and removes the application directory via a detached background process.

---

## Command-Line Usage

FreeWinly can be run directly from PowerShell scripts, CI workflows, or custom shortcuts:

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
.\freewinly.ps1 -Modules 10_hardware_health,20_software_updates -Run

# Show help
.\freewinly.ps1 -HelpMe
```

---

## Modular Architecture

Every maintenance routine lives in [`modules/`](modules/) as an independent script conforming to a simple parameter contract (`Info`, `Check`, `Run`).

Modules are numbered by category (`1x`, `2x`, `3x`) and executed in a strict cause-and-effect sequence:
1. **`1x` - Diagnostics & System Integrity:** Checks baseline hardware health, scans recent crash event logs, and repairs broken application launch hooks before attempting updates.
2. **`2x` - Software & OS Updates:** Updates user applications via Winget and applies pending Windows OS/Defender definitions.
3. **`3x` - Storage & Disk Maintenance:** Purges expired caches and temp files, immediately followed by physical SSD TRIM and HDD defragmentation on the newly freed disk sectors.

```text
FreeWinly/
├── freewinly.ps1                <-- Master runner (CLI + TUI + JIT elevation + -ConfigPath)
├── freewinly.cmd                <-- Double-clickable launcher
├── install-shortcut.ps1         <-- Start Menu shortcut generator
├── install-task.ps1             <-- Task Scheduler automation
├── uninstall.ps1                <-- Uninstaller with confirmation
├── config.json                  <-- Exclusions, enabled modules & drive settings
├── SKILL.md                     <-- AI Agent Playbook
└── modules/
    ├── 10_hardware_health.ps1   <-- Device Manager & driver faults with actionable advice
    ├── 11_event_log_health.ps1  <-- Recurring crashes & BSODs with plain-language fixes
    ├── 12_app_launch_repair.ps1 <-- Restores apps broken by dead sleep hooks & debuggers
    ├── 20_software_updates.ps1  <-- Winget updates
    ├── 21_windows_updates.ps1   <-- Windows Update COM API
    ├── 30_cache_cleanup.ps1     <-- Temp & cache cleaning (> 7 days)
    ├── 31_ssd_trim.ps1          <-- Multi-SSD TRIM optimization
    └── 32_hdd_defrag.ps1        <-- Mechanical HDD Defragmentation (auto-skips on SSD-only PCs)
```

### Module Contract (`Info / Check / Run`)

Each module can be executed directly as a standalone CLI tool:

```powershell
.\modules\31_ssd_trim.ps1 -Action Info
.\modules\31_ssd_trim.ps1 -Action Check
.\modules\31_ssd_trim.ps1 -Action Run -Options @{ Drives = @('C', 'D') }
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
FreeWinly automatically discovers new modules, queries their metadata, adds them to the menu, and runs them in numerical order.

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
* **Migration tip:** If you plan to uninstall CCleaner or similar tools, open their Performance Optimizer first and wake up all sleeping apps before uninstalling. If you already uninstalled it, FreeWinly's Module `12_app_launch_repair` fixes it in one click.

---

## Configuration and Exclusions

FreeWinly stores settings in `config.json`:

```json
{
  "excluded": [
    "Blizzard.BattleNet",
    "EpicGames.EpicGamesLauncher"
  ],
  "enabledModules": [
    "20_software_updates",
    "30_cache_cleanup",
    "31_ssd_trim"
  ],
  "cleanupTempMinAgeDays": 7
}
```

* **Excluding Self-Updating Launchers:** Add app IDs or names to `excluded` so Winget skips them.
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
