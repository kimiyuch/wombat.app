# DiskLens

A small native macOS app that shows where your disk space goes and helps you free it.

- Live scan of your home folder, ~/Library, /Applications, simulator runtimes and Homebrew
- Usage bar of the whole disk, plus the biggest folders in your home and in ~/Library
- Cleanup list: "Safe" items (Trash, caches, npm cache, Docker, Xcode leftovers, node_modules) can be cleaned from the app; "Check first" items open in Finder
- node_modules and Composer vendor folders: pick projects one by one
- Nothing is deleted without a confirmation

## Build

```bash
cd wombat.app
./build.sh
```

Requires macOS 14+ and Xcode (or the Command Line Tools). The finished app is in `build/DiskLens.app`.

## First run

Give DiskLens **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access), then reopen it. Without it, Mail, Messages and some app data look smaller than they are. Because the app is signed ad hoc, macOS may ask again after you rebuild it.

The first time you empty the Trash from DiskLens, macOS asks whether it may control Finder.

## Files

- `Sources/DiskLens/DiskScanner.swift` — scanning (du, find, diskutil) and the cleanup actions
- `Sources/DiskLens/Views.swift` — reusable views (cards, bars, cleanup list, folder picker)
- `Sources/DiskLens/DiskLensApp.swift` — the app and main window
- `Sources/DiskLens/Shell.swift` — running command-line tools off the main thread
