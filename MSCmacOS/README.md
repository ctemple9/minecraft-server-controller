# Minecraft Server Controller (MSC)

**One app. Any Minecraft server.**

Minecraft Server Controller is a macOS utility for running and managing Minecraft servers — Standard Java (Paper, Purpur, Vanilla), Modded Java (Fabric, NeoForge, Forge), and Bedrock (built-in VM) — from a single, purpose-built interface. No terminal required.

> **Built by ctemple9 / TempleTech**

---

## Overview-Java Server
![Overview](docs/screenshots/overview-java.png)

## Overview-Bedrock Server
![Bedrock Server](docs/screenshots/overview-bedrock.png)

## Create New World
![World Management](docs/screenshots/create-new-world.png)
![World Management](docs/screenshots/create-new-world-pt2.png)


## Performance 
![Performance](docs/screenshots/performance.png)

## Files
![Files](docs/screenshots/files.png)

---

## Features

### Java Servers

**Standard server types** (all use the `java -jar` launch path; add plugins from Modrinth):
- **Paper** — default; fast, plugin-compatible, actively maintained
- **Purpur** — Paper superset with hundreds of extra configuration toggles
- **Vanilla** — unmodified Mojang server; no plugins or mods

**Modded server types** (install mods from Modrinth; every player must run the same mods):
- **Fabric** — lightweight mod loader; Fabric API auto-installed on creation
- **NeoForge** — full installer-based mod loader; supports large content modpacks
- **Forge** — original mod loader; same installer flow as NeoForge

**Java server management:**
- Start, stop, and monitor server processes
- Live console with filtering, search, and command entry
- Auto and manual world backups with metadata
- World slot management — duplicate, swap, export, replace, and repair worlds
- Performance monitoring (TPS, RAM, CPU, uptime)
- Server properties editor
- Per-server flavor badge in the sidebar and server header

**Mods and plugins (Modrinth browser):**
- Browse and install mods or plugins in-app with full project pages
- Compatibility filtering — results pre-filtered to your server's loader and MC version
- Client-only badge — flags mods that do nothing on a server
- Dependency resolution — required dependencies installed automatically
- Modpack import — import `.mrpack` files directly into the Components tab
- Mod/plugin management — enable, disable, and remove installed add-ons
- Update detection — hash-based matching against Modrinth catalog; one-tap Update All
- Client mod export — generate a ZIP (modded) or Modrinth link list (Paper) to share with players

**Archives:**
- Auto-archives every downloaded server jar when the setting is on
- Archive-first installs — uses a cached jar instead of re-downloading when available
- NeoForge and Forge version library — apply a previously installed loader version without re-running the installer
- Delete archived jars to reclaim disk space

**Diagnostics:**
- Startup crash detection — identifies the failing component (Paper, Fabric, NeoForge, Forge) and surfaces repair actions (Update, Reinstall)
- Java version compatibility preflight — warns before launch if the installed Java is too old for the chosen MC version

### Bedrock Servers
- Built-in VM runtime — Bedrock Dedicated Server runs in a lightweight Apple Virtualization.framework VM; no Docker, no external install
- Automatic provisioning — MSC downloads and installs the correct BDS version on first start and updates it when a new version is selected
- BedrockConnect integration for cross-platform LAN play
- Xbox Broadcast support for console/mobile discovery; enable during server creation in the wizard
- Allowlist management
- Bedrock-specific properties editor
- Player profile cards — reads both compacted LevelDB tables and write-ahead log files so profiles appear immediately after a player's first session; auto-names players via liveness correlation when possible

### Both Server Types
- Session log and player history
- Resource pack management
- DuckDNS hostname support
- **Playit.gg tunneling** — fully in-app setup (email + password, no browser); MSC signs in natively, claims an agent, and creates Java + Bedrock tunnels automatically; Simple Voice Chat tunnel auto-created when the SVC plugin is detected
- **Xbox Broadcast** — console and mobile players see your server in the Friends tab; enable during server creation or from the server detail view; supports in-app Microsoft sign-in (WKWebView device-code flow)
- **"Initiate" first-start flow** — on first launch, MSC runs a two-pass sequence: generate all config files (pass 1), then bring up networking transports (pass 2), before showing a completion sheet with full connection info; LAN, playit.gg, and Xbox/console connection methods shown
- **"How to Connect" sidebar section** — always-visible quick-access panel with all connection methods; show/hide toggle masks addresses for screen sharing
- Remote API for the **MSC Remote** iOS companion app
- Onboarding and setup wizard — 7-page multi-step flow (Welcome, Server Type, Server Root + Java, playit.gg, Xbox Broadcast, Tailscale, Done); context-aware tour adapts to chosen server type
- Server Handbook — 31 in-app help topics across 6 categories
- Server notes
- Edit server — split-view editor with a grouped sidebar for all settings tabs
- Expanded server.properties editor — World settings (game mode, difficulty, world type, hardcore, PvP, mob spawning), Server settings (whitelist, idle timeout, op permission level), Purpur-specific section
- Watchdog — launchd-based process that restarts MSC automatically if it crashes
- World thumbnails and player skin overrides

---

## Requirements

- **macOS** 13 or later
- **Java** (for Java servers) — [Adoptium Temurin](https://adoptium.net) recommended
- **Bedrock servers** — no external install needed; runs in a built-in Apple Virtualization.framework VM (macOS 13+ required)

---

## Installation

### Option 1: Download the App
Download the latest release from the [Releases page](../../releases).

### Option 2: Build from Source
1. Clone this repo
2. Open `Minecraft_Server_Controller.xcodeproj` in Xcode 15 or later
3. Select your development team in Signing & Capabilities
4. Build and run (`⌘R`)

---

## Privacy

MSC does not include analytics, telemetry, or crash reporting. Nothing is sent to TempleTech.

The app makes network requests **on your behalf** to:

| Service | Purpose |
|---------|---------|
| `api.ipify.org` | Detect your public IP address for connection info display |
| `portchecker.io` | Check whether your server port is open to the internet |
| `minotar.net`, `mc-heads.net`, `api.mcheads.org` | Fetch player avatar images using Minecraft usernames |
| `api.github.com` | Check for latest versions of Paper, Xbox Broadcast, BedrockConnect jars |
| `papermc.io`, `github.com`, `minecraft.net` | Download Paper jars and version manifests |
| `api.purpurmc.org` | Fetch Purpur build metadata and download jars |
| `launchermeta.mojang.com`, `piston-data.mojang.com` | Fetch Vanilla version manifest and download server jars |
| `meta.fabricmc.net` | Resolve Fabric loader and installer versions |
| `maven.neoforged.net` | Resolve and download NeoForge installer |
| `maven.minecraftforge.net`, `files.minecraftforge.net` | Resolve and download Forge installer |
| `api.modrinth.com` | Search, browse, and download mods and plugins |
| `playit.gg` | Tunnel agent communication (only when Playit.gg is enabled) |

**Credentials:** The Remote API token, Xbox Broadcast account password, and Playit.gg secret key are stored in the macOS Keychain. Server names, notes, and settings are stored locally in `~/Library/Application Support/MinecraftServerController/server_config_swift.json`. Archived jars are stored in `~/Library/Application Support/MinecraftServerController/PaperTemplates/`.

---

## MSC Remote (iOS Companion App)

MSC includes a built-in Remote API server. The **MSC Remote** iOS app connects to this API to monitor and control your servers from your phone.

---

## Architecture

MSC is a SwiftUI/MVVM macOS app:

- `AppViewModel` — central state, split across `AppViewModel+X.swift` extension files
- `ServerBackend` protocol — `JavaServerBackend`, `BedrockServerBackend` (legacy Docker, kept for reference), and `VMBedrockServerBackend` (active — boots a bundled Kata kernel + custom initramfs via `VZVirtualMachine`) implement server-type-specific logic
- `UDPRelay` — Network.framework relay that bridges host port 19132 to the guest VM so LAN and playit.gg clients can reach BDS
- `BedrockProvisioner` — downloads and extracts the correct BDS Linux binary into `serverDir` on first start and on version change
- `JavaServerFlavor` — enum covering all Java server types (Paper, Purpur, Vanilla, Fabric, NeoForge, Forge); drives provisioning kind, add-on folder, Modrinth facets, and UI labels
- `ServerJarProviders` — download-and-go provisioners for Paper, Purpur, Vanilla, and Fabric; `MSCHTTP` sets the required User-Agent on all outbound requests
- `NeoForgeInstaller` / `ForgeInstaller` — run the `--installServer` installer, stream output, locate the generated args file
- `ModrinthAPI` — search, project detail, version list, and file download; also used for plugin management
- `ModrinthBrowserView` — in-app Modrinth browser sheet with project detail pages, compatibility checker, and client-only filtering
- `ModJarMetadataParser` — extracts mod ID, name, and version from `fabric.mod.json` and `META-INF/mods.toml` inside jar files
- `JavaRuntimeManager` — maps MC version to required Java major; detects the configured Java version at launch
- `ConfigManager` — persists settings; secrets go to Keychain, config goes to JSON
- `RemoteAPIServer` — serves the iOS companion app over a local HTTP API
- `MSCStyles.swift` — single source of truth for all design tokens

---

## License MIT — see [LICENSE](LICENSE)

---

## Acknowledgements

- [PaperMC](https://papermc.io) — the Paper Minecraft server
- [PurpurMC](https://purpurmc.org) — Paper fork with extended configuration options
- [FabricMC](https://fabricmc.net) — lightweight mod loader for Java servers
- [NeoForged / NeoForge](https://neoforged.net) — modern Forge-based mod loader for Java servers
- [MinecraftForge](https://minecraftforge.net) — original Java mod loader
- [GeyserMC/Geyser](https://github.com/GeyserMC/Geyser) — protocol translation layer allowing Bedrock clients to join Java servers
- [GeyserMC/Floodgate](https://github.com/GeyserMC/Floodgate) — hybrid mode plugin for Geyser, allowing Bedrock players without a Java account
- [BedrockConnect](https://github.com/Pugmatt/BedrockConnect) — cross-platform server browser for Bedrock/console players
- [MCXboxBroadcast](https://github.com/MCXboxBroadcast/Broadcaster) — Xbox/console LAN discovery broadcasting
- [Modrinth](https://modrinth.com) — mod and plugin catalog used for in-app browsing and installation
- [Playit.gg](https://playit.gg) — tunnel service for hosting without port forwarding
- [Adoptium Temurin](https://adoptium.net) — recommended Java runtime
