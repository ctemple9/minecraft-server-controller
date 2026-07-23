//
//  JavaInstaller.swift
//  MinecraftServerController
//
//  Downloads an Adoptium (Eclipse Temurin) JDK installer and hands it to macOS's
//  Installer so the user can click through the install without leaving the app.
//
//  The choice is framed in *Minecraft* terms rather than Java terms: a first-time
//  user rarely knows "Java 17 vs 21", but does know roughly which Minecraft version
//  they want to run. `JavaInstallOption` maps each installable major to the Minecraft
//  versions it covers so the picker can guide that decision. See `JavaInstallerSheet`
//  for the UI and `JavaRuntimeManager` for the detection/compatibility half.
//

import SwiftUI

/// A Java major version MSC can install via Adoptium Temurin, paired with the
/// Minecraft versions it targets so the picker reads in terms the user knows.
struct JavaInstallOption: Identifiable, Hashable, Sendable {
    let major: Int
    let title: String            // e.g. "Java 21"
    let minecraftRange: String   // e.g. "Minecraft 1.20.5 / 1.21 and newer"
    let isRecommended: Bool

    var id: Int { major }
}

enum JavaInstaller {

    /// The Minecraft-relevant install options, newest first. Java 8 / 17 / 21 / 25 are
    /// the majors that actually matter for Minecraft servers; offering the full Adoptium
    /// list (11, 16, 18, 19, 20, …) would be noise, not a real decision.
    ///
    /// Note the version boundary: Minecraft moved to a year-based scheme in 2026, and
    /// 26.1 is the first release to require Java 25. Anything still on the classic
    /// "1.21.x" numbering runs on Java 21.
    static let minecraftInstallOptions: [JavaInstallOption] = [
        JavaInstallOption(major: 25, title: "Java 25",
                          minecraftRange: "Minecraft 26.1 (latest) and newer", isRecommended: true),
        JavaInstallOption(major: 21, title: "Java 21",
                          minecraftRange: "Minecraft 1.20.5 – 1.21.x", isRecommended: false),
        JavaInstallOption(major: 17, title: "Java 17",
                          minecraftRange: "Minecraft 1.17 – 1.20.4", isRecommended: false),
        JavaInstallOption(major: 8, title: "Java 8",
                          minecraftRange: "Minecraft 1.16.5 and older", isRecommended: false)
    ]

    /// The option to preselect. Mirrors `JavaRuntimeManager.requiredJavaMajor` so that,
    /// when a Minecraft version is known (e.g. from a configured server), the picker
    /// opens on the right choice; otherwise falls back to the recommended LTS.
    static func recommendedOption(forMinecraftVersion version: String? = nil) -> JavaInstallOption {
        let major = JavaRuntimeManager.requiredJavaMajor(forMinecraftVersion: version)
        return minecraftInstallOptions.first { $0.major == major }
            ?? minecraftInstallOptions.first { $0.isRecommended }
            ?? minecraftInstallOptions[0]
    }

    enum InstallError: LocalizedError {
        case noAsset
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noAsset:
                return "No Temurin installer is available for this Java version on your Mac."
            case .badResponse:
                return "Adoptium did not return a valid installer link. Try the manual download."
            }
        }
    }

    /// Resolves the Temurin `.pkg` installer URL for a given major version. Tries the
    /// Mac's native architecture first, then falls back to x64 — Java 8 has no native
    /// Apple-Silicon build and runs under Rosetta, and this also covers any gaps.
    static func installerURL(forMajor major: Int) async throws -> URL {
        #if arch(arm64)
        let architectures = ["aarch64", "x64"]
        #else
        let architectures = ["x64"]
        #endif

        var lastError: Error?
        for arch in architectures {
            let urlString = "https://api.adoptium.net/v3/assets/latest/\(major)/hotspot"
                + "?os=mac&image_type=jdk&vendor=eclipse&architecture=\(arch)"
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let assets = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    lastError = InstallError.badResponse
                    continue
                }
                if let first = assets.first,
                   let binary = first["binary"] as? [String: Any],
                   let installer = binary["installer"] as? [String: Any],
                   let link = installer["link"] as? String,
                   let pkgURL = URL(string: link) {
                    return pkgURL
                }
                // Empty asset array for this arch — try the next one.
            } catch {
                lastError = error
            }
        }
        throw lastError ?? InstallError.noAsset
    }

    /// Downloads the Temurin installer for `major` into the user's Downloads folder
    /// (the intuitive place to find a downloaded installer) and returns its local URL.
    /// Falls back to the temp directory if Downloads can't be resolved. The caller
    /// opens it (on the main actor, via NSWorkspace) so this stays UI-free.
    static func downloadInstaller(forMajor major: Int) async throws -> URL {
        let pkgURL = try await installerURL(forMajor: major)
        let (tempURL, _) = try await URLSession.shared.download(from: pkgURL)

        let fm = FileManager.default
        let destinationDir = (try? fm.url(for: .downloadsDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let destURL = destinationDir.appendingPathComponent(pkgURL.lastPathComponent)
        try? fm.removeItem(at: destURL)
        try fm.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    /// The Adoptium releases page for a given major — the manual-download fallback.
    static func manualDownloadURL(forMajor major: Int) -> URL {
        URL(string: "https://adoptium.net/temurin/releases/?version=\(major)&package=jdk&os=mac")!
    }
}

// MARK: - Installer Sheet

/// Reusable Java-install sheet: pick a version (framed by Minecraft compatibility),
/// then download and auto-open the Temurin installer. Used from Settings → Java and
/// from the Setup Wizard's "no Java found" prompt.
struct JavaInstallerSheet: View {
    /// The major version to preselect (defaults to the recommended LTS).
    var preselectedMajor: Int = JavaInstaller.recommendedOption().major
    let onClose: () -> Void

    @State private var selectedMajor: Int
    @State private var phase: Phase = .idle

    init(preselectedMajor: Int = JavaInstaller.recommendedOption().major,
         onClose: @escaping () -> Void) {
        self.preselectedMajor = preselectedMajor
        self.onClose = onClose
        _selectedMajor = State(initialValue: preselectedMajor)
    }

    private enum Phase: Equatable {
        case idle
        case downloading
        case opened(URL)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            optionList
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: MSC.Spacing.md) {
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Install Java")
                    .font(MSC.Typography.pageTitle)
                Text("Pick the version that matches your Minecraft version — MSC downloads the Temurin installer and opens it for you.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(MSC.Colors.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(MSC.Spacing.xl)
    }

    // MARK: Options

    private var optionList: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
            ForEach(JavaInstaller.minecraftInstallOptions) { option in
                optionRow(option)
            }

            HStack(alignment: .top, spacing: MSC.Spacing.xs) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12))
                    .foregroundStyle(MSC.Colors.info)
                    .padding(.top, 1)
                Text("Not sure? **Java 25** runs the latest Minecraft (26.x). You can install another version anytime from Settings → Java.")
                    .font(.caption2)
                    .foregroundStyle(MSC.Colors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, MSC.Spacing.xs)
        }
        .padding(MSC.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .disabled(phase == .downloading)
    }

    private func optionRow(_ option: JavaInstallOption) -> some View {
        let isSelected = option.major == selectedMajor
        return Button {
            selectedMajor = option.major
            if case .failed = phase { phase = .idle }
        } label: {
            HStack(alignment: .center, spacing: MSC.Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? MSC.Colors.accent : MSC.Colors.caption)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: MSC.Spacing.sm) {
                        Text(option.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MSC.Colors.heading)
                        if option.isRecommended {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(MSC.Colors.success.opacity(0.18))
                                )
                                .foregroundStyle(MSC.Colors.success)
                        }
                    }
                    Text(option.minecraftRange)
                        .font(.system(size: 12))
                        .foregroundStyle(MSC.Colors.caption)
                }

                Spacer()
            }
            .padding(MSC.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(isSelected ? MSC.Colors.accent.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? MSC.Colors.accent.opacity(0.35) : MSC.Colors.contentBorder,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {
            statusView

            HStack(alignment: .center, spacing: MSC.Spacing.md) {
                Spacer()

                Button("Close") { onClose() }
                    .buttonStyle(MSCSecondaryButtonStyle())

                switch phase {
                case .downloading:
                    Button {
                    } label: {
                        HStack(spacing: MSC.Spacing.xs) {
                            ProgressView().controlSize(.mini)
                            Text("Downloading…")
                        }
                    }
                    .buttonStyle(MSCPrimaryButtonStyle())
                    .disabled(true)
                case .opened:
                    Button("Download Again") { startDownload() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                default:
                    Button("Download & Open Installer") { startDownload() }
                        .buttonStyle(MSCPrimaryButtonStyle())
                }
            }
        }
        .padding(MSC.Spacing.xl)
    }

    @ViewBuilder
    private var statusView: some View {
        switch phase {
        case .idle, .downloading:
            EmptyView()
        case .opened(let pkgURL):
            HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MSC.Colors.success)
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Text("Installer opened and saved to your **Downloads** folder. Finish the steps in the Installer window, then click **Detect** back in Settings to select your new Java.")
                        .font(.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([pkgURL])
                    } label: {
                        Label("Show installer in Finder", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MSC.Colors.info)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(MSC.Colors.success.opacity(0.08))
            )
        case .failed(let message):
            HStack(alignment: .top, spacing: MSC.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MSC.Colors.warning)
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(MSC.Colors.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Adoptium download page →") {
                        NSWorkspace.shared.open(JavaInstaller.manualDownloadURL(forMajor: selectedMajor))
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(MSC.Colors.info)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MSC.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MSC.Radius.sm, style: .continuous)
                    .fill(MSC.Colors.warning.opacity(0.08))
            )
        }
    }

    // MARK: Actions

    private func startDownload() {
        let major = selectedMajor
        phase = .downloading
        Task {
            do {
                let pkgURL = try await JavaInstaller.downloadInstaller(forMajor: major)
                await MainActor.run {
                    NSWorkspace.shared.open(pkgURL)
                    phase = .opened(pkgURL)
                }
            } catch {
                await MainActor.run {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }
}
