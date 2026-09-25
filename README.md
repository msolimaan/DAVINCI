# DaVinci Cleaner

A native macOS cleaner and optimizer in the spirit of **CleanMyMac** by MacPaw. It's written in SwiftUI, free, open source and sends nothing over the network.

Each tool has its own colour theme: an animated gradient background, glass cards, a glowing round action button and progress rings. Every module follows the same steps: **welcome → scan → review → clean → done**.

| Module | What it does |
| --- | --- |
| ✨ **Smart Scan** | One button that finds junk, checks memory pressure, runs quick maintenance and spots clutter in Downloads. |
| 🗑 **System Junk** | User caches, app and system logs, Xcode DerivedData, device support and simulator caches, Homebrew/npm/Yarn/pnpm/pip/CocoaPods/Gradle/Cargo/Go caches, caches for Safari, Chrome, Firefox, Edge, Brave, Arc and Opera, Mail downloads and the Trash. |
| 📦 **Uninstaller** | Removes apps completely, including their files in `Application Support`, `Caches`, `Preferences`, `Containers`, `Group Containers`, `Saved Application State`, `LaunchAgents/Daemons`, `HTTPStorages`, `WebKit` and more. It can also find **leftovers** from apps you already dragged to the Trash. |
| 🔭 **Space Lens** | An interactive treemap of your disk. Click a folder to zoom in, select boxes and remove them in place. |
| 📄 **Large & Old Files** | Big and forgotten files, with filters for size, last use, type and folder. |
| 🧬 **Duplicates** | Identical files, compared by content (SHA-256). It keeps the oldest copy and never lets you select every copy. |
| ⚡ **Maintenance** | Free up RAM, flush DNS, run the periodic maintenance scripts, reindex Spotlight, thin Time Machine snapshots, repair the "Open With" menu, reset Quick Look, clear font caches, restart Finder and the Dock, verify the startup disk. macOS asks for your password **once** for all the tasks that need it. |
| ⏻ **Login Items** | Every launch agent and daemon, with switches to turn them off (and back on). |
| 📈 **System Monitor** | Live CPU, memory (the same breakdown as Activity Monitor) and disk usage, a 3‑minute history chart, and the processes using the most memory. |
| 🧭 **Menu bar** | A popover with CPU, memory and disk gauges plus *Free Up RAM* and *Empty Trash*. |

## Safety first

A cleaner has to be trustworthy, so safety is built into the core engine and doesn't depend on the UI:

- **Nothing is removed until you review it** and press the button.
- **`SafetyGuard` re-checks every item right before removal.** An item must sit *inside* the folder its scanner was responsible for. It is refused if it is:
  - in a macOS system location: `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var/db` and others
  - your home folder itself, or an essential folder such as `~/Documents` or `~/Library/Caches` (the things *inside* those folders can still be removed)
  - inside `~/.ssh`, `~/.gnupg`, your Keychains or Messages
- Path tricks (`..`) and symlinked folders can't escape the allowed folder.
- **Items go to the Trash by default.** "Delete Immediately" is a setting you have to turn on.
- Apple's built-in apps are never offered for uninstalling, and Xcode Archives (which hold your dSYMs) are never pre-selected.
- The app never asks for or sees your password. Tasks that need administrator rights use the standard macOS authentication dialog.

## Build and run

You need macOS 13 Ventura or later and Xcode 15 or later (or the Swift 5.9+ command-line tools).

```bash
git clone https://github.com/msolimaan/DAVINCI.git
cd DAVINCI

# Build a double-clickable app with its icon, in ./build
./scripts/build-app.sh
open "build/DaVinci Cleaner.app"
```

You can also open `Package.swift` in Xcode, choose the **DaVinciCleaner** scheme and press ⌘R. From the terminal, `swift run DaVinciCleaner` works too.

### Give it Full Disk Access

macOS hides Mail, Safari, the Trash and a few other folders until you allow it. Open **System Settings → Privacy & Security → Full Disk Access**, click **+**, and add *DaVinci Cleaner.app*. The app shows a banner while access is missing, and a button that opens the right settings page.

### Run the tests

```bash
swift test
```

The tests cover the safety guard (including path traversal and symlinks), every junk location in the catalog, removal, leftover matching for the uninstaller, the large-file and duplicate finders, the Space Lens treemap layout, and the maintenance, launchctl and `ps` parsers. All of them run against throwaway temporary folders and never touch your real files.

## How it's built

```
Sources/
  CleanerCore/            Foundation-only engine, unit tested
    Safety/               SafetyGuard: the last check before anything is removed
    Cleaners/             JunkCatalog (where junk lives) + JunkScanner
    Removal/              Remover: Trash or delete, with admin fallback
    Uninstaller/          AppInventory + LeftoverFinder
    Files/                LargeFileFinder, DuplicateFinder, SpaceAnalyzer, TreemapLayout
    Maintenance/          MaintenanceTask/Runner, LaunchItemStore, CommandRunner
    Monitor/              SystemStats (Mach host statistics, sysctl), CPUSampler
  DaVinciCleaner/         SwiftUI app
    Design/               Theme, palettes, glass components, intro/scan/done screens
    ViewModels/           One @MainActor view model per module
    Views/                Module screens, sidebar, menu bar popover, settings
Tests/CleanerCoreTests/   XCTest suite
scripts/                  build-app.sh, make-icon.swift
```

The app isn't sandboxed because a sandboxed app can't clean other apps' files. For the same reason it's distributed outside the Mac App Store, like most Mac cleaners.

## Inspiration

These open-source projects shaped the design (the code here is original):

- [tw93/Mole](https://github.com/tw93/Mole): a deep-clean list of cache locations
- [alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner): matching an app's leftovers by bundle ID
- [exelban/stats](https://github.com/exelban/stats): menu bar system monitoring
- [momenbasel/PureMac](https://github.com/momenbasel/PureMac): a SwiftUI CleanMyMac alternative
- [harry0703/MangoDisk](https://github.com/harry0703/MangoDisk): safety-first cleaning and the treemap space analyzer
