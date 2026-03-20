//
//  DetailsPerformanceTabView.swift
//  MinecraftServerController
//

import SwiftUI

// MARK: - View

struct DetailsPerformanceTabView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @Binding var isShowingPerformanceHelp: Bool

    /// Controls whether the right-hand Monitoring/Quick Actions/Health Summary panel is visible.
    @State var sidebarCollapsed: Bool = false

    // Used by DetailsPerformanceTabContent extension to conditionalise CPU subtitle.
    var isBedrock: Bool {
        guard let s = viewModel.selectedServer else { return false }
        return viewModel.configServer(for: s)?.isBedrock ?? false
    }
}
