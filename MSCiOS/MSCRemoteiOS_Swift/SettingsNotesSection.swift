import SwiftUI

struct SettingsNotesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MSCRemoteStyle.spaceSM) {
            MSCSectionHeader(title: "Security Note")
            Text("For away-from-home control, use a VPN overlay like Tailscale. Do not expose this API directly to the public internet.")
                .font(.system(size: 12))
                .foregroundStyle(MSCRemoteStyle.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .mscCard()
    }
}
