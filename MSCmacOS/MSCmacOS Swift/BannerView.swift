import SwiftUI


struct BannerView: View {
    var body: some View {
        ZStack {
            MSC.Colors.tierChrome
                .ignoresSafeArea(edges: .top)

            HStack {
                VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                    Text("Minecraft Server Controller")
                        .font(MSC.Typography.shellTitle)
                        .foregroundStyle(.primary)

                    Text("by TempleTech")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.45))
                }

                Spacer()
            }
            .padding(.horizontal, MSC.Spacing.lg)
            .padding(.vertical, MSC.Spacing.sm)
        }
        .frame(height: 70)
    }
}

#Preview {
    BannerView()
}
