//
//  AboutView.swift
//  MinecraftServerController
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    // Each AboutView instance owns its own checker so the inline status
    // display stays self-contained and dismissing the sheet resets state.
    @StateObject private var updateChecker = AppUpdateChecker()

    private var appVersion: String {
        let dict = Bundle.main.infoDictionary
        let version = dict?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = dict?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: MSC.Spacing.md) {
            Text("Minecraft Server Controller")
                .font(MSC.Typography.pageTitle)

            Text("A macOS app for managing local Mincraft servers, both Java (Paper) and Bedrock (BDS).")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, MSC.Spacing.xxl)

            Text("Version \(appVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, MSC.Spacing.xs)

            Text("Developed by C.M.Temple")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, MSC.Spacing.xs)

            // MARK: - Update check (inline — no alert/sheet, respects §1.5 rule)
            updateStatusView
                .padding(.top, MSC.Spacing.xs)

            Spacer()

            HStack(spacing: MSC.Spacing.sm) {
                Button("Check for Updates…") {
                    updateChecker.checkForUpdates()
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .disabled({
                    if case .checking = updateChecker.state { return true }
                    return false
                }())

                Button("OK") {
                    dismiss()
                }
                .buttonStyle(MSCSecondaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MSC.Spacing.xxl)
        .frame(minWidth: 360, minHeight: 240)
    }

    // MARK: - Inline status display

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateChecker.state {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: MSC.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .upToDate(let version):
            Text("Version \(version) is up to date.")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .updateAvailable(let tag, let url):
            VStack(spacing: MSC.Spacing.xs) {
                Text("Version \(tag) is available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // Opening a GitHub release page is the documented download channel —
                // this browser handoff is intentional and acceptable per flowstate §1.
                Button("View Release") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
                .font(.footnote)
            }

        case .error(let message):
            Text("Update check failed: \(message)")
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MSC.Spacing.md)
        }
    }
}

#Preview {
    AboutView()
}

