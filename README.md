# Minecraft Server Controller

> **Built by ctemple9**

---

I made this app because Realms kept charging me for months I barely played, and self-hosting a server on macOS was more annoying than it needed to be. Terminal works, but parsing through console output gets old, and keeping things updated is a pain when you've never done it before. I also wanted cross-play between Bedrock and Java, which meant setting up Geyser and Floodgate, which meant more things to break.

So I built MSC. You pick the kind of server you want to run, and the app handles the setup for you. Java, Bedrock, or both. No terminal, no digging through config files, no hunting down the right Paper version, plugins, or mod loader.

To let other people join your server, MSC helps you handle the connection setup too. You can either follow the app's port forwarding guidance and use your router, or use Playit.gg if you don't know how to port forward, don't have access to your router, or just want an easier option.

If you want a simple way to host Minecraft for friends or family without paying for Realms every month, this is probably what you need.

> [!WARNING]
> **Work in progress.** It works, but you will hit bugs. Open an issue if something breaks, it genuinely helps.

---

## This is for you if:
You're on a Mac and you want to host a Minecraft server for friends or family without having to figure out all of the server setup alone.

This app is especially for you if:
- You want to play **Java**
- You want to play **Bedrock**
- You want **Java and Bedrock players together**
- You don't know how to port forward
- You don't have access to your router settings
- You do have router access and want help setting it up properly
- You just want the easiest way to get a server online for your group

## This is probably not for you if:
- You need Windows or Linux support
- You're running a large public server
- You already prefer doing everything manually in Terminal

## Quick Start

### Before you begin
- **macOS 13+**
- **Java** is required for **Java Edition** servers
- **Bedrock** servers run in a built-in VM — no extra install needed
- To let other people join your server, MSC gives you **two ways** to handle connection setup:
  - **Router port forwarding** if you have access to your router
  - **Playit.gg** if you don't know how to port forward, don't have router access, or just don't want to deal with it

### Start a server
1. Download and open **Minecraft Server Controller**
2. Create a new server
3. Choose your server type — **Standard Java** (Paper, Purpur, Vanilla), **Modded Java** (Fabric, NeoForge, Forge), or **Bedrock**
4. Complete setup and start the server
5. Choose how other people will connect:
   - **Router port forwarding** for a direct connection
   - **Playit.gg** for a simpler setup with no router changes
6. Share the connection info MSC gives you

## Connection Options

### Option 1: Router Port Forwarding
If you have access to your router and want the most direct setup, MSC can guide you through port forwarding so other people can join your server.

### Option 2: Playit.gg
If you don't know how to port forward, don't have access to your router, or simply don't want to learn it right now, **Playit.gg is totally fine**. MSC supports it in-app and can get your server online without changing router settings.

There may be a **small amount of extra lag sometimes** compared to direct port forwarding, but for most casual servers with friends, it works well.

---

### MSC macOS - Overview
![Overview](MSCmacOS/docs/screenshots/overview-java.png)

### MSC macOS - Performance 
![Performance](MSCmacOS/docs/screenshots/performance.png)

### MSC Remote — iOS Dashboard
![Dashboard](MSCiOS/docs/screenshots/dashboard.png)


---

## Apps

### [MSC — Minecraft Server Controller (macOS)](MSCmacOS/)

Run and manage Java and Bedrock servers from a native macOS app. No terminal required.

- **Standard Java servers** — Paper, Purpur, Vanilla
- **Modded Java servers** — Fabric, NeoForge, Forge (with full installer support)
- **Bedrock servers** — built-in Apple Virtualization.framework VM; no Docker or external runtime needed
- Browse and install mods and plugins from Modrinth in-app; import modpacks (`.mrpack`)
- Live console, performance monitoring, world slot management, auto backups
- Archive system — auto-archives downloaded jars; archive-first reinstalls
- Startup crash diagnostics with one-click repair
- Watchdog — automatically restarts MSC if it crashes
- Playit.gg tunneling — fully in-app setup (email + password, no browser); MSC creates and manages tunnels natively
- Xbox Broadcast — console/mobile players see your server in the Friends tab; configurable from the Create Server wizard
- Remote API for the iOS companion app

→ [View macOS README](MSCmacOS/README.md)

---

### [MSC Remote (iOS)](MSCiOS/)

Control your server from your iPhone over LAN or Tailscale VPN.

- Live server status, TPS, RAM, CPU
- Real-time console stream
- Send commands, view online players
- Worlds tab — browse world slots, trigger backups, and restore from your phone
- QR code pairing with the macOS app

→ [View iOS README](MSCiOS/README.md)

---



## Requirements

| App | Requirement |
|-----|-------------|
| MSC (macOS) | macOS 13 or later |
| MSC Remote (iOS) | iOS 16 or later |
| Java servers | [Adoptium Temurin](https://adoptium.net) |
| Bedrock servers | Built in — macOS 13+ required (uses Apple Virtualization.framework) |

---

## Built on Open Source

MSC would not exist without these projects. Thanks to everyone who built and maintains them:

| Project | Role |
|---------|------|
| [PaperMC](https://papermc.io) | Java server runtime (Paper) |
| [PurpurMC](https://purpurmc.org) | Paper fork with extended configuration options |
| [FabricMC](https://fabricmc.net) | Lightweight mod loader for Java servers |
| [NeoForged / NeoForge](https://neoforged.net) | Modern Forge-based mod loader for Java servers |
| [MinecraftForge](https://minecraftforge.net) | Original mod loader for Java servers |
| [GeyserMC / Geyser](https://github.com/GeyserMC/Geyser) | Protocol bridge, lets Bedrock clients join Java servers |
| [GeyserMC / Floodgate](https://github.com/GeyserMC/Floodgate) | Allows Bedrock players to join without a Java account |
| [MCXboxBroadcast](https://github.com/MCXboxBroadcast/Broadcaster) | Xbox and console LAN discovery broadcasting |
| [Modrinth](https://modrinth.com) | Mod and plugin catalog used for in-app browsing and installation |
| [Playit.gg](https://playit.gg) | Tunnel service for hosting without port forwarding |


---

## License

MIT — see [LICENSE](LICENSE)
