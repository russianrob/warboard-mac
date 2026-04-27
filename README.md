# Warboard for Mac

Native macOS client for the [warboard](https://tornwar.com) faction-ops
backend. Sister project to the
[warboard-native Android app](https://tornwar.com/warboard-native.apk).

## Status

**v0.1** — War Room (target list with status pills, score header,
chain bar) + Settings. Status / Faction tabs are placeholders for v0.2.

## Building

The project file is generated from `project.yml` via
[xcodegen](https://github.com/yonaskolb/XcodeGen) so it isn't checked
in. CI does this for you (see `.github/workflows/build-dmg.yml`).

### On a Mac

```sh
brew install xcodegen
xcodegen generate
open Warboard.xcodeproj
```

Cmd+R to build & run. The app appears in the Dock + Cmd-Tab.

### Without a Mac

Push to GitHub, then in the **Actions** tab run the **Build DMG**
workflow. The runner produces a universal-binary DMG you can download
from the run's **Artifacts** section.

For tagged releases (`git tag v0.1.0 && git push --tags`), the same
workflow attaches the DMG to the GitHub Release page automatically.

## Configuration

After install, open **Settings** in the sidebar and set:

- **Torn API key** — used for personal data + warboard authentication
- **Warboard server** — defaults to `https://tornwar.com`

## Architecture

Mirrors the warboard-native Android app:

```
Sources/Warboard/
├── WarboardApp.swift          — @main scene
├── Views/
│   ├── ContentView.swift      — NavigationSplitView shell
│   ├── WarRoomView.swift      — target list + header + chain bar
│   ├── SettingsView.swift     — API key + base URL
│   └── DashboardView.swift    — v0.2
├── ViewModels/
│   └── WarRoomViewModel.swift — 15 s polling + monotonic guard
├── Networking/
│   └── WarboardAPI.swift      — auth, fetchWars, fetchPoll, callTarget
├── Auth/
│   └── AuthRepository.swift   — JWT cache (UserDefaults v0.1)
├── Models/
│   ├── War.swift
│   └── CachedAuth.swift
└── Utilities/
    └── PrefsStore.swift       — UserDefaults wrapper
```

Same warboard server endpoints as the Android client.
