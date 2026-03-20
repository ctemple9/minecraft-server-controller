//
//  OverviewDuckDNSSectionView.swift
//  MinecraftServerController
//

import SwiftUI

struct OverviewDuckDNSSectionView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var hasSavedDuckDNS: Bool
    @Binding var isEditingDuckDNS: Bool

    var body: some View {
        duckdnsSection
    }

    // MARK: - DuckDNS

    private var duckdnsSection: some View {
        GroupBox("DuckDNS / External Hostname") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Optional: set a hostname (for example, yourname.duckdns.org) so friends can connect more easily.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("yourname.duckdns.org", text: $viewModel.duckdnsInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Save Hostname") {
                        let trimmed = viewModel.duckdnsInput
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.duckdnsInput = trimmed
                        viewModel.saveDuckDNSHostname()

                        // Once saved with a non-empty value, hide this box
                        hasSavedDuckDNS = !trimmed.isEmpty
                        isEditingDuckDNS = false
                    }
                }

                if !viewModel.duckdnsInput.isEmpty {
                    Text(viewModel.duckdnsInput)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
