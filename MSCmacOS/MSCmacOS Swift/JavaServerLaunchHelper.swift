// JavaServerLaunchHelper.swift
// MinecraftServerController

import Foundation

/// Fully resolved parameters for a Java Minecraft server launch.
/// Shared between `JavaServerBackend` (in-app process) and `HeadlessScriptGenerator`
/// (shell-script output) so the two can never drift.
struct JavaServerLaunchConfig {
    /// P7.7-normalized java executable. Absolute path or bare command (e.g. "java").
    let javaPath: String
    /// JVM flags in launch order: -Xms/-Xmx, sandbox-suppress, extra flags.
    let jvmFlags: [String]
    /// Non-nil for Forge/NeoForge: installer-generated args file relative to the server dir.
    /// Launch is `@<file> nogui`; nil means `-jar <jar> --nogui`.
    let neoForgeArgsFile: String?
    /// JAR basename (e.g. "paper-1.20.1-196.jar"). Ignored when `neoForgeArgsFile != nil`.
    let jarName: String
}

enum JavaServerLaunchHelper {

    static func resolve(
        config: ConfigServer,
        appConfig: AppConfig,
        serverDirURL: URL,
        minRamGB: Int,
        maxRamGB: Int,
        findNeoForgeArgsFile: (URL, String?) -> String? =
            { NeoForgeInstaller.findArgsFile(in: $0, specificVersion: $1) },
        findForgeArgsFile: (URL, String?, String?) -> String? =
            { ForgeInstaller.findArgsFile(in: $0, mcVersion: $1, forgeVersion: $2) }
    ) -> JavaServerLaunchConfig {

        // 1. Normalize java path (P7.7): JAVA_HOME dir → bin/java; bare command stays.
        let rawJava = appConfig.javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRaw = rawJava.isEmpty ? "java" : rawJava
        let normalizedJava = JavaRuntimeManager.normalizedJavaExecutablePath(effectiveRaw).path ?? effectiveRaw

        // 2. JVM flags — must stay byte-identical to ServerProcessManager.startServer.
        var flags: [String] = [
            "-Xms\(minRamGB)G",
            "-Xmx\(maxRamGB)G",
            "-Djna.nosys=true",
            "-Djna.nounpack=true",
            "-Djline.terminal=dumb",
            "-Dio.netty.noUnsafe=true",
        ]
        let extra = appConfig.extraFlags.trimmingCharacters(in: .whitespaces)
        if !extra.isEmpty {
            flags += extra.split { $0.isWhitespace }.map(String.init)
        }

        // 3. Flavor-specific args file (Forge/NeoForge) or jar (everything else).
        let neoForgeArgsFile: String?
        switch config.javaFlavor {
        case .neoforge:
            neoForgeArgsFile = findNeoForgeArgsFile(serverDirURL, config.loaderVersion)
        case .forge:
            neoForgeArgsFile = findForgeArgsFile(serverDirURL, config.minecraftVersion, config.loaderVersion)
        default:
            neoForgeArgsFile = nil
        }

        // 4. JAR basename for paper/fabric/vanilla/quilt.
        let rawJar = config.paperJarPath
        let jarName: String
        if rawJar.isEmpty {
            jarName = "paper.jar"
        } else {
            let url = URL(fileURLWithPath: (rawJar as NSString).expandingTildeInPath)
            jarName = url.lastPathComponent.isEmpty ? "paper.jar" : url.lastPathComponent
        }

        return JavaServerLaunchConfig(
            javaPath: normalizedJava,
            jvmFlags: flags,
            neoForgeArgsFile: neoForgeArgsFile,
            jarName: jarName
        )
    }
}
