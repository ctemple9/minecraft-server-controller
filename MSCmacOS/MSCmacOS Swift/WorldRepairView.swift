//  WorldRepairView.swift
//  MinecraftServerController
//
//  Sheet that walks the user through the world level.dat repair flow.
//  Three phases: prompt → repairing (live log) → done (success or failure).

import SwiftUI

struct WorldRepairView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var isPresented: Bool

    private enum Phase {
        case prompt
        case repairing
        case done(success: Bool)
    }

    @State private var phase: Phase = .prompt
    @State private var logLines: [String] = []
    @State private var repairSucceeded = false

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .prompt:
                promptContent
            case .repairing:
                repairingContent
            case .done(let success):
                doneContent(success: success)
            }
        }
        .frame(width: 480)
        .background(MSC.Colors.cardBackground)
    }

    // MARK: - Prompt

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            HStack(spacing: MSC.Spacing.md) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repair World")
                        .font(.headline)
                    Text("Fix connection failures after a Bedrock update")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: MSC.Spacing.sm) {
                Text("Are you seeing this error when trying to connect?")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: MSC.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 3)
                    Text("\"The server you are attempting to join may not exist or may be locked\"")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Text("After a Minecraft update, the server's world format file (level.dat) can become incompatible with the new version, causing all connections to silently fail.")
                    .font(MSC.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Label("What Repair World does", systemImage: "info.circle")
                    .font(.subheadline.weight(.medium))

                Group {
                    bulletRow("Creates a backup of your current world first")
                    bulletRow("Starts the server briefly to generate an updated format file")
                    bulletRow("Replaces only the format file — your builds and world data are not touched")
                    bulletRow("Removes temporary files when done")
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                Button {
                    startRepair()
                } label: {
                    Label("Repair World", systemImage: "wrench.and.screwdriver.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(MSC.Spacing.lg)
    }

    // MARK: - Repairing

    private var repairingContent: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            HStack(spacing: MSC.Spacing.md) {
                ProgressView()
                    .scaleEffect(0.9)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repairing World…")
                        .font(.headline)
                    Text("Do not close this window or start the server manually.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line)
                        }
                    }
                    .padding(MSC.Spacing.sm)
                }
                .frame(height: 180)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm)
                        .fill(Color.black.opacity(0.1))
                )
                .onChange(of: logLines.count) { _ in
                    if let last = logLines.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(MSC.Spacing.lg)
    }

    // MARK: - Done

    private func doneContent(success: Bool) -> some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.lg) {
            HStack(spacing: MSC.Spacing.md) {
                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(success ? Color.green : Color.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(success ? "World Repaired" : "Repair Failed")
                        .font(.headline)
                    Text(success
                         ? "Your world is ready. Start the server and try connecting."
                         : "Something went wrong. Check the log below and try again.")
                        .font(MSC.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if success {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Label("What changed", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))
                    bulletRow("level.dat replaced with a version compatible with the current BDS")
                    bulletRow("level.dat_old and levelname.txt updated to match")
                    bulletRow("World data (db folder) was not modified")
                    bulletRow("A backup of the previous world was saved")
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(MSC.Spacing.sm)
                }
                .frame(height: 140)
                .background(
                    RoundedRectangle(cornerRadius: MSC.Radius.sm)
                        .fill(Color.black.opacity(0.1))
                )
            }

            Divider()

            HStack {
                Button("Close") {
                    isPresented = false
                }
                .buttonStyle(MSCSecondaryButtonStyle())

                Spacer()

                if success {
                    Button {
                        isPresented = false
                        viewModel.startServer()
                    } label: {
                        Label("Start Server", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(MSC.Spacing.lg)
    }

    // MARK: - Helpers

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: MSC.Spacing.xs) {
            Text("•")
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(MSC.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startRepair() {
        phase = .repairing
        logLines = []
        Task { @MainActor in
            let success = await viewModel.repairWorldLevelDat { line in
                logLines.append(line)
            }
            phase = .done(success: success)
        }
    }
}
