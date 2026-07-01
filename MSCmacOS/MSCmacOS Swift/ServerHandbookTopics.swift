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

The app supports a wide range of server types as first-class citizens:

**Standard Java servers \u{2014} Paper, Purpur, and Vanilla.** Great for plugin-heavy setups, Bedrock cross-play via Geyser, and Java Edition players. Players connect with no extra setup on their end.

**Modded Java servers \u{2014} Fabric, NeoForge, and Forge.** For mods that add new blocks, items, dimensions, and gameplay systems. Every player must install the same mod loader and mods to connect.

**Bedrock Dedicated Server (BDS).** The native server for mobile, console, and Windows 10/11 players. Runs in a built-in lightweight VM — no extra software required. Cross-play with all Bedrock platforms is built in.
""")

            InAppBox(items: [
                "Start and stop any server type with a single click \u{2014} Java Standard, Modded, and Bedrock",
                "Watch the live console \u{2014} see exactly what your server is doing",
                "Manage multiple servers from one window \u{2014} mix any combination of server types",
                "Browse and download mods from Modrinth; browse and download plugins from the Components tab",
                "Configure ports, RAM, cross-play, and Playit.gg tunneling",
                "Handle backups, world conversions, and server transfers",
                "Manage world slots, resource packs, and player allowlists",
                "Monitor live performance \u{2014} TPS, CPU, RAM, player health, and in-game time",
                "Remote control from iOS via MSC Remote (companion app)",
                "Watchdog crash recovery keeps your server running overnight"
            ])

            GuideCallout(style: .tip, text: "Starting fresh? Check the Getting Started section for step-by-step checklists: Your First Java Server (Paper), Your First Modded Server (Fabric/NeoForge), or Your First Bedrock Server. Come back to other topics for deeper explanations of anything along the way.")

            AdvancedSection(content: """
Under the hood, Standard Java servers (Paper/Purpur/Vanilla) run a shell command like:
  java -Xms2G -Xmx4G -jar paper.jar

Fabric modded servers launch from a generated launcher JAR:
  java -jar fabric-server-launch.jar

NeoForge and Forge modded servers use a generated shell script that passes an @args file to Java — the installer sets all of this up, and MSC runs the resulting script automatically.

Bedrock servers run in a lightweight Linux VM bundled with the app — no Docker or external software needed. The app manages the VM lifecycle entirely — start, stop, console streaming, world file sharing — so you never need to open any external tool.

All server types are fully managed. The complexity lives inside the app, not in front of you.
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
Paper is the most popular server in the **Standard Java** family. Standard servers support plugins \u{2014} server-side extensions that players don\u{2019}t need to install anything to benefit from.

**Vanilla Minecraft** is the official server from Mojang. It works, but it has limited configuration options and no plugin support.

**Paper** is a "fork" \u{2014} a modified version of the vanilla server that keeps gameplay the same but adds:
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
The Standard Java server family tree:

  CraftBukkit \u{2192} Spigot \u{2192} Paper \u{2192} Pufferfish \u{2192} Purpur

Each adds more features and performance improvements on top of the last. Vanilla sits outside this tree \u{2014} it\u{2019}s the official Mojang server with no third-party modifications.

Paper is the sweet spot for most home servers. Purpur is for server operators who want hundreds of extra configuration toggles on top of Paper\u{2019}s foundation. Vanilla is for purists who want zero modifications.

The Standard family is entirely separate from Modded servers (Fabric, NeoForge, Forge). Those use a different loading system and a different add-on ecosystem (mods instead of plugins). See the Modded Servers section of this handbook for details.
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
                "No Java installation needed for Bedrock servers \u{2014} the built-in VM provides the runtime."
            ])
        }
    }

    // ── How Bedrock Runs ──────────────────────────────────────────────────

    var dockerContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "memorychip",
                title: "How Bedrock Runs",
                subtitle: "How the app runs Bedrock Dedicated Server without Docker or any external software.",
                color: .green
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Mojang only made BDS for Linux \u{2014} there's no Mac version. MSC bundles a tiny lightweight Linux virtual machine that runs inside your Mac. The BDS server thinks it's running on a Linux machine, which it is \u{2014} just one that lives invisibly inside the app."
            )

            GuideBodyText("""
**Why a VM?** Mojang has never released a native macOS binary for Bedrock Dedicated Server. The official BDS binary is Linux-only. MSC bundles a minimal Linux VM (using Apple's built-in Virtualization framework) that runs the Linux BDS binary transparently. No Docker, no external downloads, no extra installs required.
""")

            GuideCallout(style: .tip, text: "The built-in VM starts and stops automatically with the server. You never need to open or interact with any external tool — just click Start and Stop like any other server type.")

            InAppBox(items: [
                "BDS is downloaded automatically on first start and cached in your server folder.",
                "VM start/stop is wired to the Start/Stop buttons \u{2014} same UI as Java servers.",
                "World data is stored in your server folder and shared with the VM. Your data is never locked inside the VM image.",
                "Console output streams from the VM in real-time, just like Java.",
                "Updating BDS: use the version selector in the Components tab — the app downloads and installs the new version automatically."
            ])

            AdvancedSection(content: """
Under the hood, MSC uses Apple's Virtualization.framework to boot a compact Linux guest (a custom minimal kernel + initramfs, ~11 MB bundled with the app). The BDS binary lives in your server directory and is shared into the VM via virtio-fs — no image to pull, no layer cache.

Bedrock UDP port 19132 is forwarded from the host into the VM via a tiny UDP relay so LAN clients and Playit.gg tunnels reach the server transparently. Commands typed in the console go to BDS stdin over the VM serial console.
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
**JAR** stands for Java ARchive. It\u{2019}s a bundle of compiled code \u{2014} essentially the server software in a single file.

**Java** is the runtime that executes that code. It\u{2019}s not specific to Minecraft; it\u{2019}s a general-purpose programming platform that millions of programs use.

The launch command varies by server type:

**Standard servers (Paper/Purpur/Vanilla):**
`java -Xms2G -Xmx4G -jar paper.jar`

**Fabric modded servers** use a launcher JAR the Fabric installer generates:
`java -jar fabric-server-launch.jar`

**NeoForge/Forge modded servers** use a shell script the installer generates. It passes a long @args file to Java with remapping flags and a classpath. MSC reads and runs this script for you \u{2014} you never have to touch it directly.

Note: JAR files and Java are only needed for Java servers. Bedrock servers use the built-in VM instead.
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

            GuideBodyText("RAM settings apply to Java servers only \u{2014} Bedrock servers run in the built-in VM and manage their own memory. For Java servers, here are practical starting points:")

            RamGuideTable()

            GuideBodyText("""
**Modded servers need significantly more RAM.** The table above covers Standard servers (Paper, Purpur, Vanilla). Fabric and NeoForge/Forge packs load many more systems at startup and keep more data in memory during play.

Rough modded starting points:
\u{2022} **Small Fabric pack (10\u{2013}30 mods):** 3\u{2013}5 GB max
\u{2022} **Medium pack (30\u{2013}100 mods):** 5\u{2013}8 GB max
\u{2022} **Large NeoForge/Forge pack (100+ mods):** 8\u{2013}12 GB max

Check the modpack\u{2019}s documentation \u{2014} most published modpacks include server RAM recommendations.
""")

            InAppBox(items: [
                "Manage Servers \u{2192} Edit \u{2192} General tab: Min RAM and Max RAM sliders.",
                "These map to Java's -Xms (minimum heap) and -Xmx (maximum heap) flags.",
                "Setting min = max reduces GC pauses at the cost of memory always being reserved.",
                "TPS (ticks per second) in the console overview shows server health. 20 TPS = smooth. Below 15 = noticeable lag."
            ])

            GuideCallout(style: .tip, text: "Leave at least 2\u{2013}3 GB of RAM free for macOS and other apps. For a typical Paper server, 4\u{2013}6 GB is the sweet spot. For modded servers, start with the modpack\u{2019}s recommendation and adjust based on TPS and GC log entries.")

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

            GuideCallout(style: .warning, text: "Geyser and Floodgate only work on Standard Java servers (Paper, Purpur). Modded servers (Fabric, NeoForge, Forge) cannot use Geyser. Bedrock clients would need to install the same mods as Java players, which isn\u{2019}t possible \u{2014} Bedrock Edition has no mod-loading support.")

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

For Bedrock servers, world data is stored in a `worlds/` folder inside your server directory and is shared with the VM automatically via a direct file share.

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
                    ChecklistStep(number: 3, title: "Download Paper templates", detail: "Open Archives in the sidebar \u{2192} Download latest Paper. This saves the newest Paper build as a reusable template.")
                    ChecklistStep(number: 4, title: "(Optional) Download plugin templates", detail: "If you want Bedrock cross-play, open Archives \u{2192} Download latest Geyser and Download latest Floodgate.")
                }
            }

            Group {
                Text("Phase 2 \u{2014} Create Your Server")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(number: 5, title: "Add a new server", detail: "Click Manage Servers \u{2192} Create New Server. Choose Standard \u{2192} Paper. Give it a name, choose your Paper template, set RAM (2 GB min / 4 GB max is a good start), and enable Bedrock Cross-play if needed.")
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

            GuideCallout(style: .tip, text: "You don't need to memorize this. Work through it step by step. See the \"How Bedrock Runs\" topic in the Bedrock section if you want to understand how MSC runs BDS natively.")

            Group {
                Text("Phase 1 \u{2014} Initial Setup")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 1,
                        title: "Open the app",
                        detail: "Launch Minecraft Server Controller. Bedrock runs in a built-in VM — no Docker, no extra installs. The app is self-contained."
                    )
                    ChecklistStep(
                        number: 2,
                        title: "Run the Setup Wizard",
                        detail: "On first launch, the Setup Wizard appears. Choose a Servers Root folder (~/MinecraftServers is fine). Select Bedrock as your server type. No Java path needed — no extra installs needed."
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
                        number: 5,
                        title: "Start the server",
                        detail: "Click Start. On first launch, the app downloads BDS automatically \u{2014} this may take a moment depending on your internet speed. Watch the console. When you see \"Server started\", it's ready."
                    )
                    ChecklistStep(
                        number: 6,
                        title: "Test local connection",
                        detail: "Open Minecraft on your phone, tablet, or another device on your home network. Go to Servers \u{2192} Add Server. Enter your Mac's local IP (e.g. 192.168.1.x) and port 19132. You should be able to connect."
                    )
                    ChecklistStep(
                        number: 7,
                        title: "Enable external access",
                        detail: "Friends outside your home need one of two approaches \u{2014} (A) Port Forwarding: forward UDP port 19132 on your router to your Mac\u{2019}s local IP. Bedrock requires UDP, not TCP \u{2014} forwarding TCP 19132 will not work. Or (B) Playit.gg Tunneling: no router access needed; no extra installs needed. Enable the tunnel in Edit Server \u{2192} Settings \u{2192} Network. See Connection & Access for full guides on both."
                    )
                    ChecklistStep(
                        number: 8,
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
                        number: 9,
                        title: "Create a backup",
                        detail: "Once everything works, open Server Details → Worlds and create your first backup. Label it \"initial setup\" or similar."
                    )
                    ChecklistStep(
                        number: 10,
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
The **Files tab** gives you a full view of everything on disk inside your server's directory. For Java servers this includes your Paper JAR, plugins folder, world data, and all config files. For Bedrock servers it shows the server directory shared with the VM — BDS binary, worlds folder, config files, and more.

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
For Bedrock servers, all files shown are on your Mac's filesystem (your server's host directory). The VM accesses this directory via a direct file share — no container layer. Edits you make here while the server is stopped take effect the next time the server starts.

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
**Playit.gg** is a free tunneling service for game servers. Instead of requiring your router to accept inbound connections, the app runs a small native `playitd` agent that connects outbound to Playit.gg\u{2019}s relay servers. Playit.gg gives you a stable public address \u{2014} like abc123.jth.mc.ply.gg \u{2014} that routes traffic back through the relay to your server.

**Why this matters:**
""")

            BulletList(items: [
                "No router configuration needed \u{2014} the agent makes outbound connections only",
                "Works behind CGNAT (some mobile and cable ISPs) where port forwarding is impossible",
                "Works on networks where you don\u{2019}t have router access \u{2014} dorms, apartments, offices",
                "The address Playit.gg gives you is stable and doesn\u{2019}t change when your home IP changes"
            ])

            GuideCallout(style: .tip, text: "Playit.gg requires no extra software. The app downloads and manages the native playit agent automatically.")

            GuideBodyText("""
**Tradeoffs vs. port forwarding:**
""")

            BulletList(items: [
                "Latency: game traffic passes through Playit.gg\u{2019}s relay servers, adding roughly 10\u{2013}50 ms. For most players this is unnoticeable.",
                "Account required: you need a free Playit.gg account (no credit card). One-time setup takes about 5 minutes.",
                "No extra installs: the app downloads and manages the native playit agent automatically.",
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
The app runs the Playit.gg agent as a native background process alongside your Minecraft server. One agent (one secret key) can tunnel multiple ports \u{2014} your Java port and Bedrock/Geyser port can both go through the same agent.

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
                "Bedrock servers: BDS is downloaded automatically on first start after import if not already present."
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

    // ── Standard vs Modded ────────────────────────────────────────────────

    var standardVsModdedContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "tray.2.fill",
                title: "Standard vs Modded Servers",
                subtitle: "The two main categories of Java server and the key difference between them.",
                color: .orange
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Standard Java servers are like a restaurant \u{2014} the kitchen adds toppings and sauces (plugins) that diners don\u{2019}t need to know about. Modded servers are like a potluck \u{2014} everyone must bring the exact same dish from the same recipe. If one person shows up with a different dish, they don\u{2019}t fit at the table."
            )

            GuideBodyText("""
All Java servers fall into one of two categories. The choice shapes everything: who can connect, what add-ons work, and how much RAM you need.

**Standard servers \u{2014} Paper, Purpur, and Vanilla**
Run plugins: server-side extensions that add features without requiring players to install anything. Your friends connect with normal Minecraft, no changes needed.

**Modded servers \u{2014} Fabric, NeoForge, and Forge**
Run mods: code that modifies the game on both the server and every client simultaneously. Every player must install the same mod loader and the same set of mods before they can connect. If their mod list doesn\u{2019}t match, they get a connection error.
""")

            BulletList(items: [
                "Plugins: server-side only. Players need no extra setup \u{2014} just vanilla Minecraft.",
                "Mods: both sides. Every player installs the same mod loader and mods.",
                "You cannot mix plugins and mods on the same server (with rare exceptions).",
                "Geyser/Floodgate (Bedrock cross-play) only works on Standard servers \u{2014} not Modded."
            ])

            GuideCallout(style: .tip, text: "Not sure which to pick? Choose Standard if your friends aren\u{2019}t technical or if you want Bedrock cross-play. Choose Modded if you want new blocks, items, dimensions, or the experience of a specific modpack.")

            InAppBox(items: [
                "Create New Server: the first step asks you to choose Standard or Modded, then select the specific server type.",
                "Standard options: Paper (recommended), Purpur (Paper with extras), Vanilla (official Mojang, no plugins).",
                "Modded options: Fabric (lightweight, fast updates), NeoForge (large ecosystem), Forge (legacy/older packs)."
            ])

            AdvancedSection(content: """
There are hybrid approaches, but they\u{2019}re advanced and not recommended for beginners:

\u{2022} Fabric has some Plugin API compatibility mods (like Polymer) that allow limited plugin-like functionality on Fabric. These are still mods, so the client requirement applies.
\u{2022} NeoForge had PluginLoader experiments historically, but the ecosystems are genuinely separate today.

For the vast majority of home servers, you pick one category and stick with it. Switching later requires creating a new server \u{2014} the world data carries over but your add-ons do not.
""")
        }
    }

    // ── Vanilla ───────────────────────────────────────────────────────────

    var vanillaContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "leaf.fill",
                title: "Vanilla Server",
                subtitle: "The official Mojang server \u{2014} pure, simple, and without any add-ons.",
                color: .orange
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Vanilla is the raw, unmodified recipe straight from Mojang\u{2019}s kitchen. No extra ingredients, no substitutions. It\u{2019}s the same experience as singleplayer, just with multiple people in the same world at the same time."
            )

            GuideBodyText("""
A **Vanilla server** runs Mojang\u{2019}s official server binary with no third-party modifications. No plugins, no mods, no performance patches. The game behaves exactly as it does in singleplayer.

**When to use Vanilla:**
""")

            BulletList(items: [
                "You want a pure, unmodified Minecraft experience for a small group",
                "You\u{2019}re testing Minecraft behavior without any interference from plugins or mods",
                "You want to match singleplayer exactly (same bugs, same quirks, same behavior)",
                "Simplicity is a priority \u{2014} fewer moving parts, fewer things to break"
            ])

            GuideBodyText("""
**What\u{2019}s missing compared to Paper:**
""")

            BulletList(items: [
                "No plugin support \u{2014} you cannot install Bukkit/Spigot/Paper plugins",
                "Fewer configuration options in server.properties (Paper exposes many extras)",
                "Slower performance under load compared to Paper\u{2019}s optimizations",
                "Slower bug fixes than the Paper team\u{2019}s rapid patching cadence"
            ])

            GuideCallout(style: .note, text: "Vanilla servers support full vanilla Java Edition clients and all vanilla gameplay features. If you later decide you want plugins, you\u{2019}d need to create a new Paper server and copy the world folder over \u{2014} the world data is compatible.")

            InAppBox(items: [
                "Create New Server \u{2192} Standard \u{2192} Vanilla.",
                "Vanilla doesn\u{2019}t need a Paper template. MSC downloads the vanilla server JAR directly from Mojang for your chosen Minecraft version.",
                "Edit Server \u{2192} JARs tab: shows the vanilla server JAR, read-only (no Update button \u{2014} version changes go through the Versions picker).",
                "No EULA accept needed \u{2014} MSC handles it automatically for Vanilla servers the same as Paper."
            ])

            AdvancedSection(content: """
The Vanilla server JAR is downloaded directly from Mojang\u{2019}s version manifest. Each Minecraft version has an exact JAR SHA1 that MSC verifies before using it.

Performance notes: Vanilla\u{2019}s chunk loading and entity processing is noticeably slower than Paper under multi-player load. For 1\u{2013}2 players casually exploring, this doesn\u{2019}t matter. For 5+ players or redstone-heavy builds, Paper\u{2019}s optimizations become meaningful.
""")
        }
    }

    // ── Purpur ────────────────────────────────────────────────────────────

    var purpurContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "crown.fill",
                title: "What is Purpur?",
                subtitle: "Paper with hundreds of extra configuration options on top.",
                color: .orange
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "If Paper is a car with a good engine and sensible controls, Purpur is the same car with a cockpit full of extra dials. Most of them start in the same position as Paper \u{2014} but now you can adjust things Paper never exposed."
            )

            GuideBodyText("""
**Purpur** is a fork of Paper (via Pufferfish) that inherits everything Paper has \u{2014} the same plugin ecosystem, the same performance improvements \u{2014} and adds hundreds of extra configuration toggles that Paper doesn\u{2019}t expose.

**All Paper plugins work on Purpur without modification.** If you\u{2019}ve been running Paper, switching to Purpur is a JAR swap, not a migration.

Examples of what Purpur adds:
""")

            BulletList(items: [
                "Per-entity behavior toggles (disable silverfish spawning, change zombie burn thresholds, set spider climb height)",
                "Per-material settings (how blocks behave in specific situations)",
                "Extra mob controls \u{2014} aggression radius, spawn caps, entity-specific damage values",
                "Spectator and creative mode tweaks beyond Paper\u{2019}s options",
                "Additional server gameplay adjustments (fall damage, hunger, sleep mechanics)"
            ])

            GuideCallout(style: .note, text: "Purpur\u{2019}s extra options are all disabled or set to Paper-equivalent defaults out of the box. You get Paper behavior unless you intentionally change something.")

            GuideCallout(style: .tip, text: "Start with Paper. Switch to Purpur if you find yourself wanting to tune something that Paper\u{2019}s configuration doesn\u{2019}t expose.")

            InAppBox(items: [
                "Create New Server \u{2192} Standard \u{2192} Purpur.",
                "Purpur uses the same JAR template system as Paper. MSC downloads Purpur builds from purpurmc.org.",
                "Purpur\u{2019}s extra settings are in purpur.yml inside the server folder (created on first run).",
                "Edit Server \u{2192} JARs tab: shows the Purpur Server JAR with an Update button."
            ])

            AdvancedSection(content: """
The Standard server family tree, with Purpur at the end:

  CraftBukkit \u{2192} Spigot \u{2192} Paper \u{2192} Pufferfish \u{2192} Purpur

Pufferfish adds CPU optimization patches on top of Paper. Purpur builds on Pufferfish and adds the configuration layer. In practice, Purpur vs. Paper performance on a small home server is negligible \u{2014} the main reason to run Purpur is the configuration options, not the performance.

Purpur maintains API compatibility with Paper plugins. Any plugin that declares compatibility with Paper (Bukkit, Spigot, or Paper API) will run on Purpur.
""")
        }
    }

    // ── Fabric ────────────────────────────────────────────────────────────

    var fabricContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "gearshape.fill",
                title: "What is Fabric?",
                subtitle: "A lightweight mod loader known for fast updates and an active ecosystem.",
                color: .indigo
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Fabric installs a minimal framework onto the Minecraft server \u{2014} like adding a thin expansion slot to a circuit board. The slot adds nothing to the game itself, but mods can plug in cleanly. Because the framework is small and makes few assumptions, it\u{2019}s easy to update when new Minecraft versions drop."
            )

            GuideBodyText("""
**Fabric** is a lightweight mod-loading framework. Unlike NeoForge, it makes minimal changes to Minecraft\u{2019}s internals, which means it\u{2019}s typically updated to support new Minecraft versions within days of release.

**Installation:** When you create a Fabric server, MSC downloads the Fabric installer and runs it automatically for your chosen Minecraft + loader version. The result is a `fabric-server-launch.jar` in your server folder. Installation takes about 10\u{2013}15 seconds.

**Mods** live in the `mods/` folder inside your server directory. The Mods tab in Edit Server shows all installed mods with Delete buttons. Use the Mod Browser in the Components tab to search Modrinth and download mods directly.
""")

            GuideCallout(style: .note, text: "Many Fabric mods depend on Fabric API \u{2014} a shared library that provides common utilities. MSC adds Fabric API automatically when you create a Fabric server.")

            GuideBodyText("""
**Loader version:** Each Fabric loader version is compatible with a specific range of Minecraft versions. MSC shows available loader versions in Edit Server \u{2192} Components \u{2192} Versions. Changing the MC version or loader version re-runs the installer automatically.
""")

            GuideCallout(style: .warning, text: "Fabric has no native plugin support. Paper/Bukkit plugins will not load on a Fabric server. Every player who connects must also have Fabric and the same mods installed on their client.")

            InAppBox(items: [
                "Create New Server \u{2192} Modded \u{2192} Fabric.",
                "Components tab \u{2192} Versions: change Minecraft or Fabric loader version. MSC re-runs the installer.",
                "Components tab \u{2192} Mod Browser: search Modrinth and download mods directly into the server.",
                "Edit Server \u{2192} Mods tab: shows all installed mods with Delete buttons.",
                "Components tab \u{2192} Export: generates a client mod list so players know what to install."
            ])

            AdvancedSection(content: """
Quilt is a community fork of Fabric with additional features and a different governance model. MSC supports Quilt servers with the same setup flow as Fabric \u{2014} Create New Server \u{2192} Modded \u{2192} Quilt. Most Fabric mods are compatible with Quilt, but check the mod\u{2019}s documentation.

The Fabric loader version is different from Fabric API. The loader is the framework that loads mods at startup. Fabric API is a regular mod (JAR file) that provides shared utilities. You need both, but MSC manages them separately: the loader version is in the Versions picker, and Fabric API is a mod in your mods/ folder.
""")
        }
    }

    // ── NeoForge ──────────────────────────────────────────────────────────

    var neoforgeContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "hammer.fill",
                title: "What is NeoForge?",
                subtitle: "The modern successor to Minecraft Forge, with a large modpack ecosystem.",
                color: .indigo
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "NeoForge is like a full engine rebuild that exposes thousands of internal hooks for mod developers. It\u{2019}s more invasive than Fabric, but that depth enables mods that fundamentally change how Minecraft works \u{2014} full tech trees, magic systems, custom dimensions, and entire modpacks built around new gameplay loops."
            )

            GuideBodyText("""
**NeoForge** is the actively-maintained community fork of the original Minecraft Forge project (forked in 2023). It makes extensive changes to Minecraft\u{2019}s internals, which is what enables mods to add deep gameplay systems \u{2014} but it also means updates to new Minecraft versions take longer than Fabric (usually weeks, sometimes months).

**Installation:** NeoForge uses an installer-based setup. MSC downloads the NeoForge installer JAR and runs it automatically. The installer remaps Minecraft\u{2019}s code and generates a `libraries/` folder and a `run.sh` launch script. This process takes **30\u{2013}90 seconds** depending on download speed \u{2014} longer than Fabric, but only happens once per version.

MSC reads the generated launch script and runs it for you. You never need to interact with it directly.
""")

            GuideCallout(style: .note, text: "The first start of a NeoForge server can take 2\u{2013}3 minutes as it remaps Minecraft\u{2019}s code. Subsequent starts are normal speed. The console will show progress during this phase.")

            GuideBodyText("""
**Mods** live in the `mods/` folder. The Mods tab in Edit Server shows installed mods. Use the Mod Browser in the Components tab to search Modrinth and download compatible mods.

**Client requirement:** Every player who joins must have NeoForge at the same version installed on their Minecraft client, plus all required mods. See the Client Requirements topic for how to share this with your players.
""")

            GuideCallout(style: .tip, text: "For new servers on Minecraft 1.21+, NeoForge is the recommended choice over Forge. Most new large modpacks target NeoForge. Only choose Forge if your specific modpack requires it.")

            InAppBox(items: [
                "Create New Server \u{2192} Modded \u{2192} NeoForge.",
                "Components tab \u{2192} Versions: change NeoForge or Minecraft version. Re-runs the installer.",
                "Components tab \u{2192} Mod Browser: search and download compatible mods.",
                "Edit Server \u{2192} Mods tab: shows all installed mods.",
                "Components tab \u{2192} Export: generate a client mod list for your players."
            ])

            AdvancedSection(content: """
The NeoForge installer generates:
  libraries/        \u{2014} remapped Minecraft classes + NeoForge dependencies
  run.sh            \u{2014} shell script that builds the full classpath and launch args
  @user_jvm_args.txt \u{2014} JVM flags (MSC injects -Xms/-Xmx here)

MSC reads run.sh to extract the launch command, injects your RAM settings, and runs the server process. When you change the NeoForge version, MSC deletes the old libraries/ and re-runs the installer to rebuild them.

NeoForge loader versions look like 21.1.172 \u{2014} the first two numbers match the Minecraft minor version (21.1 = MC 1.21.1). Each MC version has many NeoForge builds; MSC\u{2019}s version picker shows all available builds from the NeoForge version manifest.
""")
        }
    }

    // ── Forge ─────────────────────────────────────────────────────────────

    var forgeContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "wrench.and.screwdriver.fill",
                title: "What is Forge?",
                subtitle: "The original Minecraft mod loader \u{2014} still used for older modpacks.",
                color: .indigo
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Forge is the original workshop where Minecraft modding was invented. NeoForge is a renovated version of the same workshop by a newer team. They use the same tools and techniques, but NeoForge gets the ongoing maintenance."
            )

            GuideBodyText("""
**Minecraft Forge** is the original server-side mod loader, with roots going back to early Minecraft versions. It built the foundation for the modded ecosystem and still has an enormous library of mods \u{2014} particularly for older Minecraft versions like 1.12.2, 1.7.10, and earlier.

In 2023, the **NeoForge** project forked from Forge to address development and governance concerns. For new servers on Minecraft 1.21 and later, NeoForge is generally the better choice. Forge remains the right option for:
""")

            BulletList(items: [
                "Modpacks that specifically require Forge (check the pack\u{2019}s documentation)",
                "Older Minecraft versions (1.20 and earlier) where Forge has better mod coverage",
                "Existing Forge servers you\u{2019}re importing into MSC"
            ])

            GuideCallout(style: .note, text: "Forge and NeoForge are not interchangeable. A modpack built for Forge requires a Forge server. A modpack built for NeoForge requires a NeoForge server. Check which loader your modpack targets before creating your server.")

            GuideBodyText("""
**Installation** uses the same process as NeoForge: MSC downloads the Forge installer, runs it to generate the `libraries/` folder and launch script, and starts the server from the generated script. First-time setup takes 30\u{2013}90 seconds.

**Client requirement:** Every player must have Forge (same version) and the same required mods installed. The client requirement works exactly the same as NeoForge.
""")

            InAppBox(items: [
                "Create New Server \u{2192} Modded \u{2192} Forge.",
                "Components tab \u{2192} Versions: change Forge or Minecraft version. Re-runs the installer.",
                "Components tab \u{2192} Mod Browser: search and download compatible mods from Modrinth.",
                "Edit Server \u{2192} Mods tab: shows all installed mods with Delete buttons."
            ])

            AdvancedSection(content: """
The Forge installer generates the same libraries/ + run.sh structure as NeoForge. MSC handles them identically.

Forge version numbers look like 1.21-51.0.33 \u{2014} the first part is the Minecraft version, the second is the Forge build number. MSC\u{2019}s version picker pulls available builds from Forge\u{2019}s Maven repository.

For very old Minecraft versions (1.12.2 and earlier), Forge is the only option \u{2014} NeoForge doesn\u{2019}t support pre-1.20 versions. These older packs may have unusual startup behaviors; the MSC startup crash diagnostics apply the same way.
""")
        }
    }

    // ── Mods & Mod Browser ────────────────────────────────────────────────

    var modsModBrowserContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "puzzlepiece.extension.fill",
                title: "Mods & the Mod Browser",
                subtitle: "Find, download, and manage mods from within the app.",
                color: .indigo
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "The Mod Browser is like an app store built into MSC. Instead of going to a website, downloading a file, and manually placing it in a folder, you search inside the app, click download, and it ends up in the right place automatically."
            )

            GuideBodyText("""
**Mods** are `.jar` files that live in your server\u{2019}s `mods/` folder. They are loaded when the server starts. Mods can add new blocks, items, dimensions, crafting systems, mobs, biomes, and fundamentally new gameplay loops.

The **Mod Browser** in the Components tab pulls from **Modrinth** \u{2014} the primary open-source mod repository with tens of thousands of mods. The browser automatically filters results to show only mods compatible with your server\u{2019}s Minecraft version and mod loader (Fabric, NeoForge, or Forge).
""")

            GuideBodyText("**Server-side vs client-side:** not all mods need to be installed on both sides.")

            BulletList(items: [
                "Required on both sides: the most common category. Adds blocks, items, or gameplay that both the server and client must understand. Everyone installs these.",
                "Server-side only: the server runs these, but clients don\u{2019}t need them. Examples: Spark (performance profiler), Chunky (chunk pre-generation), LuckPerms-Fabric (permissions).",
                "Client-side only: visual or audio mods that the server doesn\u{2019}t run. Not relevant for server management.",
                "MSC shows a badge on each mod in the browser indicating which type it is."
            ])

            GuideBodyText("""
**Modpack import:** MSC can import a Modrinth modpack file (`.mrpack`). The import wizard automatically downloads and installs all server-compatible mods from the pack.

**Update detection:** MSC compares the hash of each installed mod JAR against the latest version on Modrinth. If an update is available, it appears in the Components tab.

**Export for clients:** Once you\u{2019}ve set up your mods, use the Export button in the Components tab to generate a list of required mods with Modrinth links \u{2014} or a ZIP of the JAR files themselves. Share this with your players so they know exactly what to install.
""")

            InAppBox(items: [
                "Edit Server \u{2192} Components tab \u{2192} Mod Browser: available for Fabric, NeoForge, and Forge servers only.",
                "Search by name, or browse by category. Filter by server-side / client-side badge.",
                "Click a mod to see details, version history, and a Download button.",
                "Downloaded mods appear immediately in the Mods tab. No server restart needed to install \u{2014} but the mod only loads on next server start.",
                "Mods tab: shows installed mods. Click Delete to remove a mod (requires server restart to take effect).",
                "Components tab \u{2192} Export: generate client mod list or ZIP."
            ])

            GuideCallout(style: .note, text: "The Mod Browser is not available for Standard servers (Paper, Purpur, Vanilla). Those servers use the Plugin tab instead. The two ecosystems \u{2014} plugins and mods \u{2014} are completely separate.")

            AdvancedSection(content: """
MSC uses Modrinth\u{2019}s v2 API for mod search. Version filtering uses both game_versions and loaders parameters to show only mods the server can actually run.

Update detection works by computing the SHA512 hash of each installed JAR and comparing it to the hash of the latest version file on Modrinth. This is accurate for mods downloaded through MSC; manually-placed JARs may not have matching hashes.

.mrpack files are ZIP archives containing a modrinth.index.json with a manifest of mods (download URLs + SHA512 hashes) and an optional overrides/ folder with extra files. MSC reads the manifest, downloads mods marked as server or both, verifies hashes, and places them in the mods/ folder.
""")
        }
    }

    // ── Client Requirements ───────────────────────────────────────────────

    var clientRequirementsModdedContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "person.badge.key.fill",
                title: "Client Requirements",
                subtitle: "Why every player needs the same mods \u{2014} and how to make that easy.",
                color: .indigo
            )

            AnalogyBox(
                title: "Think of it like this",
                text: "Joining a modded server is like joining a book club where everyone must read the same edition of the same book. If one person shows up with a different edition \u{2014} missing chapters, renamed sections \u{2014} the conversation doesn\u{2019}t line up. The server enforces this by checking what every client has before letting them in."
            )

            GuideBodyText("""
This is the most important practical difference between Standard and Modded servers.

**Standard servers (Paper, Purpur, Vanilla):** plugins run on the server only. Your friends connect with a completely unmodified Minecraft client \u{2014} no downloads, no setup, just the game they already have.

**Modded servers (Fabric, NeoForge, Forge):** mods run on both the server and every client simultaneously. When a player tries to connect, the server and client exchange their mod lists during the handshake. If the lists don\u{2019}t match, the player sees an error like \u{201C}Mod list mismatch\u{201D} or \u{201C}Missing mods\u{201D} and cannot connect.
""")

            GuideBodyText("**What each player needs to install:**")

            BulletList(items: [
                "The correct Minecraft version (same as the server)",
                "The same mod loader (Fabric, NeoForge, or Forge) at the same version as the server",
                "All required mods \u{2014} server-side-only mods are excluded from this requirement"
            ])

            GuideCallout(style: .warning, text: "Fabric and NeoForge mods are not interchangeable. A player with Fabric installed cannot join a NeoForge server, and vice versa. Everyone must use the same loader.")

            GuideBodyText("""
**How to share mods with your players:**

The easiest approach is to use MSC\u{2019}s **Export for clients** feature in the Components tab. This generates either:
- A list of Modrinth links so players can download mods individually
- A ZIP of the required JAR files they can drop directly into their mods/ folder

Players can also use a modpack launcher like **Prism Launcher**, **ATLauncher**, or the official **Modrinth App** to install a mod bundle with a single click if you\u{2019}ve set up a Modrinth modpack.
""")

            GuideCallout(style: .tip, text: "If setting this up for non-technical friends, a Modrinth modpack (exported from your server\u{2019}s mod list) that they install in the Modrinth App is the lowest-friction option. One click installs everything they need.")

            InAppBox(items: [
                "Edit Server \u{2192} Components tab \u{2192} Export: generate client mod list.",
                "The export lists only mods required on both sides \u{2014} server-side-only mods are automatically excluded.",
                "Players who use Prism Launcher can import the exported list as a local modpack.",
                "If a player gets a \"mod list mismatch\" error: compare their mod list to the server\u{2019}s Mods tab and identify the difference."
            ])

            AdvancedSection(content: """
Server-side-only mods are identified by their environment metadata. Fabric mods declare this in their fabric.mod.json: "environment": "server". NeoForge/Forge mods use the @Mod annotation and declare client-side dependencies.

MSC reads this metadata for Fabric mods automatically. For NeoForge/Forge mods, it uses Modrinth\u{2019}s server_side field when the mod was downloaded through the Mod Browser.

Common server-side-only mods that do NOT need to be on clients:
\u{2022} Spark (profiler)
\u{2022} Chunky (pre-generation)
\u{2022} LuckPerms-Fabric (permissions)
\u{2022} Lithium, Ferrite Core, Krypton (performance, server-side effect only)
""")
        }
    }

    // ── Your First Modded Server ──────────────────────────────────────────

    var firstModdedServerContent: some View {
        GuideSection {
            GuideTopicHeader(
                icon: "flag.checkered",
                title: "Your First Modded Server",
                subtitle: "A step-by-step checklist for getting a Fabric or NeoForge server running.",
                color: .mint
            )

            GuideCallout(style: .tip, text: "Not sure which loader to pick? Fabric is the easier starting point: faster setup, snappier updates, and less RAM overhead. Choose NeoForge if your friends have a specific NeoForge modpack they want to play.")

            Group {
                Text("Phase 1 \u{2014} Before You Create the Server")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 1,
                        title: "Install Java 21",
                        detail: "Modded servers require Java, same as Standard Java servers. Download Temurin 21 from adoptium.net. Verify it in Preferences \u{2192} Check for Java."
                    )
                    ChecklistStep(
                        number: 2,
                        title: "Decide: Fabric or NeoForge?",
                        detail: "Fabric: simpler, faster to set up, lighter RAM usage, great ecosystem. NeoForge: larger ecosystem, required for most big modpacks (1.21+). If you have a specific modpack in mind, check which loader it requires \u{2014} the pack page will say."
                    )
                    ChecklistStep(
                        number: 3,
                        title: "(Optional) Find your modpack",
                        detail: "Browse modrinth.com for modpacks. Filter by server-side support. Note the Minecraft version and loader. You\u{2019}ll need this information when creating the server."
                    )
                }
            }

            Group {
                Text("Phase 2 \u{2014} Create the Server")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 4,
                        title: "Create a new server",
                        detail: "Click Manage Servers \u{2192} Create New Server \u{2192} Modded. Choose Fabric or NeoForge, then select your Minecraft version and loader version. Set RAM: at least 4 GB min / 6 GB max for a small Fabric pack; 6 GB min / 10 GB max for a NeoForge pack."
                    )
                    ChecklistStep(
                        number: 5,
                        title: "Wait for installation",
                        detail: "Fabric installs in about 10\u{2013}15 seconds. NeoForge takes 30\u{2013}90 seconds \u{2014} it\u{2019}s downloading and remapping Minecraft\u{2019}s code. The console shows progress. Don\u{2019}t interrupt it."
                    )
                    ChecklistStep(
                        number: 6,
                        title: "(Optional) Import a modpack",
                        detail: "If you have a .mrpack file: in the Components tab, use Import Modpack to install all server-compatible mods automatically. If installing mods manually, continue to Phase 3."
                    )
                }
            }

            Group {
                Text("Phase 3 \u{2014} Install Mods")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 7,
                        title: "Open the Mod Browser",
                        detail: "Edit Server \u{2192} Components tab \u{2192} Mod Browser. Search for mods by name. The browser only shows mods compatible with your server\u{2019}s MC version and loader. Click Download to add a mod."
                    )
                    ChecklistStep(
                        number: 8,
                        title: "Check Fabric API (Fabric servers only)",
                        detail: "Most Fabric mods depend on Fabric API. MSC adds it automatically, but verify it\u{2019}s in the Mods tab. If it\u{2019}s missing, search \u{201C}Fabric API\u{201D} in the Mod Browser and download it."
                    )
                    ChecklistStep(
                        number: 9,
                        title: "Start the server once to test",
                        detail: "Click Start. The server loads all mods at startup \u{2014} watch the console for errors. A successful Fabric start ends with \u{201C}Done!\u{201D}. NeoForge takes longer on first start due to remapping; progress shows in the console. Stop the server after confirming it starts cleanly."
                    )
                }
            }

            Group {
                Text("Phase 4 \u{2014} Set Up Your Players")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 10,
                        title: "Export the client mod list",
                        detail: "Edit Server \u{2192} Components tab \u{2192} Export. This generates a list of required mods. Share it with your players. Each player needs to install the same Minecraft version, same loader, and the same mods."
                    )
                    ChecklistStep(
                        number: 11,
                        title: "Have each player install the mods",
                        detail: "Easiest: point them to Prism Launcher or the Modrinth App and import the mod list. Manual: they download each mod JAR and place it in their .minecraft/mods folder. Each player must also have the correct mod loader installed (Fabric Installer or NeoForge Installer from their respective websites)."
                    )
                }
            }

            Group {
                Text("Phase 5 \u{2014} Go Live")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ChecklistStep(
                        number: 12,
                        title: "Set up external access",
                        detail: "Same as a Standard server: port forwarding (TCP 25565 on your router) or Playit.gg tunneling (Edit Server \u{2192} Settings \u{2192} Network). See Connection & Access in this handbook."
                    )
                    ChecklistStep(
                        number: 13,
                        title: "Test with one player first",
                        detail: "Have one friend test the connection before inviting everyone. Confirm they can load into the world and that the mods are working. A mod mismatch shows as an error during the connection handshake \u{2014} compare the Mods tab with what the player has installed."
                    )
                    ChecklistStep(
                        number: 14,
                        title: "Create a first backup",
                        detail: "Once everything works, open Server Details \u{2192} Worlds and create your first backup. Modded worlds can be harder to recover from corruption, so back up before installing new mods or updating."
                    )
                }
            }

            GuideCallout(style: .note, text: "Congratulations! Modded servers take more setup than Standard servers, but the result is a much richer gameplay experience. Check the Mods & Mod Browser and Client Requirements topics in this handbook whenever you need more detail on any step.")
        }
    }

}

// MARK: - Preview

#Preview {
    ServerHandbookView()
        .environmentObject(AppViewModel())
}
