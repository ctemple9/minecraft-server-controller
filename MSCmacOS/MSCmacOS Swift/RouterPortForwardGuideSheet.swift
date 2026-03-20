//
//  RouterPortForwardGuideSheet.swift
//  MinecraftServerController
//
//  Sheet container for the Router Port Forwarding Guide feature.
//  Visual: matches Welcome Guide — dark windowBackgroundColor base,
//  controlBackgroundColor chrome bars, system Dividers.
//

import SwiftUI

// MARK: - Sheet

struct RouterPortForwardGuideSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var sheetViewModel: RouterPortForwardGuideSheetViewModel
    @Environment(\.dismiss) private var dismiss

    init(runtimeContext: RouterPortForwardGuideRuntimeContext?) {
        _sheetViewModel = StateObject(
            wrappedValue: RouterPortForwardGuideSheetViewModel(runtimeContext: runtimeContext)
        )
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Header bar
            HStack(spacing: MSC.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Port Forwarding Guide")
                        .font(MSC.Typography.shellTitle)
                        .foregroundStyle(.primary)
                    Text(screenSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Close guide")
            }
            .padding(.horizontal, MSC.Spacing.xl)
            .padding(.vertical, MSC.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            // MARK: Screen content
            Group {
                switch sheetViewModel.currentScreen {
                case .picker:
                    RouterPortForwardGuidePicker(sheetViewModel: sheetViewModel)

                case .guideReader(let id):
                    RouterPortForwardGuideReader(
                        guideID: id,
                        sheetViewModel: sheetViewModel
                    )

                case .troubleshooting:
                    RouterPortForwardGuideTroubleshootingScreen(
                        sheetViewModel: sheetViewModel
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var screenSubtitle: String {
        switch sheetViewModel.currentScreen {
        case .picker:
            return "Step 1 of 3 — Find your router"
        case .guideReader(let id):
            let name = sheetViewModel.allGuides.first { $0.id == id }?.displayName
            return name.map { "Step 2 of 3 — \($0)" } ?? "Step 2 of 3 — Follow the steps"
        case .troubleshooting:
            return "Step 3 of 3 — Diagnose issues"
        }
    }
}
