//
//  OverviewHealthHelpers.swift
//  MinecraftServerController
//

import Foundation

extension OverviewHealthCardView {

    // MARK: - outdatedJarCount (used by overviewHealthCard)

    var outdatedJarCount: Int {
        let snap = viewModel.componentsSnapshot
        let infos = [snap.paper, snap.geyser, snap.floodgate, snap.broadcast, snap.bedrockConnect]
        return infos.filter { info in
            guard let local = info.local, let online = info.online else { return false }
            return !jarVersionsMatch(local, online)
        }.count
    }

    func jarVersionsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if let ba = jarBuildNumber(a), let bb = jarBuildNumber(b) { return ba == bb }
        return false
    }

    func jarBuildNumber(_ s: String) -> Int? {
        let lower = s.lowercased()
        guard let range = lower.range(of: "build") else { return nil }
        let after = lower[range.upperBound...]
        return Int(after.filter { $0.isNumber })
    }
}
