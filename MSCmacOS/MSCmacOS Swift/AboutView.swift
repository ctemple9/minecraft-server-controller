//
//  AboutView.swift
//  MinecraftServerController
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

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

            Spacer()

            Button("OK") {
                dismiss()
            }
            .buttonStyle(MSCSecondaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(MSC.Spacing.xxl)
        .frame(minWidth: 360, minHeight: 220)
    }
}

#Preview {
    AboutView()
}

