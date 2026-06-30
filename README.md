# Minecraft Server Controller

> **Built by ctemple9**

---

I made this app because Realms kept charging me for months I barely played, and self-hosting a server on macOS was more annoying than it needed to be. Terminal works, but parsing through console output gets old, and keeping things updated is a pain when you've never done it before. I also wanted cross-play between Bedrock and Java, which meant setting up Geyser and Floodgate, which meant more things to break.

So I built MSC. It handles all of it. You pick a server type, it sets everything up, and a guide walks you through port forwarding so friends outside your house can actually connect. No terminal, no config files, no hunting down the right version of paper/plugins.

If you just want to play Minecraft with friends or family without paying for Realms every month, this is probably what you need.

> [!WARNING]
> **Work in progress.** It works, but you will hit bugs. Open an issue if something breaks, it genuinely helps.

---

## This is for you if:
You're on a Mac, you want to host a server for friends or family, and you don't want to learn how servers work to do it. Java, Bedrock, or both. 

## This is probably not for you if:
You need Windows or Linux, or you're running a large public server.

## Quick Start

### Before you begin (the app walks through these steps if you need help)
- **macOS 13+**
- **Java** is required for **Paper / Java Edition** servers
- **Docker Desktop** is required for **Bedrock** servers
- **Port forwarding is required** if players outside your home network will join
- You must be able to log into your router and change its port forwarding settings

### Start a server
1. Download and open **Minecraft Server Controller**
2. Create a new server
3. Choose your server type — **Standard Java** (Paper, Purpur, Vanilla), **Modded Java** (Fabric, NeoForge, Forge), or **Bedrock**
4. Complete setup and start the server
5. Open **Port Forwarding Help**
6. Log into your router and forward the server port
7. Share your public IP or DuckDNS hostname with friends

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
- Browse and install mods and plugins from Modrinth in-app; import modpacks (`.mrpack`)
- Live console, performance monitoring, world slot management, auto backups
- Archive system — auto-archives downloaded jars; archive-first reinstalls
- Startup crash diagnostics with one-click repair
- Watchdog — automatically restarts MSC if it crashes
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
| Bedrock servers | [Docker Desktop](https://www.docker.com/products/docker-desktop/) |

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
| [itzg / minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server) | Docker image for Bedrock Dedicated Server |
| [MCXboxBroadcast](https://github.com/MCXboxBroadcast/Broadcaster) | Xbox and console LAN discovery broadcasting |
| [Modrinth](https://modrinth.com) | Mod and plugin catalog used for in-app browsing and installation |
| [Playit.gg](https://playit.gg) | Tunnel service for hosting without port forwarding |


---

## License

MIT — see [LICENSE](LICENSE)
