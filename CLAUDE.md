# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projects

Two independent Xcode projects live side-by-side:

| Project | Path | Target |
|---|---|---|
| MSC (macOS) | `MSCmacOS/Minecraft_Server_Controller.xcodeproj` | macOS 13+ |
| MSC Remote (iOS) | `MSCiOS/MSCRemoteiOS.xcodeproj` | iOS 16+ |

## Build & Run

Open the relevant `.xcodeproj` in Xcode 15+ and press `⌘R`. There are no build scripts, Makefiles, or CLI build steps. No tests exist in this codebase.

To build from the command line (e.g. to verify compilation):
```
xcodebuild -project "MSCmacOS/Minecraft_Server_Controller.xcodeproj" \
           -scheme "Minecraft Server Controller" \
           -destination "platform=macOS" build
```

## macOS App Architecture

**SwiftUI/MVVM.** The entire app flows through a single `@MainActor ObservableObject`:

```
AppViewModel  (AppViewModel.swift + AppViewModel+X.swift extensions)
 ├── ConsoleManager        — console lines, filtering, structured parsing
 ├── ServerLifecycleManager — metrics timer, readiness flags
 ├── ServerBackend (protocol)
 │    ├── JavaServerBackend   — spawns JVM via Swift's Process class
 │    └── BedrockServerBackend — shells out to Docker CLI
 └── ConfigManager         — loads/saves AppConfig to JSON; secrets to Keychain
```

**Extension pattern.** `AppViewModel` is split into ~25 `AppViewModel+X.swift` files. Each owns a feature domain (WorldSlots, Backups, PlayerProfiles, Metrics, etc.) and its `@Published` vars are declared in `AppViewModel.swift` itself — extensions cannot add stored properties.

**Persistence.** `ConfigManager` writes `AppConfig` (containing an array of `ConfigServer`) to `~/Library/Application Support/MinecraftServerController/server_config_swift.json`. Sensitive values (Remote API token, Xbox Broadcast password) go to the macOS Keychain via `KeychainManager`. Never put secrets in the JSON.

**`ConfigServer` is the server data model** — it has `serverType: ServerType` (`.java` / `.bedrock`) and the convenience `isBedrock: Bool`. `Server` is a lightweight UI-only struct (id + name + directory) used for selection state.

**Process execution.** All server operations shell out: Java servers via `ServerProcessManager` (Swift `Process` wrapping the JVM), Bedrock servers via Docker CLI commands. One-off tools (e.g. future Chunker integration) should follow the same pattern — `Process` + stdout stream.

## Design System

All design tokens live in `MSCStyles.swift` under the `MSC` enum. Always use these — never hardcode values.

```swift
MSC.Spacing.{xxs|xs|sm|md|lg|xl|xxl|xxxl}   // 4-pt grid
MSC.Radius.{sm|md|lg|xl}
MSC.Colors.{success|warning|error|info}        // semantic status
MSC.Colors.{tierAtmosphere|tierChrome|tierContent|tierCard}  // vitreous surface tiers
MSC.Typography.{pageTitle|sectionHeader|cardTitle|caption|mono}
```

The vitreous tier system: Atmosphere (darkest, window BG) → Chrome (sidebar/banner) → Content (panel surface) → Card (card fill). Match the tier to the surface depth.

## World Slot System

`WorldSlotManager.swift` + `AppViewModel+WorldSlots.swift` own world snapshots.

**On-disk layout:**
```
{serverDir}/world_slots/{slotId}/
    world.zip      — zipped world folder(s)
    slot.json      — WorldSlot metadata (name, dates, seed, levelName)
```

**Key rule:** the server must be stopped before any slot operation that touches world data. `AppViewModel` enforces this; `WorldSlotManager` does not.

**Java worlds** zip the level-name folder plus `_nether` and `_the_end` siblings. **Bedrock worlds** zip the `worlds/` directory from the Docker volume.

## iOS Companion App

`MSCiOS` is a separate app that connects to the macOS app's `RemoteAPIServer` (HTTP + WebSocket) over LAN or Tailscale. The iOS app has its own `DashboardViewModel` and communicates exclusively through `RemoteAPIClient`. When adding macOS features that the iOS app should reflect, add a corresponding endpoint in `RemoteAPIServer+HTTP.swift` and update `RemoteAPIServerDTOs.swift`.

## UI Patterns

- **Destructive actions** use `.confirmationDialog` (not `.alert`) — see `DetailsWorldsTabView` for reference.
- **Multi-step operations** use sheets rather than navigation pushes.
- **Bedrock-only controls** are gated on `cfgServer?.isBedrock == true` inline in the view — no separate view hierarchy.
- **Success banners** use `BannerView` — prefer this over alerts for non-blocking feedback.
- `MSCSecondaryButtonStyle` is the standard style for toolbar/header action buttons.
