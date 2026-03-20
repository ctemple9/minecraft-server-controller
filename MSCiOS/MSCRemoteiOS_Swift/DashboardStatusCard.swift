import SwiftUI

struct DashboardStatusCard: View {
    let isRunning: Bool
    let isPaired: Bool
    let activeServerNameText: String
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MSCSectionHeader(title: "Server Status")
                .padding(.bottom, MSCRemoteStyle.spaceMD)

            HStack(alignment: .center, spacing: MSCRemoteStyle.spaceMD) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        MSCStatusDot(isActive: isRunning, size: 10)
                        Text(isRunning ? "RUNNING" : "STOPPED")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(isRunning ? MSCRemoteStyle.success : MSCRemoteStyle.danger)
                            .kerning(0.8)
                    }
                    Text(activeServerNameText)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(isPaired ? MSCRemoteStyle.textPrimary : MSCRemoteStyle.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPaired ? MSCRemoteStyle.accent : MSCRemoteStyle.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(isPaired ? MSCRemoteStyle.accentDim : MSCRemoteStyle.bgElevated)
                        .clipShape(Circle())
                }
                .disabled(!isPaired)
            }

            if !isPaired {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                    Text("Not paired — open Settings to connect.")
                        .font(.system(size: 12))
                }
                .foregroundStyle(MSCRemoteStyle.warning)
                .padding(.top, MSCRemoteStyle.spaceMD)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .mscCard()
    }
}
