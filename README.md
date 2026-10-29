<p align="center">
  <img src="assets/logo.png" width="120" alt="GRID Logo" />
</p>

<h1 align="center">GRID: Native macOS Workspace & Window Manager</h1>

<p align="center">
  <strong>A 100% standalone, lightweight native macOS application built with Swift for Apple Silicon.</strong>
</p>

---

## ⚡ Features

- **🚀 100% Native Swift**: Compiled directly for Apple Silicon ARM64 using macOS AppKit and Accessibility APIs.
- **📸 1-Click Layout Snapshot**: Arrange your windows freely across any number of monitors, click `📸 Snapshot Current Layout...`, and save your workspace in seconds.
- **🖥️ Dynamic Multi-Display Support**: Automatically detects single displays (16" Built-in Retina) and multi-monitor setups (dual/triple displays), adapting layouts dynamically.
- **⚡ Smart App Launching & Snapping**: Restores your workspace effortlessly. If an app is closed, GRID automatically launches it and snaps its window into place.
- **🔗 Deep URL & Document Restore**: Automatically captures and re-opens exact web pages (e.g. WhatsApp Web in Brave Browser) and specific files (e.g. your active Excel or Numbers spreadsheets) directly upon profile activation.
- **🎯 Smart Workspace Isolation**: Automatically minimizes windows of applications outside the target profile to the Dock using native macOS Genie animations. Can be toggled on/off in the menu bar.
- **⊞ Pure Menu Bar Agent**: Runs quietly with zero Dock presence (`LSUIElement`).
- **⌨️ Global Hotkeys**: `Cmd + Option + Ctrl + G` re-snaps the active workspace; `Cmd + Option + Ctrl + 1…9` apply the first nine workspaces (in menu order) from any app.
- **🗂 Workspace Submenu**: Hover a workspace to apply, update it from the current layout, rename, duplicate, and see every window/file/site it restores — remove any of them with ✕.
- **🔽 Minimize All**: Send every window to the Dock in one click.
- **🔁 Login Item**: Toggle **Launch at Login** from the menu.
- **💾 JSON Persistence**: Workspace profiles live in `~/Library/Application Support/GRID/profiles.json` (see `profiles.example.json` for the format).

---

## 🛠️ Build & Installation

### Option 1: One-Command Install
```bash
./install.sh
```
This script compiles the Swift source code, packages `build/GRID.app`, copies it to `/Applications/GRID.app`, and launches it.

### Option 2: Build Only
```bash
./build.sh
```
The compiled application will be generated in `build/GRID.app`. Set `GRID_SIGN_IDENTITY` to sign with a real certificate instead of ad-hoc signing.

> **Signing note:** without `GRID_SIGN_IDENTITY`, the app is ad-hoc signed with a designated requirement based only on its bundle identifier, so macOS keeps the Accessibility permission across rebuilds. The trade-off is that any other app on the same Mac signed with that identifier would inherit the permission. If that matters to you, sign with your own certificate.

### Run Tests
```bash
swift test
```

---

## 📖 How to Use

1. **Accessibility Permissions:**
   On first launch, macOS will request Accessibility permissions:
   **System Settings** ➔ **Privacy & Security** ➔ **Accessibility** ➔ Enable **GRID**.

2. **Save a Workspace (Snapshot):**
   - Position your open windows (e.g. Browser, Numbers, IDE, WhatsApp) across your screens.
   - Click **`⊞ GRID`** in the Menu Bar (top right).
   - Click **`📸 Snapshot Current Layout...`**.
   - Type a name (e.g. `Office 3-Screens` or `Laptop Focus`) and press **Save Profile**.

3. **Restore / Apply:**
   - Click **`⊞ GRID`** ➔ hover a workspace ➔ **Apply Workspace**, or press **`Cmd + Option + Ctrl + 1…9`**.
   - The same submenu lists what the workspace opens; click ✕ to drop a window, or use **Update from Current Layout…**, **Rename…** and **Duplicate…**.
   - Use the shortcut **`Cmd + Option + Ctrl + G`** (works from any app) to re-align windows according to the active workspace.
   - Profiles are never applied automatically when displays change — you always pick one from the menu.

4. **Automation Permission:**
   The first time GRID reads browser URLs or Numbers/Excel documents, macOS asks to let GRID control that app. Allow it to restore web pages and files.

5. **Logs:**
   Open **Console.app** and filter by subsystem `com.amer.grid`.

---

## 📂 Architecture

```
GRID/
├── src/
│   ├── Core/                    # GRIDCore: pure, unit-tested logic
│   │   ├── Models.swift         # Codable structs for profiles and normalized coordinates
│   │   └── Geometry.swift       # Coordinate math & URL/title matching rules
│   └── App/                     # GRID executable (menu bar agent)
│       ├── main.swift           # App bootstrap
│       ├── AppDelegate.swift    # Lifecycle, global hotkey & display event listener
│       ├── MenuBarController.swift # Menu bar UI, alerts, snapshot dialogs
│       ├── WindowManager.swift  # Accessibility window capture, matching & positioning
│       ├── ScreenManager.swift  # Multi-display topology (with stable display UUIDs)
│       ├── ScriptBridge.swift   # AppleScript: per-window browser URLs & documents
│       ├── HotKeyManager.swift  # System-wide Carbon hotkey
│       ├── ProfileStore.swift   # JSON persistence in Application Support
│       └── Log.swift            # os.Logger categories
├── Tests/GRIDCoreTests/         # swift-testing unit tests
├── Package.swift                # Swift package (GRIDCore, GRID, tests)
├── Info.plist                   # Bundle metadata (LSUIElement = true)
├── build.sh                     # swift build + app bundle + codesigning
├── install.sh                   # Builds and moves GRID.app to /Applications
└── profiles.example.json        # Example profile format
```

---

## 📜 License
MIT License — see [LICENSE](LICENSE).
