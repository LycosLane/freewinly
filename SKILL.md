---
name: freewinly
description: FreeWinly v1.5.3 - Open source, bloatware-free Windows PC maintenance & diagnostic engine using native Windows tools (Winget, PowerShell 5.1+, COM APIs, DISM, and TRIM). Use whenever the user asks to check, maintain, update, audit, or clean their PC.
---

# FreeWinly - Open Source Windows Maintenance & AI Agent Playbook

FreeWinly is a native Windows maintenance engine built without third-party dependencies. It operates in two modes:
1. **Human Mode:** Pure standalone PowerShell/TUI with zero AI dependencies (ideal for family PCs, offline environments, and purists).
2. **AI Harness Mode:** Pairs with AI assistants (Antigravity, Claude Code, Cursor) as a token-efficient diagnostic and configuration toolbelt.

---

## Repository Architecture

### Core Runners & State Files
| File / Directory | Description |
| :--- | :--- |
| `freewinly.ps1` | Master runner (CLI + high-level orchestrator + JIT elevation) |
| `freewinly.cmd` | Double-clickable batch launcher (%* arguments) |
| `VERSION` | Single Source of Truth canonical version file |
| `config.json` | Execution order, per-module settings, generic hooks |
| `config.previous.json` | Rolling backup created on configuration modification |
| `config.last-good.json` | Verified configuration preserved after successful runs |
| `BRANDING.md` | Brand guidelines and Fluke Fedora specifications |
| `SKILL.md` | AI Agent Playbook |

### Core Toolchain (`core/`)
| Script | Role |
| :--- | :--- |
| `core/freewinly-version.ps1` | Central version provider and runtime loader |
| `core/freewinly-config-io.ps1` | Atomic config writer, rolling backup manager, and recovery |
| `core/freewinly-discovery.ps1` | AST contract gatekeeper, module discovery, and sub-options builder |
| `core/freewinly-tui.ps1` | Interactive ASCII tree-view menu, countdown, and key dispatcher |
| `core/freewinly-add-app.ps1` | Custom app cache manager (add/remove with safety checks) |
| `core/freewinly-init-config.ps1` | First-run setup and exclusion wizard |
| `core/freewinly-setup-schedule.ps1` | Native Windows Task Scheduler installer |
| `core/freewinly-setup-launcher.ps1` | Start Menu launcher manager (Install/Remove/Status) |
| `core/freewinly-setup-path.ps1` | User PATH CLI auto-complete manager |
| `core/freewinly-uninstall.ps1` | Complete uninstaller with preview and confirmation |

### Maintenance Modules (`modules/`)
| Module | Order | Purpose |
| :--- | :--- | :--- |
| `freewinly-check-hardware.ps1` | 10 | Device Manager and driver faults with actionable advice |
| `freewinly-check-eventlog.ps1` | 11 | Recurring crashes and BSODs with plain-language fixes |
| `freewinly-repair-applaunch.ps1` | 12 | Restores apps broken by dead sleep hooks and debuggers |
| `freewinly-update-software.ps1` | 20 | Winget updates (respects per-module exclusions) |
| `freewinly-update-windows.ps1` | 21 | Native Windows OS and Defender Updates |
| `freewinly-clean-cache.ps1` | 30 | Safe temp and cache cleaning (>7 days) |
| `freewinly-clean-browsers.ps1` | 31 | Disposable browser cache cleanup (Edge, Chrome, Firefox, Brave) |
| `freewinly-clean-apps.ps1` | 32 | Desktop app cache cleanup (Discord, Teams, Slack, Steam, VS Code, etc.) |
| `freewinly-clean-network.ps1` | 33 | Network cache flush and latency diagnostics |
| `freewinly-clean-winsxs.ps1` | 34 | Windows Component Store DISM cleanup and SFC verification |
| `freewinly-trim-ssd.ps1` | 35 | SSD NVMe TRIM ReTrim optimization |
| `freewinly-defrag-hdd.ps1` | 36 | Mechanical HDD Defrag (auto-skips on SSD-only PCs) |

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
* Expand or collapse sub-options for the highlighted module with **[Tab]**.
  - Expanding `SSD TRIM Optimization` or `Mechanical HDD Defragmentation` exposes interactive per-drive `[x]` / `[ ]` checkboxes that directly manage `excludedDrives` in `config.json`.
  - Expanding `Desktop App Cache Cleanup` displays built-in apps, custom configured apps, and the `[ + Add new app... ]` line.
* Fine-tune sub-options with **[Left/Right]** arrows (collapse/expand, toggle bools/drives, step integer slider presets).
* Reorder module execution sequence with **[+]** / **[-]** (`Move Up` / `Move Down`), keeping selection anchored.
* **[ Delete ] / [ Backspace ]** -> Remove the highlighted custom application cache (with confirmation prompt; built-in apps can only be toggled).
* **[ Enter ]** -> **Run All Checked Tasks [x]** (or activate selected action/sub-option).
* **[ C ] / [ A ]** -> **Dry-Run Check / Diagnostic Audit** (inspects pending updates, hardware errors, and cache savings without modifying system state).
* **[ V ]** -> **Toggle Output Mode** (`Standard` clean single-line status vs `Advanced` verbose stream).
* **[ E ]** -> **Cycle Sub-Options View Mode** (`Hidden` -> `Custom` -> `Expanded`).
* **[ T ]** -> **Cycle Auto-Start Countdown** (`0s`, `3s`, `5s`, `10s`, `20s`, `30s`).
* **[ W ]** -> **Schedule Maintenance in Windows Task Scheduler** (interactive panel with `D` weekday cycler and `+`/`-` hour adjustments).
* **[ P ]** -> **Toggle User `PATH` CLI Auto-Complete** (adds/removes FreeWinly in the current User's `PATH` without requiring Admin rights).
* **[ S ]** -> **Save Selection & Order as Default** (saves current checkboxes, execution order, sub-options, view mode, and timer to `config.json`).
* **[ O ]** -> **Run Configuration & Exclusion Wizard** (detects standalone/unknown packages).
* **[ I ]** -> **Install or Update Start Menu Launcher**.
* **[ U ]** -> **Artifact Cleaner & Uninstaller** (previews and cleanly removes Task Scheduler jobs, all shortcuts, and User `PATH` integrations; keeps scripts safe).
* **[ Q ]** -> **Quit Without Running**.

### 3. Desktop Application Cache Cleaner (`freewinly-clean-apps`)
* Generic data-driven cleaner for app caches. Ships built-in definitions for Discord, Microsoft Teams, Slack, Steam, VS Code, Obsidian, and Telegram.
* **Built-in definitions stay in code:** Built-in path and process rules live inside the module. `config.json` only stores boolean overrides (`discord: true`), preserving automatic updates for future built-ins without config bloat.
* **Strict path safety engine:** All paths (built-in and custom) must reside strictly under `%APPDATA%`, `%LOCALAPPDATA%`, or `%TEMP%`, at least 2 segments below base. Reparse points and symlinks are never traversed. Running apps are skipped safely. Forward slashes (`/`) and backward slashes (`\`) are normalized transparently.
* **Custom App Management via CLI:**
  ```powershell
  # Add custom app with process lock protection and cache path
  .\core\freewinly-add-app.ps1 -Name "Spotify" -Process "Spotify" -Path "%LOCALAPPDATA%/Spotify/Data" -MinAgeDays 7
  
  # Remove custom app from configuration
  .\core\freewinly-add-app.ps1 -Remove "Spotify"
  ```

### 4. Configuration Safety & Atomic Writes
* **Atomic Writes:** All writes to `config.json` write to a temporary file before atomic replacement.
* **`config.previous.json`:** A rolling copy of the previous configuration is saved before changes are applied.
* **`config.last-good.json`:** Verified configuration is preserved whenever a run completes without unhandled errors.
* **Corruption Safety:** If `config.json` contains syntax errors, FreeWinly never overwrites the file. Interactive sessions offer `[R]` to restore from backup; headless runs execute using the verified backup or defaults in memory.

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
  - `freewinly-clean-browsers`: `{ "enabled": true, "minAgeDays": 3, "cleanEdge": true, "cleanChrome": true, "cleanFirefox": true, "cleanBrave": true }`
  - `freewinly-clean-apps`: `{ "enabled": true, "minAgeDays": 3, "discord": true, "teams": true, "slack": true, "steam": true, "vscode": true, "obsidian": true, "telegram": true, "customApps": {} }`
  - `freewinly-clean-network`: `{ "enabled": true, "flushDns": true, "clearArpCache": true, "checkConnectivity": true, "clearNetBios": false, "resetWinsock": false }`
  - `freewinly-clean-winsxs`: `{ "enabled": false, "verifySystemFiles": false, "resetBase": false }`
  - `freewinly-trim-ssd`: `{ "enabled": true, "excludedDrives": [], "minIntervalDays": 0, "lastRun": null }`
  - `freewinly-defrag-hdd`: `{ "enabled": true, "excludedDrives": [], "minIntervalDays": 30, "lastRun": null }`

---

## Logs & Diagnostic File Locations

All runtime activities, errors, and verbose diagnostics are logged to deterministic file paths:

* **Daily Log Files (`logs/freewinly-YYYYMMDD.log`):**
  Contains timestamped logs of every module execution, exact winget download URLs, package hashes, license notices, DISM servicing reports, and PowerShell stack traces. In Standard output mode, all third-party verbose progress is redirected here to keep the console calm.
* **Active Configuration (`config.json`):**
  Defines user preferences, module order, enable/disable states, and per-module exclusion lists.
* **Rolling Backup (`config.previous.json`):**
  Automatically saved whenever settings are modified via CLI, TUI, or AI agent.
* **Verified Baseline (`config.last-good.json`):**
  Preserved only after a maintenance run finishes with zero unhandled module errors. Can be used to restore known-working states.

---

## Troubleshooting & Reporting GitHub Issues

When assisting a user who encounters a recurring failure, unexpected crash, or wants to report a bug on GitHub:

1. **GitHub Issues URL:**
   `https://github.com/LycosLane/freewinly/issues`

2. **Required Diagnostic Information Checklist:**
   Before filing an issue, collect the following environment facts:
   * **FreeWinly Version:** `Get-Content VERSION` (or from the console banner).
   * **Windows OS Version & Build:** Run `(Get-CimInstance Win32_OperatingSystem).Caption` and `(Get-CimInstance Win32_OperatingSystem).Version`.
   * **PowerShell Version:** `$PSVersionTable.PSVersion.ToString()`.
   * **Execution Context:** Was it executed via `freewinly.cmd` (Interactive TUI), elevated CLI (`.\freewinly.ps1 -Run`), read-only audit (`.\freewinly.ps1 -Check`), or Task Scheduler?
   * **Failing Module Name:** The module indicator where the issue occurred (e.g. `freewinly-update-software`).
   * **Relevant Log Excerpt:** The relevant error block from `logs/freewinly-YYYYMMDD.log`.

3. **Privacy & Anonymization Guidance:**
   Always advise the user to sanitize personal or sensitive details before posting publicly:
   * Replace actual username paths (`C:\Users\JohnDoe` -> `C:\Users\<username>`).
   * Remove internal corporate domain names, computer hostnames, or private IP addresses.
   * Remove custom application names if they reveal proprietary internal software.

4. **Standard Issue Report Template (Ready to Copy):**

```markdown
### Environment
- FreeWinly Version: 1.5.3
- Windows Version: Windows 11 Pro (Build 22631.xxxx)
- PowerShell Version: 5.1.22621.xxxx (or 7.x)
- Execution Mode: Interactive TUI / Headless CLI (-Run) / Audit (-Check)

### Problem Description
A clear and concise description of the issue encountered.

### Affected Module(s)
- [e.g. freewinly-update-software / freewinly-trim-ssd]

### Relevant Log Excerpt (`logs/freewinly-YYYYMMDD.log`)
```text
[2026-11-07 23:10:45] Module Error (freewinly-update-software): ...
```

### Steps to Reproduce
1. Run `.\freewinly.ps1 -Run`
2. Observe error at step [ 4/10 ]

### Expected Behavior
What should have happened instead.
```


