//
//  AppViewModel+Metrics.swift
//  MinecraftServerController
//

import Foundation

extension AppViewModel {

    // MARK: - Resource usage dispatch

    func updateResourceUsageMetrics() {
        if selectedServerIsBedrock {
            updateBedrockResourceUsageMetrics()
            return
        }
        guard let pid = javaBackend.processID else {
            serverCpuPercent = nil
            serverRamMB = nil
            serverRamFractionOfMax = nil
            return
        }
        let maxRamGB = currentServerMaxRamGB
        let coreCount = logicalCoreCount
        let shouldLogPSOutput = serverCpuPercent == nil

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }

            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-p", String(pid), "-o", "%cpu,rss"]
            let pipe = Pipe()
            ps.standardOutput = pipe

            do {
                try ps.run()
                ps.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.serverCpuPercent = nil
                    self.serverRamMB = nil
                    self.serverRamFractionOfMax = nil
                }
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.serverCpuPercent = nil
                    self.serverRamMB = nil
                    self.serverRamFractionOfMax = nil
                }
                return
            }

            let lines = output
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .filter { !$0.starts(with: "%") }

            if lines.isEmpty {
                Task { @MainActor in
                    self.logAppMessage("[Metrics] ps returned no data lines for PID \(pid)")
                }
            } else {
                if shouldLogPSOutput {
                    Task { @MainActor in
                        self.logAppMessage("[Metrics] ps output for PID \(pid): \(lines.joined(separator: " | "))")
                    }
                }
            }

            guard let dataLine = lines.first else {
                DispatchQueue.main.async {
                    self.serverCpuPercent = nil
                    self.serverRamMB = nil
                    self.serverRamFractionOfMax = nil
                }
                return
            }

            let parts = dataLine.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2 else {
                Task { @MainActor in
                    self.logAppMessage("[Metrics] ps data line has unexpected format: '\(dataLine)'")
                }
                DispatchQueue.main.async {
                    self.serverCpuPercent = nil
                    self.serverRamMB = nil
                    self.serverRamFractionOfMax = nil
                }
                return
            }

            let cpuStr = String(parts[0])
            let rssStr = String(parts[1])
            let rawCpu = Double(cpuStr)
            let rssKB = Double(rssStr)

            var cpuVal: Double? = nil
            var ramMB: Double? = nil
            var fraction: Double? = nil

            if let rawCpu = rawCpu {
                if coreCount > 0 {
                    let normalized = rawCpu / Double(coreCount)
                    cpuVal = max(0.0, min(100.0, normalized))
                } else {
                    cpuVal = rawCpu
                }
            }

            if let rssKB = rssKB {
                let mb = rssKB / 1024.0
                ramMB = mb
                if let maxRamGB = maxRamGB {
                    let maxMB = Double(maxRamGB) * 1024.0
                    if maxMB > 0 { fraction = mb / maxMB }
                }
            }

            DispatchQueue.main.async {
                self.serverCpuPercent = cpuVal
                self.serverRamMB = ramMB
                self.serverRamFractionOfMax = fraction
                self.updateUptimeDisplay()
            }
        }
    }
}
