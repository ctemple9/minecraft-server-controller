//
//  WelcomeGuideTopics.swift
//  MinecraftServerController
//

import SwiftUI

// MARK: - Topic Content Views

extension WelcomeGuideView {

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
                "Configure ports, RAM (Java), plugins (Java), and cross-play settings",
                "Handle backups so you can safely experiment",
                "Manage world slots, resource packs, and player allowlists",
                "Remote control from iOS via MSC Remote (companion app)"
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
                title: "Ports, Port Forwarding & DuckDNS",
                subtitle: "How your friends outside your house reach your server.",
                color: .blue
            )

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

            GuideCallout(style: .warning, text: "This feature requires a dedicated alt Xbox account, not your personal one. The password is stored locally for the broadcast tool to use. Never use your main Microsoft account.")

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

    // ── Bedrock Connect ───────────────────────────────────────────────────

    var bedrockConnectContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "gamecontroller.fill",
                title: "Bedrock Connect",
                subtitle: "Let PlayStation, Switch, and mobile players join using the Featured Servers menu.",
                color: .purple
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Consoles like PlayStation and Nintendo Switch can't add custom servers directly in Minecraft. Bedrock Connect tricks the console into thinking your server is an official Featured Server. It's like a decoy entrance that secretly leads to your house."
            )

            GuideBodyText("""
**The problem Bedrock Connect solves:**

On PC, Bedrock players can add any server address in Settings \u{2192} Servers. But on PlayStation and Nintendo Switch, Minecraft only shows a list of approved "Featured Servers" \u{2014} you can't type in a custom address.

**Bedrock Connect** is a DNS-based redirect tool. When enabled, it intercepts the request for the official Featured Servers list and replaces it with your own servers. Players on consoles see your server in the Featured Servers section and can join from there.
""")

            GuideCallout(style: .warning, text: "Bedrock Connect requires changing the DNS settings on the player's console or router to point at your Mac. This is a slightly advanced step that requires coordination with the player who wants to join.")

            GuideBodyText("""
**What you need:**
- Your Mac must be on the same network as the console, OR you must set up DNS routing through a VPN or external DNS
- Bedrock Connect JAR downloaded and configured
- Your Geyser/Bedrock port must be reachable from the console
""")

            InAppBox(items: [
                "Bedrock Connect is a global service \u{2014} one instance serves all configured servers at once, not per-server.",
                "Manage the JAR in the Components tab and the global service settings from the Bedrock Connect section in the sidebar.",
                "The app auto-generates a servers.json file from all your configured servers with Bedrock ports.",
                "Log output tagged [BedrockConnect] appears in the console when it's running.",
                "The JAR is managed through the app's JAR library alongside the Xbox Broadcast JAR."
            ])

            GuideCallout(style: .note, text: "Bedrock Connect is best for situations where you're hosting a regular gaming session with console friends who are on your local network or a known VPN. It's more setup overhead than Xbox Broadcast but covers PlayStation and Switch which Xbox Broadcast doesn't.")

            AdvancedSection(content: """
Bedrock Connect works by running a local DNS server on your Mac. When a console's DNS is pointed at your Mac:

1. The console requests the Featured Servers list from Mojang's DNS
2. Bedrock Connect intercepts that request
3. It returns your servers.json instead
4. The console displays your servers in the Featured Servers tab

The DNS interception only affects Minecraft-specific DNS lookups \u{2014} regular internet traffic is unaffected.

You can find the Bedrock Connect open-source project at:
github.com/Pugmatt/BedrockConnect
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

            GuideCallout(style: .note, text: "MSC Remote works over your local network by default. To access it away from home, you'll need a VPN (like Tailscale) or a tunneling solution to reach your Mac remotely.")

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
                    ChecklistStep(number: 10, title: "Set up port forwarding (for external players)", detail: "Log into your router and forward TCP port 25565 to your Mac's local IP. If using Geyser, also forward UDP port 19132. See the Ports & DuckDNS topic for details.")
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
                        title: "Set up UDP port forwarding (for external players)",
                        detail: "Log into your router and forward UDP port 19132 to your Mac's local IP. Important: Bedrock uses UDP, not TCP. If you forward TCP 19132, it will not work."
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

}

// MARK: - Preview

#Preview {
    WelcomeGuideView()
        .environmentObject(AppViewModel())
}
