# Minecraft Server Controller

**One app. Any Minecraft server.**

A macOS utility for running and managing Minecraft servers — both Java (Paper) and Bedrock (via Docker) — from a single, purpose-built interface. Paired with an iOS companion app for remote monitoring and control from your iPhone.

> **Built by ctemple9 / TempleTech**

---

> [!WARNING]
> **This project is a work in progress.** It is functional and usable, but you will encounter bugs. If something breaks, please open an issue — it helps a lot.

---

## Apps

### [MSC — Minecraft Server Controller (macOS)](MSCmacOS/)

Run and manage Java and Bedrock servers from a native macOS app. No terminal required.

- Start, stop, and monitor Java (Paper) and Bedrock servers
- Live console with filtering, search, and command entry
- World slot management, auto backups, performance monitoring
- Remote API for the iOS companion app

→ [View macOS README](MSCmacOS/README.md)

---

### [MSC Remote (iOS)](MSCiOS/)

Control your server from your iPhone over LAN or Tailscale VPN.

- Live server status, TPS, RAM, CPU
- Real-time console stream
- Send commands, view online players
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

MSC would not exist without these projects. Huge thanks to everyone who built and maintains them:

| Project | Role |
|---------|------|
| [PaperMC](https://papermc.io) | Java server runtime |
| [GeyserMC / Geyser](https://github.com/GeyserMC/Geyser) | Protocol bridge — lets Bedrock clients join Java servers |
| [GeyserMC / Floodgate](https://github.com/GeyserMC/Floodgate) | Allows Bedrock players to join without a Java account |
| [itzg / minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server) | Docker image for Bedrock Dedicated Server |
| [BedrockConnect](https://github.com/Pugmatt/BedrockConnect) | Cross-platform server browser for Bedrock and console players |
| [MCXboxBroadcast](https://github.com/MCXboxBroadcast/Broadcaster) | Xbox and console LAN discovery broadcasting |
| [Adoptium Temurin](https://adoptium.net) | Recommended Java runtime for Paper servers |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Container runtime for Bedrock server management |
| [Tailscale](https://tailscale.com) | Recommended VPN for remote access via MSC Remote |

---

## License

MIT — see [LICENSE](LICENSE)
