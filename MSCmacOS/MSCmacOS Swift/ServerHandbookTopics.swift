//
//  ServerHandbookTopics.swift
//  MinecraftServerController
//

import SwiftUI

// MARK: - Topic Content Views

extension ServerHandbookView {

    // ── Overview ──────────────────────────────────────────────────────────

    var overviewContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "house.fill",
                title: "Overview",
                subtitle: "What this app is and what it can do for you.",
                color: .blue
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Normally in Minecraft, your world lives inside one player's game. A server is like a separate, always-available room that everyone can visit. Minecraft Server Controller is the manager who sets up and runs that room on your Mac \u{2014} whether it's a Java room or a Bedrock room."
            )

            GuideBodyText("""
Minecraft Server Controller is a native macOS app that gives you a clean interface for running Minecraft servers. Instead of typing commands in Terminal, you get buttons, toggles, and visual feedback.

The app supports two types of servers \u{2014} Java (Paper) and Bedrock Dedicated Server (BDS) \u{2014} as equals. Java servers are great for plugin-heavy setups and Java Edition players. Bedrock servers natively support cross-play with mobile, console, and Windows 10/11 players out of the box.
""")

            InAppBox(items: [
                "Start and stop Java (Paper) or Bedrock servers with a single click",
                "Watch the live console \u{2014} see exactly what your server is doing",
                "Manage multiple servers from one window \u{2014} mix Java and Bedrock",
                "Configure ports, RAM (Java), plugins, cross-play, and Playit.gg tunneling",
                "Handle backups, world conversions, and server transfers",
                "Manage world slots, resource packs, and player allowlists",
                "Monitor live performance \u{2014} TPS, CPU, RAM, player health, and in-game time",
                "Remote control from iOS via MSC Remote (companion app)",
                "Watchdog crash recovery keeps your server running overnight"
            ])

            GuideCallout(style: .tip, text: "Starting fresh? Use \"Your First Java Server\" or \"Your First Bedrock Server\" in the Management section for a guided walk-through. You can always come back to other topics for deeper explanations.")

            AdvancedSection(content: """
Under the hood, Java servers run a shell command like:
  java -Xms2G -Xmx4G -jar paper.jar

Bedrock servers run inside a Docker container using the official itzg/minecraft-bedrock-server image. The app manages the Docker container lifecycle entirely \u{2014} start, stop, log streaming, volume mounts \u{2014} so you never have to open Docker directly.

Both approaches are fully managed. The complexity lives inside the app, not in front of you.
""")
        }
    }

    // ── Paper ─────────────────────────────────────────────────────────────

    var paperContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "server.rack",
                title: "What is a Paper Server?",
                subtitle: "Why Paper, and how it's different from vanilla Minecraft.",
                color: .blue
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Vanilla Minecraft is like the stock engine in a car \u{2014} official, reliable, but limited. Paper is a performance-tuned replacement engine that's still compatible with the original car, runs better, and lets you bolt on extra parts (plugins)."
            )

            GuideBodyText("""
**Vanilla Minecraft** is the official server from Mojang. It works, but it has limited configuration options and no plugin support.

**Paper** is a popular "fork" \u{2014} a modified version of the vanilla server that keeps gameplay the same but adds:
""")

            BulletList(items: [
                "Significantly better performance under load",
                "Hundreds of extra configuration options",
                "Support for the massive Bukkit/Spigot/Paper plugin ecosystem",
                "Faster bug fixes than the vanilla server"
            ])

            GuideCallout(style: .note, text: "Paper maintains full compatibility with vanilla Java clients. Your friends don't need to install anything special to join \u{2014} they just use their normal Minecraft launcher.")

            InAppBox(items: [
                "Each server folder needs a paper.jar file. The app downloads and manages these via Paper Templates.",
                "Use Paper Templates \u{2192} Download latest Paper to grab the newest build.",
                "Each server entry stores its own Paper JAR path \u{2014} different servers can run different Paper versions."
            ])

            AdvancedSection(content: """
Paper is part of a family of high-performance Minecraft server implementations. The main family tree is:

  CraftBukkit \u{2192} Spigot \u{2192} Paper \u{2192} Purpur

Each adds more features and performance improvements. Paper is the sweet spot between compatibility and performance for most home servers. This app is designed specifically for Paper and its direct plugin ecosystem.
""")
        }
    }

    // ── Bedrock ───────────────────────────────────────────────────────────

    var bedrockContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "cube.fill",
                title: "What is Bedrock Dedicated Server?",
                subtitle: "The native server for Minecraft on mobile, console, and Windows 10/11.",
                color: .green
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "If Java Edition is the PC version of Minecraft, Bedrock Edition is the universal version that runs everywhere else \u{2014} phones, tablets, Xbox, PlayStation, Nintendo Switch, and Windows 10/11. BDS is the dedicated server built for that universal version. Everyone on those platforms can connect to it with no extra setup on their end."
            )

            GuideBodyText("""
**Bedrock Edition** is the version of Minecraft available on mobile (iOS/Android), consoles (Xbox, PlayStation, Nintendo Switch), and Windows 10/11. It's sometimes called the "universal" edition because all those platforms play together seamlessly.

**BDS (Bedrock Dedicated Server)** is Mojang's official server software for Bedrock Edition. When you run a native Bedrock server:
""")

            BulletList(items: [
                "Mobile players (iOS/Android) can join directly",
                "Console players (Xbox, PlayStation, Switch) can join directly",
                "Windows 10/11 Minecraft players can join directly",
                "No plugins, translators, or extra configuration required for any of this \u{2014} it's built in"
            ])

            GuideCallout(style: .note, text: "Java Edition players cannot join a Bedrock server natively. If you want both Java and Bedrock players on the same server, use a Java (Paper) server with the Geyser plugin. See the Plugins & Cross-Play topic.")

            GuideBodyText("""
**Bedrock vs. Paper \u{2014} which should you run?**

Choose **Bedrock** if your players are primarily on mobile, console, or Windows 10/11, and you don't need Java plugins.

Choose **Paper (Java)** if your players are primarily on Java Edition, or if you want the rich plugin ecosystem (economy, claims, mini-games, etc.).

You can run both from this app simultaneously.
""")

            InAppBox(items: [
                "Create New Server \u{2192} choose Bedrock to create a native BDS server.",
                "Bedrock server port: Default port is 19132 UDP (not TCP). Port forwarding must be UDP.",
                "Player management uses allowlist.json and permissions.json \u{2014} the app handles these for you.",
                "No Java installation needed for Bedrock servers \u{2014} Docker provides the runtime."
            ])
        }
    }

    // ── Docker ────────────────────────────────────────────────────────────

    var dockerContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "shippingbox.fill",
                title: "Docker & How Bedrock Runs",
                subtitle: "Why Docker is needed and what the app does with it.",
                color: .blue
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Mojang only made BDS for Linux \u{2014} there's no Mac version. Docker is like a tiny portable Linux computer that runs inside your Mac. The BDS server thinks it's running on a Linux machine, which it is \u{2014} just a virtual one that lives in a box on your Mac."
            )

            GuideBodyText("""
**Why Docker?** Mojang has never released a native macOS binary for Bedrock Dedicated Server. The official BDS binary is Linux-only. Docker Desktop for Mac runs a lightweight Linux virtual machine, which allows the Linux BDS binary to run on your Mac without any compatibility hacks.

This is the standard solution used by Bedrock self-hosters worldwide. It's not a workaround \u{2014} it's the correct way to run BDS on macOS.
""")

            GuideCallout(style: .tip, text: "Docker Desktop is free for personal use. Download it from docker.com/products/docker-desktop. It's a one-time install \u{2014} after that, you never need to open or interact with Docker directly.")

            GuideBodyText("""
**After installing Docker Desktop, the app takes over completely:**

The app checks for Docker on launch. If Docker isn't running, it tells you. If Docker isn't installed, it links you to the download page. Once Docker is running, Bedrock server management is identical to Java \u{2014} click Start, click Stop, watch the console.
""")

            InAppBox(items: [
                "Docker image used: itzg/minecraft-bedrock-server (official, widely-used BDS image).",
                "On first Bedrock server start, the app pulls the Docker image automatically. This takes a minute \u{2014} progress shows in the console.",
                "Container start/stop is wired to the Start/Stop buttons \u{2014} same UI as Java servers.",
                "World data is stored in your server folder via Docker volume mount. Your data is never inside the container.",
                "Console output is streamed from the container in real-time, just like Java."
            ])

            GuideCallout(style: .note, text: "Docker Desktop must be running before you can start a Bedrock server. The app shows a clear warning if it detects Docker isn't running.")

            AdvancedSection(content: """
The app uses the docker CLI commands:
  docker run ... \u{2014} start a new container
  docker stop ... \u{2014} stop a running container
  docker exec ... \u{2014} send commands to the running server

Container names are derived from your server folder name to avoid conflicts. World data is mounted from {serverDir}/worlds to the container's expected data path, so your world persists across container restarts and image updates.

Updating BDS is as simple as pulling a newer image version. The app handles this via the version selector in server settings.
""")
        }
    }

    // ── JARs & Java ───────────────────────────────────────────────────────

    var jarsJavaContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "shippingbox.fill",
                title: "JAR Files & Java",
                subtitle: "The files that power your Java server and the engine that runs them.",
                color: .orange
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "A JAR file is a sealed package containing all the server's code. Java is the machine that opens that package and runs it. You need both \u{2014} the package alone doesn't do anything, and the machine needs a package to run."
            )

            GuideBodyText("""
**JAR** stands for Java ARchive. It's a bundle of compiled code \u{2014} essentially the server software in a single file.

**Java** is the runtime that executes that code. It's not specific to Minecraft; it's a general-purpose programming platform that millions of programs use.

When Minecraft Server Controller starts your Java server, it's running a command like:
`java -Xms2G -Xmx4G -jar paper.jar`

Note: JAR files and Java are only needed for Java servers. Bedrock servers use Docker instead.
""")

            GuideCallout(style: .warning, text: "Java must be installed on your Mac before a Java server can start. The app recommends Temurin 21 (from Adoptium). Use Preferences \u{2192} Check for Java to verify your setup.")

            InAppBox(items: [
                "Preferences \u{2192} Java Path: tells the app which java executable to use.",
                "Manage Servers \u{2192} Edit: each Java server has its own Paper JAR path (usually paper.jar inside the server folder).",
                "Details tab: shows a JAR summary \u{2014} which Paper, Geyser, and Floodgate builds this server is using and when they were last updated.",
                "Update Paper / Update Geyser / Update Floodgate buttons: one-click updates from your saved templates."
            ])

            GuideCallout(style: .pitfall, text: "Common pitfall: if you see \"java not found\" errors, your Java installation isn't in the expected location. Open Preferences, click Check for Java, and follow the prompts.")

            AdvancedSection(content: """
You can have multiple Java versions installed on your Mac (common with developers). You can point Minecraft Server Controller to a specific binary \u{2014} for example:
  /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java

This is useful if you want to test a server on an older Java version, or if you use a tool like SDKMAN to manage multiple JDKs.

Geyser and Floodgate are also JAR files \u{2014} they live in your server's plugins/ folder and get picked up automatically when the server starts.
""")
        }
    }

    // ── RAM & Performance ─────────────────────────────────────────────────

    var ramPerformanceContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "memorychip.fill",
                title: "RAM & Performance",
                subtitle: "How memory affects your Java server and what settings to use.",
                color: .green
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "RAM is like the size of your desk while you're working. The Minecraft world, players, and plugins all spread out on that desk. If the desk is too small, things fall off and the server lags or crashes. Too big, and your Mac's other apps have nothing left."
            )

            GuideBodyText("RAM settings apply to Java servers only \u{2014} Bedrock servers run in Docker and manage their own memory. For Java servers, here are practical starting points:")

            RamGuideTable()

            InAppBox(items: [
                "Manage Servers \u{2192} Edit \u{2192} General tab: Min RAM and Max RAM sliders.",
                "These map to Java's -Xms (minimum heap) and -Xmx (maximum heap) flags.",
                "Setting min = max reduces GC pauses at the cost of memory always being reserved.",
                "TPS (ticks per second) in the console overview shows server health. 20 TPS = smooth. Below 15 = noticeable lag."
            ])

            GuideCallout(style: .tip, text: "Leave at least 2\u{2013}3 GB of RAM free for macOS and other apps. Giving the server more RAM than it needs doesn't help \u{2014} the sweet spot is usually 4\u{2013}6 GB for a typical small server.")

            AdvancedSection(content: """
Paper exposes many performance tuning options in paper.yml, bukkit.yml, and spigot.yml. These files are created in your server folder automatically and can be edited by hand for fine-tuning.
""")
        }
    }

    // ── Plugins, Geyser & Floodgate ───────────────────────────────────────

    var pluginsGeyserFloodgateContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "puzzlepiece.fill",
                title: "Plugins & Cross-Play",
                subtitle: "Extend your Java server and let Bedrock players join.",
                color: .purple
            )

            GuideCallout(style: .note, text: "This topic covers cross-play for Java servers via Geyser/Floodgate. If you're running a native Bedrock server, cross-play with mobile, console, and Windows 10/11 players is built in \u{2014} no plugins needed.")

            AnalogyBox(
                title: "Think of it like this",
                text: "Plugins are app add-ons \u{2014} you drop them in a folder and they give the server new abilities. Geyser is a real-time translator between Java and Bedrock Minecraft, and Floodgate is the guest pass that lets Bedrock players in without a Java account."
            )

            GuideBodyText("""
**Plugins** are `.jar` files in your server's `plugins/` folder. They load when the server starts and can add almost anything \u{2014} new commands, economy systems, claim protection, chat formatting, mini-games, and more.

**Geyser** is a plugin (and also a standalone proxy) that translates the Bedrock network protocol into Java protocol in real-time. This means Bedrock players on phones, tablets, consoles, and Windows 10/11 can join your Java Paper server.

**Floodgate** works alongside Geyser to allow Bedrock players to join without owning a separate Java Edition account. Without Floodgate, `online-mode=true` would block Bedrock players.
""")

            GuideCallout(style: .note, text: "Geyser/Floodgate doesn't make the experience perfect \u{2014} some Java-only features like certain inventory layouts or maps behave differently on Bedrock. But basic gameplay works well.")

            InAppBox(items: [
                "Plugin Templates: download the latest Geyser and Floodgate JARs once into a global template folder.",
                "When creating a server: enable Bedrock Cross-play to automatically copy Geyser and Floodgate into the server's plugins/ folder.",
                "Update Geyser / Update Floodgate buttons: one-click to pull the newest version from your templates into the current server.",
                "Bedrock Port: configure this in Settings \u{2192} Network. Default is 19132 (UDP)."
            ])

            GuideCallout(style: .pitfall, text: "Common pitfall: Geyser listens on a separate port from your Java server (usually 19132 UDP vs. 25565 TCP). You need to forward BOTH ports on your router for external connections.")

            AdvancedSection(content: """
Geyser works in two modes:
\u{2022} Plugin mode (used here): Geyser runs inside your Paper server. Simpler setup.
\u{2022} Proxy mode: Geyser runs as a standalone proxy in front of the server. More flexible but more complex.

This app uses plugin mode by default, which is correct for most home servers.

Bedrock players connect to the same external IP as Java players, but use a different port. In Minecraft Bedrock, they go to Settings \u{2192} Servers \u{2192} Add Server and enter your IP and Bedrock port.

Floodgate also handles skin data for Bedrock players, so they show up in-game with their Bedrock skin and a "." prefix on their username (configurable).
""")
        }
    }

    // ── EULA & Online Mode ────────────────────────────────────────────────

    var eulaOnlineModeContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "checkmark.seal.fill",
                title: "EULA & Online Mode",
                subtitle: "The two must-know settings before your Java server can start.",
                color: .orange
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "The EULA is the rental agreement for using the server software \u{2014} you must sign it before you can move in. Online mode is the ID check at the door \u{2014} it verifies that everyone who tries to enter actually owns a ticket."
            )

            GuideBodyText("""
**EULA** (End User License Agreement) is Mojang's legal agreement for running their server software. The first time your server starts, it creates a file called `eula.txt` with `eula=false`. The server will refuse to fully boot until that becomes `eula=true`.

This is required by Mojang. The app makes it simple \u{2014} you just click a button.
""")

            GuideCallout(style: .pitfall, text: "If you see \"You need to agree to the EULA\" in the console and the server stops immediately, your EULA hasn't been accepted yet. Use the Details tab \u{2192} Accept EULA.")

            GuideBodyText("""
**Online Mode** (`online-mode` in `server.properties`) controls whether the server verifies player accounts with Mojang's authentication servers.

- `online-mode=true` (recommended): Every player's account is verified as legitimate. Standard and secure.
- `online-mode=false`: No account verification. Anyone can join with any username \u{2014} often called a "cracked" server.

**Important for Geyser/Floodgate users:** If you're using Floodgate for Bedrock players, keep `online-mode=true`. Floodgate handles Bedrock authentication separately.
""")

            GuideCallout(style: .warning, text: "Setting online-mode=false disables account verification, allows unverified clients, and can break plugins that depend on real player UUIDs. Only do this if you have a specific reason.")

            InAppBox(items: [
                "Details tab \u{2192} EULA section: Accept EULA button writes eula=true for you.",
                "Settings tab \u{2192} server.properties editor: Online Mode toggle (ON = true, OFF = false).",
                "The app will warn you if you try to start a server with an unaccepted EULA."
            ])
        }
    }

    // ── Ports & DuckDNS ───────────────────────────────────────────────────

    var portsForwardingDuckDNSContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "network",
                title: "Port Forwarding & DuckDNS",
                subtitle: "Configure your router to let friends outside your house reach your server.",
                color: .purple
            )

            GuideCallout(style: .note, text: "There are two ways to let external players connect. Port forwarding (this topic) configures your router directly. Playit.gg tunneling (next topic) routes traffic through a relay service \u{2014} no router access needed. See the \"How Servers Connect\" topic for a side-by-side comparison. If you\u{2019}re unsure which to use, read that topic first.")

            AnalogyBox(
                title: "Think of it like this",
                text: "The internet is a city. Your public IP is your building's address. Ports are the apartment numbers inside. Your server is apartment 25565 (Java) or 19132 (Bedrock). Friends need both the street address and the apartment number to visit \u{2014} and your router needs to be told which apartment to send them to."
            )

            GuideBodyText("""
**IP Address**: your internet connection's numeric address, like `123.45.67.89`. It's assigned by your internet provider and can change.

**Port**: a numbered channel on your computer. Different programs listen on different ports. Minecraft's defaults are:
- Java/Paper: **25565 (TCP)**
- Bedrock/BDS or Geyser: **19132 (UDP)**

**Port forwarding** tells your router to pass incoming traffic on a specific port to a specific computer on your home network. Without it, friends outside your house are blocked by your router and can't reach your server.
""")

            GuideCallout(style: .pitfall, text: "LAN (local network) players don't need port forwarding \u{2014} they connect directly using your Mac's local IP (like 192.168.1.x). Port forwarding is only needed for players outside your home.")

            GuideBodyText("""
**DuckDNS** solves a common problem: your home IP address changes over time. DuckDNS gives you a free, stable hostname like `yourname.duckdns.org` that automatically updates to point at your current IP. You give this hostname to friends instead of your raw IP.
""")

            GuideCallout(style: .note, text: "Setting up DuckDNS is optional but highly recommended. Without it, you'll need to send your friends your updated IP address every time it changes (which can happen weekly or after power outages).")

            InAppBox(items: [
                "Settings \u{2192} Network: set Server Port (Java) and Bedrock Port (Geyser or BDS).",
                "Details tab: shows Java address, Bedrock address, and your DuckDNS hostname if configured.",
                "Preferences: paste your DuckDNS hostname \u{2014} the app uses it throughout the connection info panels.",
                "The app does NOT configure your router. You must log into your router and set up port forwarding manually."
            ])

            AdvancedSection(content: """
Router port forwarding varies by manufacturer, but the concept is always:
  "When someone connects to [my external IP]:[port], send them to [Mac's local IP]:[same port]."

For a typical setup:
  \u{2022} TCP port 25565 \u{2192} your Mac's local IP (find it in System Settings \u{2192} Network)
  \u{2022} UDP port 19132 \u{2192} same Mac (for Bedrock BDS or Geyser cross-play)

Some routers call this "Virtual Servers" or "NAT rules" instead of "Port Forwarding" \u{2014} it's the same thing.

Important: Java uses TCP. Bedrock uses UDP. These are different protocols. If you forward TCP 19132 instead of UDP 19132 for Bedrock, it won't work.
""")
        }
    }

    // ── Xbox Broadcast ────────────────────────────────────────────────────

    var broadcastContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "dot.radiowaves.left.and.right",
                title: "Xbox Broadcast",
                subtitle: "Let Bedrock friends see your Java server appear in their Friends tab.",
                color: .green
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Geyser lets Bedrock players connect to your Java server, but they still have to know your address. Xbox Broadcast is like hanging a party flyer in the hallway \u{2014} your world shows up in Bedrock friends' \"Friends\" tab as joinable, so they can join with one tap instead of manually entering an address."
            )

            GuideBodyText("""
Minecraft Server Controller integrates with **MCXboxBroadcastStandalone** \u{2014} an open-source tool that uses a dedicated Xbox/Microsoft account to broadcast a "joinable session" so Bedrock friends can see your server in their Friends tab.

**How it works:**
1. You create a free alt Microsoft/Xbox account specifically for broadcasting.
2. Your Bedrock-playing friends add that alt account as a friend.
3. When broadcast is running, your server appears as joinable in their Friends tab.
""")

            GuideCallout(style: .warning, text: "This feature requires a dedicated alt Xbox account, not your personal one. Never use your main Microsoft account.")

            GuideCallout(style: .note, text: "Why a separate account? Xbox Broadcast keeps your server visible in the friends list by staying signed into Xbox Live continuously while the server runs. Using your real account would mean it appears permanently \u{201C}online\u{201D} elsewhere, which can conflict with other Xbox activity and Game Pass sessions. A free dedicated alt account \u{2014} any Outlook.com address works \u{2014} keeps this completely separate from your personal gaming.")

            GuideBodyText("""
**Requirements before enabling broadcast:**
- Geyser and Floodgate installed and working on your Java server
- Bedrock port forwarded on your router
- A free alt Microsoft account created specifically for this purpose
""")

            GuideCallout(style: .note, text: "Broadcast does not tunnel traffic or bypass your router. It only advertises the session. Friends still connect through your normal Bedrock port \u{2014} port forwarding is still required.")

            InAppBox(items: [
                "Manage Servers \u{2192} Edit \u{2192} Broadcast tab: configure the alt account and enable broadcast.",
                "When the server starts with broadcast enabled, MCXboxBroadcastStandalone starts automatically.",
                "Broadcast log lines appear in the console tagged as [Broadcast] so you can see its status.",
                "The broadcast helper JAR is managed through the app's JAR library \u{2014} downloaded once, used by any server."
            ])

            AdvancedSection(content: """
MCXboxBroadcastStandalone is an independent open-source project. Source code and documentation are available at:
github.com/MCXboxBroadcast/Broadcaster

The app generates a per-server config.yml for the broadcast helper, which includes your server's Bedrock IP and port. This config is stored in the server's folder and updated if you change Bedrock port settings.

Xbox broadcast has occasional authentication token expiry \u{2014} if it stops working, the broadcast helper usually recovers automatically. If it doesn't, stopping and restarting the server resets the auth flow.
""")
        }
    }

    // ── Worlds & Backups ──────────────────────────────────────────────────

    var worldsBackupsContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "archivebox.fill",
                title: "Worlds & Backups",
                subtitle: "Protect your world and understand how data is stored.",
                color: .orange
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "A world is a save file folder. A backup is a snapshot of that folder at a specific moment in time. If you try a new plugin and it corrupts your world, a backup lets you roll back to exactly how things were before."
            )

            GuideBodyText("""
In your server folder, each world is stored as a group of folders:
- `world/` \u{2014} the overworld
- `world_nether/` \u{2014} the Nether
- `world_the_end/` \u{2014} The End

The base name (`world`) comes from the `level-name` setting in `server.properties`. If you change it to `myserver`, the folders become `myserver/`, `myserver_nether/`, etc.

For Bedrock servers, world data is stored in a `worlds/` folder inside your server directory and is mounted into the Docker container automatically.

**Always back up before:**
- Installing or updating plugins
- Changing major server settings
- Updating to a new Paper/Minecraft version
- Letting new players join for the first time
""")

            GuideCallout(style: .pitfall, text: "Never delete or rename world folders while the server is running. Always stop the server first, make your change, then restart.")

            InAppBox(items: [
                "Worlds tab: create, restore, and manage backups for each world slot, with a legacy/unmatched section when older backups do not map cleanly.",
                "Backups are stored as .zip files in a backups/ folder inside your server directory.",
                "Restore: unpacks a backup zip, replacing current world folders. Server must be stopped.",
                "Duplicate to new server: creates a fresh server directory from a backup \u{2014} great for testing changes.",
                "World tools in the Worlds tab: Replace World (swap in a different world folder) and Rename World (safely updates level-name and folder names together).",
                "Automated rotating backups: the app can be configured to create backups on a schedule and automatically delete old ones."
            ])

            GuideCallout(style: .tip, text: "Tip: use the Rename World tool instead of manually renaming folders. The tool updates both the folder names and the level-name setting in server.properties together, so they stay in sync.")

            AdvancedSection(content: """
Backups made by the app are standard zip archives. You can open them in Finder to inspect or extract specific files (like player data).

The automated rotating backup system (if enabled) creates a backup every N hours and keeps only the last X backups. This prevents backup folders from growing indefinitely.

If a world gets corrupted, you can sometimes recover it without a full restore using Minecraft's built-in /replaceitem or by editing the region files \u{2014} but for most cases, restoring a recent backup is faster and safer.
""")
        }
    }

    // ── Remote Access ─────────────────────────────────────────────────────

    var remoteAccessContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "iphone",
                title: "MSC Remote (iOS)",
                subtitle: "Monitor and control your servers from your iPhone.",
                color: .blue
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "MSC Remote is like a remote control for your Mac's server. You can check if the server is running, see the console, and send commands \u{2014} all from your iPhone, even when you're away from your Mac."
            )

            GuideBodyText("""
**MSC Remote** is a companion iOS app that connects to the **Remote API** built into Minecraft Server Controller on your Mac.

When the Remote API is enabled, your Mac acts as a small local server that MSC Remote can connect to. You can:
- See which server is running and its status (works for both Java and Bedrock servers)
- Read the live console log
- Send commands to the server
- Check player count and performance stats
""")

            GuideCallout(style: .note, text: "MSC Remote works over your local network by default using your Mac\u{2019}s local IP. To use it from outside your home \u{2014} a different network, cellular, traveling \u{2014} you need Tailscale. Tailscale creates a secure private connection between your iPhone and Mac that works from anywhere with no port forwarding required. See the Tailscale topic in Connection & Access for a step-by-step setup guide.")

            GuideBodyText("""
**Access Tokens \u{2014} How Security Works**

The Remote API uses tokens instead of passwords. There are two types:
- **Owner token**: full access \u{2014} stored securely in your Mac's Keychain
- **Shared access tokens**: limited read-only access \u{2014} you can create these for guests or family members who should be able to check the server but not send commands
""")

            GuideCallout(style: .warning, text: "Keep your Owner token private. Anyone with the Owner token can send commands to your server. Shared access tokens are safer to distribute.")

            InAppBox(items: [
                "Preferences \u{2192} Remote API: enable the API server and configure the port (default: a local port you choose).",
                "Owner token: generated once and stored in macOS Keychain. View it in Preferences to enter in MSC Remote.",
                "Shared access tokens: create in Preferences for guests. These tokens have read-only access.",
                "MSC Remote iOS app: available separately. Enter your Mac's local IP, port, and token to connect.",
                "MSC Remote works with both Java and Bedrock servers."
            ])

            AdvancedSection(content: """
The Remote API runs as a lightweight HTTP server on your Mac. It only accepts connections from authorized tokens \u{2014} unauthenticated requests are rejected.

For remote access outside your home network, Tailscale is a popular zero-config VPN option. It assigns your Mac a stable private IP that you can reach from anywhere, which you can use with MSC Remote instead of your local IP.

The API exposes endpoints for server status, console streaming (via polling or SSE), and command dispatch. If you're technically inclined, you can also build your own client using the same API.
""")
        }
    }

    // ── First Java Server Checklist ───────────────────────────────────────

    var firstServerContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "flag.checkered",
                title: "Your First Java Server",
                subtitle: "A step-by-step checklist from zero to friends connecting on Java Edition.",
                color: .green
            )

            GuideCallout(style: .tip, text: "You don't need to memorize this. Bookmark it and work through it step by step. You can always come back to other topics in this guide for deeper explanations of any step.")

            Group {
                Text("Phase 1 \u{2014} Initial Setup")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(number: 1, title: "Install Java", detail: "Download Temurin 21 from adoptium.net. This is the Java runtime the server needs. After installing, verify it in Preferences \u{2192} Check for Java.")
                    ChecklistStep(number: 2, title: "Run the Setup Wizard", detail: "On first launch, the Setup Wizard appears. Choose a Servers Root folder (~/MinecraftServers is fine) and confirm your Java path.")
                    ChecklistStep(number: 3, title: "Download Paper templates", detail: "Open Jars in the sidebar. \u{2192} Download latest Paper. This saves the newest Paper build as a reusable template.")
                    ChecklistStep(number: 4, title: "(Optional) Download plugin templates", detail: "If you want Bedrock cross-play, open Jars \u{2192} Download latest Geyser and Download latest Floodgate.")
                }
            }

            Group {
                Text("Phase 2 \u{2014} Create Your Server")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(number: 5, title: "Add a new server", detail: "Click Manage Servers \u{2192} Add / Create Server. Select Java, give it a name, choose your Paper template, set RAM (2 GB min / 4 GB max is a good start), and enable Bedrock Cross-play if needed.")
                    ChecklistStep(number: 6, title: "Accept the EULA", detail: "Go to the Details tab for your server and click Accept EULA. The server can't start until this is done.")
                    ChecklistStep(number: 7, title: "Configure basic settings", detail: "In the Settings tab, set your MOTD (the message players see in the server list), max players, difficulty, and gamemode. Leave Online Mode ON.")
                }
            }

            Group {
                Text("Phase 3 \u{2014} Go Online")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(number: 8, title: "Start the server", detail: "Click Start. Watch the console. When you see \"Done (X.XX s)! For help, type /help\", the server is ready.")
                    ChecklistStep(number: 9, title: "Test local connection", detail: "Open Minecraft Java on the same Mac or another computer on your home network. Add a server using your Mac's local IP (e.g. 192.168.1.x) and port 25565. You should be able to connect.")
                    ChecklistStep(number: 10, title: "Enable external access", detail: "Friends outside your home need one of two approaches \u{2014} (A) Port Forwarding: log into your router and forward TCP port 25565 (and UDP 19132 for Geyser cross-play). Or (B) Playit.gg Tunneling: no router access needed; create a free Playit.gg account and enable the tunnel in Edit Server \u{2192} Settings \u{2192} Network. See Connection & Access for full step-by-step guides on both.")
                    ChecklistStep(number: 11, title: "(Optional) Set up DuckDNS", detail: "Create a free hostname at duckdns.org and add it to Preferences. Share yourname.duckdns.org with friends instead of your raw IP.")
                }
            }

            Group {
                Text("Phase 4 \u{2014} Stay Safe")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(number: 12, title: "Create a backup", detail: "Once everything works, open Server Details → Worlds and create your first backup. Label it \"initial setup\" or similar.")
                    ChecklistStep(number: 13, title: "Invite friends", detail: "Share your DuckDNS hostname (or IP) and port with friends. Java players use the Multiplayer menu; Bedrock players with Geyser add a server in their Servers tab.")
                }
            }

            GuideCallout(style: .note, text: "Congratulations! If you made it through this checklist, you're hosting a Minecraft Java server. Check out the other topics in this guide whenever you want to understand something more deeply or add new features.")
        }
    }

    // ── First Bedrock Server Checklist ────────────────────────────────────

    var bedrockSetupContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "flag.checkered",
                title: "Your First Bedrock Server",
                subtitle: "A step-by-step checklist from zero to friends connecting on Bedrock Edition.",
                color: .green
            )

            GuideCallout(style: .tip, text: "You don't need to memorize this. Work through it step by step. See the \"Docker & How Bedrock Runs\" topic if you want to understand why Docker is needed.")

            Group {
                Text("Phase 1 \u{2014} Initial Setup")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 1,
                        title: "Install Docker Desktop",
                        detail: "Download Docker Desktop (free for personal use) from docker.com/products/docker-desktop. Install it and open it at least once to start the Docker engine. You only do this once."
                    )
                    ChecklistStep(
                        number: 2,
                        title: "Open the app",
                        detail: "Launch Minecraft Server Controller. It detects Docker automatically. If Docker isn't running, the app will tell you \u{2014} just open Docker Desktop and try again."
                    )
                    ChecklistStep(
                        number: 3,
                        title: "Run the Setup Wizard",
                        detail: "On first launch, the Setup Wizard appears. Choose a Servers Root folder (~/MinecraftServers is fine). Select Bedrock as your server type. No Java path needed."
                    )
                }
            }

            Group {
                Text("Phase 2 \u{2014} Create Your Server")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 4,
                        title: "Create a new Bedrock server",
                        detail: "Click Manage Servers \u{2192} Create New Server \u{2192} select Bedrock. Set a display name, port (19132 is the default), max players, difficulty, and gamemode. Click Create."
                    )
                    ChecklistStep(
                        number: 5,
                        title: "Review server settings",
                        detail: "In the Settings tab, confirm your MOTD, max players, and difficulty. No EULA step needed for Bedrock \u{2014} BDS handles it automatically on first run."
                    )
                }
            }

            Group {
                Text("Phase 3 \u{2014} Go Online")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 6,
                        title: "Start the server",
                        detail: "Click Start. On first launch, the app pulls the Docker image automatically \u{2014} this may take a minute depending on your internet speed. Watch the console. When you see \"Server started\", it's ready."
                    )
                    ChecklistStep(
                        number: 7,
                        title: "Test local connection",
                        detail: "Open Minecraft on your phone, tablet, or another device on your home network. Go to Servers \u{2192} Add Server. Enter your Mac's local IP (e.g. 192.168.1.x) and port 19132. You should be able to connect."
                    )
                    ChecklistStep(
                        number: 8,
                        title: "Enable external access",
                        detail: "Friends outside your home need one of two approaches \u{2014} (A) Port Forwarding: forward UDP port 19132 on your router to your Mac\u{2019}s local IP. Bedrock requires UDP, not TCP \u{2014} forwarding TCP 19132 will not work. Or (B) Playit.gg Tunneling: no router access needed; Docker Desktop is already installed for Bedrock servers so no extra installs are required. Enable the tunnel in Edit Server \u{2192} Settings \u{2192} Network. See Connection & Access for full guides on both."
                    )
                    ChecklistStep(
                        number: 9,
                        title: "(Optional) Set up DuckDNS",
                        detail: "Create a free hostname at duckdns.org and add it to Preferences. Share yourname.duckdns.org with friends instead of your raw IP."
                    )
                }
            }

            Group {
                Text("Phase 4 \u{2014} Stay Safe")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 10,
                        title: "Create a backup",
                        detail: "Once everything works, open Server Details → Worlds and create your first backup. Label it \"initial setup\" or similar."
                    )
                    ChecklistStep(
                        number: 11,
                        title: "Invite friends",
                        detail: "Share your DuckDNS hostname (or public IP) and port 19132. Friends add it as a custom server in Bedrock's server list (Settings \u{2192} Servers \u{2192} Add Server). Bedrock cross-play is built in \u{2014} mobile, console, and Windows 10/11 players can all join."
                    )
                }
            }

            GuideCallout(style: .note, text: "Congratulations! You're hosting a native Bedrock server. All Bedrock Edition platforms can join \u{2014} no plugins or translators needed. Check out the other topics in this guide for backups, world management, and remote access.")
        }
    }
    // ── Server Files Browser ──────────────────────────────────────────────

    var serverFilesContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "folder.fill",
                title: "Server Files Browser",
                subtitle: "Browse, preview, and edit your server's files without leaving the app.",
                color: .orange
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Your server directory is like a filing cabinet. MSC's Files tab is a window into that cabinet — you can browse every drawer, read any document, and carefully edit the ones you need to change."
            )

            GuideBodyText("""
The **Files tab** gives you a full view of everything on disk inside your server's directory. For Java servers this includes your Paper JAR, plugins folder, world data, and all config files. For Bedrock servers it shows the host-side files that Docker bind-mounts into the container at /data when the server runs.

You can navigate into any subfolder and get back with the breadcrumb trail at the top.
""")

            InAppBox(items: [
                "Click any folder to navigate into it — breadcrumbs at the top let you jump back",
                "Text files (.yml, .json, .properties, .log, .txt, .sh, .cfg, .conf) can be previewed in-app with a click",
                "The preview sheet has an \"Edit File\" button — tap it, confirm the warning, and the file becomes editable",
                "Changes are written directly to disk when you click Save — there is no undo inside MSC",
                "Non-text files (JARs, ZIPs, images) open via \"Reveal in Finder\" instead",
                "\"Show in Finder\" in the breadcrumb bar opens the current folder in Finder"
            ])

            GuideCallout(style: .warning, text: "Editing server files directly can break your server if you make a mistake. Always stop the server before editing critical config files like server.properties or paper.yml. When in doubt, make a backup first.")

            GuideCallout(style: .tip, text: "The most commonly edited files are server.properties (core settings), ops.json (operator list), whitelist.json (allowlist), and plugin config YAMLs inside the plugins/ folder.")

            AdvancedSection(content: """
For Bedrock servers, all files shown are on your Mac's filesystem (your server's host directory). When the server starts, Docker bind-mounts this directory to /data inside the container. Edits you make here while the server is stopped take effect the next time the container starts.

For Java (Paper) servers, files are read and written directly — no container layer involved. The server process and MSC both access the same directory.

Neither server type locks individual files while running (except active world region files). Editing a config while the server is live won't cause a crash, but the change won't take effect until the server is reloaded or restarted.
""")
        }
    }

    // ── Networking Basics ─────────────────────────────────────────────────

    var networkingBasicsContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "globe.americas.fill",
                title: "How Servers Connect",
                subtitle: "Public IPs, private IPs, NAT, and the two ways friends reach your server.",
                color: .blue
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "The internet is a city. Every building (internet connection) has one street address (public IP). Inside each building are many apartments (devices). Your Mac is one apartment. When a friend wants to visit, they need the building address AND the apartment number \u{2014} and your building\u{2019}s front desk (router) needs to be told which apartment to send them to."
            )

            GuideBodyText("""
**Public IP** is the address your internet provider assigns to your home connection. Everyone outside your home sees this address when they try to reach something on your network. It\u{2019}s shared by all devices in your house.

**Private IP** is the address your router assigns to each device inside your home \u{2014} your Mac, your phone, your TV. These addresses (like 192.168.1.x or 10.0.0.x) only exist inside your home network and can\u{2019}t be reached directly from the internet.

**NAT (Network Address Translation)** is what your router does: it translates between your one public IP and all your private devices. Outbound traffic works automatically \u{2014} your Mac can reach the internet at any time. Inbound traffic is blocked by default \u{2014} the router doesn\u{2019}t know which device an incoming connection is meant for.

This is why you can load any website (your Mac reaches out) but a friend can\u{2019}t connect to your server without extra setup (they\u{2019}re trying to reach in).
""")

            GuideCallout(style: .note, text: "LAN players \u{2014} people on the same Wi-Fi or wired network as your Mac \u{2014} connect directly using your private IP and need nothing special. The external access problem only affects players outside your home.")

            GuideBodyText("""
**Two ways to solve this:**
""")

            InAppBox(items: [
                "Port Forwarding: tell your router to send traffic on a specific port (25565 TCP for Java, 19132 UDP for Bedrock) to your Mac. Requires router access and a reachable public IP. Free \u{2014} no external service needed. See the Port Forwarding & DuckDNS topic.",
                "Playit.gg Tunneling: your Mac connects outbound to Playit.gg\u{2019}s relay servers. Friends connect to an address Playit.gg gives you. No router access needed, but adds some latency and requires a free Playit.gg account. See the Playit.gg Tunneling topic."
            ])

            GuideCallout(style: .tip, text: "Not sure which to use? If you have access to your router and your ISP gives you a standard public IP, port forwarding is simpler long-term. If you\u{2019}re on a shared network, behind CGNAT (some mobile and cable ISPs), or just don\u{2019}t want to configure your router, Playit.gg is the better choice.")

            AdvancedSection(content: """
CGNAT (Carrier-Grade NAT) is used by some ISPs \u{2014} particularly mobile carriers and some cable providers. Under CGNAT, your home doesn\u{2019}t get its own public IP; you share one with many other customers. Port forwarding is impossible under CGNAT. If you set up port forwarding correctly and it still never works, CGNAT may be the reason.

You can check for CGNAT by comparing the WAN IP shown in your router\u{2019}s admin panel to the IP shown on a site like whatismyip.com. If they\u{2019}re different, you\u{2019}re behind CGNAT.

Playit.gg and all other tunneling solutions work under CGNAT because they rely only on outbound connections from your Mac.
""")
        }
    }

    // ── Playit.gg ─────────────────────────────────────────────────────────

    var playitSetupContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "antenna.radiowaves.left.and.right",
                title: "Playit.gg Tunneling",
                subtitle: "Let friends connect to your server without touching your router.",
                color: .purple
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Normally your server is like a shop inside a building with a locked front door \u{2014} friends need to know the address and the building needs to unlock the door (port forwarding). Playit.gg is like opening a franchise counter at their shopping mall. Friends go to the mall address; Playit.gg passes the traffic to your shop in the background. You never had to unlock your door."
            )

            GuideBodyText("""
**Playit.gg** is a free tunneling service for game servers. Instead of requiring your router to accept inbound connections, the app runs a small agent (via Docker) that connects outbound to Playit.gg\u{2019}s relay servers. Playit.gg gives you a stable public address \u{2014} like abc123.jth.mc.ply.gg \u{2014} that routes traffic back through the relay to your server.

**Why this matters:**
""")

            BulletList(items: [
                "No router configuration needed \u{2014} the agent makes outbound connections only",
                "Works behind CGNAT (some mobile and cable ISPs) where port forwarding is impossible",
                "Works on networks where you don\u{2019}t have router access \u{2014} dorms, apartments, offices",
                "The address Playit.gg gives you is stable and doesn\u{2019}t change when your home IP changes"
            ])

            GuideCallout(style: .note, text: "Playit.gg requires Docker Desktop \u{2014} the same Docker used for Bedrock servers. If you\u{2019}re already running a Bedrock server, Docker is already installed and you have everything you need.")

            GuideBodyText("""
**Tradeoffs vs. port forwarding:**
""")

            BulletList(items: [
                "Latency: game traffic passes through Playit.gg\u{2019}s relay servers, adding roughly 10\u{2013}50 ms. For most players this is unnoticeable.",
                "Account required: you need a free Playit.gg account (no credit card). One-time setup takes about 5 minutes.",
                "Docker required: the agent runs as a Docker container. Bedrock users already have Docker Desktop. Java-only users need to install it.",
                "Free tier: Playit.gg\u{2019}s free tier supports Minecraft tunnels without player count limits."
            ])

            InAppBox(items: [
                "Create Server wizard: choose Tunnel (playit.gg) in the Network step instead of a direct port.",
                "Existing server: Edit Server \u{2192} Settings \u{2192} Network \u{2192} toggle Playit.gg tunnel on.",
                "First start: a prompt asks for your Playit.gg agent secret key. The in-app setup guide walks through getting this from the Playit.gg website.",
                "Your Playit.gg addresses appear in the Overview connection card automatically once the agent is running.",
                "Voice Chat (Simple Voice Chat plugin): after enabling the tunnel, also enable Voice Chat Tunnel in Edit Server \u{2192} Settings \u{2192} Network, then create a matching Custom UDP tunnel in the Playit.gg dashboard."
            ])

            GuideCallout(style: .tip, text: "You can use Playit.gg and port forwarding simultaneously on the same server. Players connecting via the Playit.gg address are relayed; players connecting to your direct IP go straight through. Useful as a fallback for players who have trouble with one approach.")

            AdvancedSection(content: """
The app runs the Playit.gg agent as a Docker container alongside your Minecraft server. One agent (one secret key, one container) can tunnel multiple ports \u{2014} your Java port and Bedrock/Geyser port can both go through the same agent.

Individual tunnels are configured on the Playit.gg website and assigned to your agent. The agent picks them up automatically \u{2014} no server restart needed when adding or changing tunnels.

Supported tunnel types used by MSC:
  \u{2022} Minecraft Java (TCP) \u{2014} for Paper servers
  \u{2022} Minecraft Bedrock (UDP) \u{2014} for Geyser or native Bedrock servers
  \u{2022} Custom UDP \u{2014} for Simple Voice Chat (port 24454)
""")
        }
    }

    // ── Tailscale ─────────────────────────────────────────────────────────

    var tailscaleContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "lock.shield.fill",
                title: "Tailscale",
                subtitle: "Access MSC Remote from anywhere using a secure private network.",
                color: .purple
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Tailscale gives every device you add a permanent private phone number that only your approved devices can call \u{2014} no matter where any of them are in the world. Your Mac gets a Tailscale IP (like 100.64.0.1) that never changes and is only reachable from your other Tailscale devices."
            )

            GuideBodyText("""
**Tailscale** is a zero-config VPN that creates a secure private network between your devices. There\u{2019}s no server to maintain and no port forwarding to set up. You install Tailscale on your Mac and on your iPhone, sign into the same account on both, and they can reach each other from anywhere \u{2014} home Wi-Fi, cellular, a friend\u{2019}s network, anywhere with internet.

**Why you\u{2019}d use it:**
""")

            BulletList(items: [
                "Control your Minecraft server via MSC Remote from outside your home without exposing the Remote API port on your router",
                "Access the console and send commands while you\u{2019}re away",
                "Your Tailscale IP never changes, so your MSC Remote pairing stays valid even when your home IP changes",
                "Fully encrypted end-to-end \u{2014} no one can intercept Remote API traffic"
            ])

            GuideCallout(style: .note, text: "Tailscale is for MSC Remote app access and server management. It is not a replacement for port forwarding or Playit.gg for Minecraft game clients \u{2014} players still need one of those two approaches to join your server.")

            GuideBodyText("**Setup (one time per device):**")

            VStack(alignment: .leading, spacing: 14) {
                ChecklistStep(number: 1, title: "Create a Tailscale account", detail: "Go to tailscale.com and sign up. Free for personal use with up to 3 users and 100 devices. No credit card required.")
                ChecklistStep(number: 2, title: "Install Tailscale on your Mac", detail: "Download from the Mac App Store or tailscale.com. Open it and sign in with your account. Your Mac is now assigned a Tailscale IP \u{2014} click the menu bar icon to see it. It starts with 100.")
                ChecklistStep(number: 3, title: "Install Tailscale on your iPhone", detail: "Search \u{201C}Tailscale\u{201D} in the App Store. Sign in with the same account. Tap Connect.")
                ChecklistStep(number: 4, title: "Verify both devices appear connected", detail: "In Tailscale on your iPhone, you should see your Mac listed with a green dot. That\u{2019}s all the setup required.")
                ChecklistStep(number: 5, title: "Use the Tailscale IP in MSC Remote", detail: "In MSC Remote \u{2192} Settings, set the Base URL to your Mac\u{2019}s Tailscale IP and the Remote API port \u{2014} for example: http://100.64.0.1:48400. This works on any network automatically.")
            }

            InAppBox(items: [
                "Preferences \u{2192} Remote API: shows your Mac\u{2019}s local URL and port. Replace the local IP with your Tailscale IP when configuring MSC Remote for use outside your home network.",
                "Your Mac\u{2019}s Tailscale IP is shown in the Tailscale menu bar icon. It starts with 100.",
                "Once configured with a Tailscale IP, MSC Remote works everywhere \u{2014} you don\u{2019}t need to switch between home and away configurations."
            ])

            AdvancedSection(content: """
Tailscale uses WireGuard under the hood \u{2014} a modern, fast, and widely-audited VPN protocol. Traffic between your devices is encrypted end-to-end. Tailscale\u{2019}s coordination servers handle device discovery but never see your traffic.

For most home setups, Tailscale establishes direct peer-to-peer connections once both devices are online, giving very low latency. When a direct path isn\u{2019}t possible (strict NATs, some firewalls), it falls back to Tailscale\u{2019}s DERP relay servers automatically.

If you run multiple Macs with MSC, each gets its own Tailscale IP and can be reached independently from MSC Remote.
""")
        }
    }

    // ── World Conversion ──────────────────────────────────────────────────

    var worldConversionContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "arrow.2.circlepath",
                title: "World Conversion",
                subtitle: "Convert a world between Java Edition and Bedrock Edition format.",
                color: .teal
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Java and Bedrock worlds are written in different formats \u{2014} like the same novel published in two different languages. Conversion reads the original and writes it out in the other language. Most content comes through cleanly; some edition-specific features don\u{2019}t have an equivalent in the other format and get left behind."
            )

            GuideBodyText("""
Java Edition and Bedrock Edition store world data in fundamentally different formats. A world created on a Java server cannot be directly loaded by a Bedrock server, and vice versa. The World Conversion wizard handles the translation automatically.

**When you\u{2019}d use this:**
""")

            BulletList(items: [
                "You\u{2019}re switching from a Java server to a Bedrock server (or vice versa) and want to keep your existing world",
                "You want to run the same world on both a Java and a Bedrock server simultaneously",
                "A player wants to continue their singleplayer Bedrock world on your Java server"
            ])

            GuideCallout(style: .warning, text: "World conversion is a best-effort process. Blocks, items, and entities that don\u{2019}t exist in the target edition are dropped or approximated. Always create a backup before converting, and test the result before replacing your active world.")

            InAppBox(items: [
                "Worlds tab \u{2192} World Conversion Wizard: select the source world and target format.",
                "The wizard creates a converted copy \u{2014} it does not replace or delete your original world.",
                "Review the conversion summary after it finishes: it lists anything that couldn\u{2019}t be converted.",
                "To use the converted world: open the Worlds tab and use Replace World to swap it in after the server is stopped."
            ])

            GuideCallout(style: .note, text: "For most survival worlds, terrain, blocks, and player inventory convert cleanly. The main losses are edition-exclusive content: Java-only technical blocks, Bedrock-only items, and any content added by plugins or mods.")

            AdvancedSection(content: """
Java worlds store chunk data in the Anvil format \u{2014} .mca region files inside a world/ directory. Bedrock worlds use LevelDB \u{2014} a key-value store inside a leveldb/ directory. These are completely different storage formats, which is why direct file copying doesn\u{2019}t work between editions.

Conversion quality is generally good for vanilla survival worlds built on recent versions. The further apart the source and target versions, or the more modded/plugin-generated the content, the more conversion gaps you\u{2019}ll see.

The converted world should be tested in the target edition before you commit to using it as your active server world. Run around the spawn area, check your inventory, and test key locations before retiring the original.
""")
        }
    }

    // ── Server Import & Transfer ──────────────────────────────────────────

    var serverTransferContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "square.and.arrow.down.fill",
                title: "Server Import & Transfer",
                subtitle: "Move an existing server into the app or transfer it to a new Mac.",
                color: .teal
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Your server is a folder on disk \u{2014} all the settings, world data, and plugins live there. Import just tells the app where that folder is. Transfer is copying that folder to a different computer and pointing the new app at it."
            )

            GuideBodyText("""
If you have an existing Minecraft server \u{2014} one you ran manually from Terminal, one you managed with another tool, or one you\u{2019}re moving from a different Mac \u{2014} you can bring it into Minecraft Server Controller without starting from scratch. Your world data, plugins, settings, and player lists all carry over.

**Import an existing server:**
Point the app at an existing server folder. MSC reads the configuration, detects whether it\u{2019}s a Java or Bedrock server, and adds it to your server list. Nothing in the folder is changed during import.

**Transfer to a new Mac:**
""")

            BulletList(items: [
                "On your old Mac: create a backup from the Worlds tab, or simply locate your server folder in Finder",
                "Copy the entire server folder to your new Mac \u{2014} AirDrop, an external drive, or any file transfer method works",
                "On your new Mac: use File \u{2192} Import Server (or the + button in the server list) and select the copied folder",
                "The app reads the existing configuration automatically"
            ])

            InAppBox(items: [
                "File \u{2192} Import Server (or the + button in the server list): browse to an existing server folder to add it.",
                "The server folder must be self-contained \u{2014} all config files and world data should be inside one directory.",
                "Java servers: your Paper JAR path may need updating after a move if the folder is now in a different location.",
                "Bedrock servers: Docker pulls the correct image version automatically on first start after import."
            ])

            GuideCallout(style: .tip, text: "The most reliable way to transfer a server is to create a backup zip from the Worlds tab first. The backup is a complete, self-contained archive that\u{2019}s easy to move and easy to restore from.")

            GuideCallout(style: .note, text: "The app stores the path to each server folder but doesn\u{2019}t move or copy files itself. If you relocate a server folder in Finder after importing, update the path in Manage Servers \u{2192} Edit.")
        }
    }

    // ── Watchdog & Crash Recovery ─────────────────────────────────────────

    var watchdogContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "stethoscope",
                title: "Watchdog & Crash Recovery",
                subtitle: "Automatically restart your server if it crashes unexpectedly.",
                color: .teal
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "The watchdog is a supervisor that checks on your server at regular intervals. If the server stopped but was never told to stop, the supervisor restarts it. If you stopped it intentionally, the supervisor sees the note you left and leaves it stopped."
            )

            GuideBodyText("""
Minecraft servers can crash \u{2014} a buggy plugin, an out-of-memory condition, or a rare JVM error can bring the server down without warning. Without a watchdog, it stays down until someone manually restarts it.

**How the MSC watchdog works:**
""")

            BulletList(items: [
                "A background launchd agent (a macOS system service) polls periodically to check whether your server process is running",
                "When you stop the server intentionally via the Stop button or the /stop command, the app writes a clean-quit marker to the server folder",
                "If the watchdog finds the server stopped but no clean-quit marker present, it treats the stop as a crash and restarts the server automatically",
                "If the clean-quit marker is present, the watchdog recognizes the intentional stop and leaves the server down"
            ])

            GuideCallout(style: .note, text: "The watchdog runs via macOS launchd, so it continues monitoring even when the Minecraft Server Controller app is not open on screen.")

            InAppBox(items: [
                "Preferences \u{2192} Watchdog: enable and configure crash recovery per server.",
                "Restart delay: how long the watchdog waits before restarting after detecting a crash. Default is 30 seconds to let the system settle.",
                "Watchdog activity appears in the console log tagged [Watchdog] so you can see when it took action.",
                "To stop a server and keep it stopped: always use the Stop button in MSC or the /stop command. These write the clean-quit marker."
            ])

            GuideCallout(style: .warning, text: "Don\u{2019}t stop your server by killing the process in Activity Monitor or Terminal. This bypasses the clean-quit marker, and the watchdog will restart the server immediately \u{2014} which is probably not what you intended.")

            GuideCallout(style: .tip, text: "Enable the watchdog any time you\u{2019}re leaving your server running overnight or while away from your Mac. It\u{2019}s especially valuable if you have players who rely on the server being available without you monitoring it constantly.")

            AdvancedSection(content: """
The launchd agent is a lightweight plist that macOS loads on login. It polls at a configurable interval (default: 60 seconds). The interval is intentionally not too short \u{2014} a rapid restart loop after a repeating crash could hammer disk I/O unnecessarily.

The clean-quit cookie is a file written to the server\u{2019}s directory when MSC initiates an intentional stop, and removed when the server is started again. The watchdog reads this file before deciding whether to restart.

If your server crashes immediately on every restart due to a bug or corrupt world, the watchdog will keep restarting it. In that case, stop the server intentionally (which writes the cookie) and investigate the console log before re-enabling the watchdog.
""")
        }
    }

    // ── Player Management ─────────────────────────────────────────────────

    var playerManagementContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "person.2.fill",
                title: "Player Management",
                subtitle: "Control who can connect, what they can do, and how they appear in the app.",
                color: .teal
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Your server is like a private club. The allowlist is the guest list \u{2014} only people on it can get in. Ops are the staff \u{2014} they can do things regular members can\u{2019}t. Banning is a permanent removal from the premises. These are independent systems you can use in any combination."
            )

            GuideBodyText("""
**Allowlist (Whitelist)**

The allowlist restricts who can join your server. When enabled, only players whose usernames appear on the list can connect \u{2014} anyone else gets a \u{201C}Not whitelisted\u{201D} rejection.

Use this for private servers \u{2014} family servers, friend groups, or any server where you don\u{2019}t want strangers joining. It\u{2019}s disabled by default.

**Operators (Ops)**

Ops are trusted players with elevated command permissions. They can use commands regular players cannot \u{2014} like /gamemode, /tp, /give, and player management commands. Java servers support four op levels:
""")

            BulletList(items: [
                "Level 1: bypass spawn protection only",
                "Level 2: gameplay commands (/give, /tp, /gamemode, /time, /weather, etc.)",
                "Level 3: player management commands (/kick, /ban, /whitelist)",
                "Level 4: full server control including /stop and /op \u{2014} use sparingly"
            ])

            GuideBodyText("""
**Banning**

Banning prevents a specific player from connecting even if they\u{2019}re on the allowlist. Java servers track bans by UUID (account ID) so name changes don\u{2019}t bypass them. Bedrock servers track by XUID.
""")

            InAppBox(items: [
                "Players tab: see all online players with their head renders, health, and status. Right-click a player (or use the action menu) for op, deop, kick, ban, message, teleport, and whitelist actions.",
                "Overview \u{2192} Players strip: scrolling head grid of online players. Tap a head to feature the player; tap their character render for quick actions.",
                "Overview \u{2192} Players strip: right-click a head to hide a player from the overview grid. Right-click empty space to show hidden players again.",
                "Edit Server \u{2192} Players tab: manage the allowlist and op list without typing commands in the console.",
                "Bedrock players joining via Geyser appear with a period prefix (e.g. .PlayerName) \u{2014} this is Floodgate\u{2019}s identifier so they can be distinguished from Java Edition players."
            ])

            GuideCallout(style: .tip, text: "For a typical friends server: enable the allowlist and add each friend\u{2019}s username, set yourself and at least one trusted friend as ops (level 2 is usually enough), and leave online mode on.")

            AdvancedSection(content: """
Java servers store player data in these files inside the server directory:
  whitelist.json \u{2014} the allowlist by UUID and username
  ops.json \u{2014} operator list with UUIDs and op levels
  banned-players.json \u{2014} banned players by UUID
  banned-ips.json \u{2014} IP-based bans

Bedrock servers use:
  allowlist.json \u{2014} the allowlist with platform XUIDs
  permissions.json \u{2014} operator and visitor permission levels

Changes made in the Players tab are written directly to these files. Paper reloads allowlist and ops changes dynamically \u{2014} they take effect on a running server without a restart.

Floodgate assigns Bedrock players a Java UUID starting with 00000000-0000-0000-0009-... which is how whitelist.json and ops.json can track them even though they don\u{2019}t have Java Edition accounts.
""")
        }
    }

}

// MARK: - Preview

#Preview {
    ServerHandbookView()
        .environmentObject(AppViewModel())
}
