//
//  MessagePlayerSheetView.swift
//  MinecraftServerController
//

import SwiftUI

// MARK: - View

struct MessagePlayerSheetView: View {
    @EnvironmentObject var viewModel: AppViewModel

    let player: OnlinePlayer
    @Binding var messageTarget: OnlinePlayer?
    @Binding var messageText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Message \(player.name)")
                .font(.headline)

            TextField("Message", text: $messageText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    messageTarget = nil
                    messageText = ""
                }
                Button("Send") {
                    viewModel.messagePlayer(named: player.name, message: messageText)
                    messageTarget = nil
                    messageText = ""
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}
