//
//  AppViewModel+BedrockPerformance.swift
//  MinecraftServerController
//
//  Bedrock performance metrics backed by `docker stats`.
//  Keeps the existing Performance tab layout while feeding it
//  Docker-safe data instead of Java/JVM-only metrics.
//

import Foundation

extension AppViewModel {

    var selectedServerIsBedrock: Bool {
        guard let server = selectedServer else { return false }
        return configServer(for: server)?.isBedrock ?? false
    }

    var performanceCpuPercentForSelectedServer: Double? {
        selectedServerIsBedrock ? bedrockCpuPercent : serverCpuPercent
    }

    var performanceRamMBForSelectedServer: Double? {
        selectedServerIsBedrock ? bedrockMemoryUsedMB : serverRamMB
    }

    var performanceRamLimitGBForSelectedServer: Int? {
        guard selectedServerIsBedrock else { return currentServerMaxRamGB }
        guard let limitMB = bedrockMemoryLimitMB, limitMB > 0 else { return nil }
        return max(1, Int((limitMB / 1024.0).rounded()))
    }

    var bedrockLoad1mAverage: Double? { rollingAverage(from: bedrockCpuHistory, sampleCount: 12) }
    var bedrockLoad5mAverage: Double? { rollingAverage(from: bedrockCpuHistory, sampleCount: 60) }
    var bedrockLoad15mAverage: Double? { rollingAverage(from: bedrockCpuHistory, sampleCount: 180) }

    func clearBedrockPerformanceMetrics() {
        bedrockCpuPercent = nil
        bedrockMemoryUsedMB = nil
        bedrockMemoryLimitMB = nil
        bedrockCpuHistory.removeAll()
    }

    func updateBedrockResourceUsageMetrics() {
        guard let server = selectedServer,
              let cfg = configServer(for: server),
              cfg.isBedrock else {
            clearBedrockPerformanceMetrics()
            return
        }

        guard let docker = DockerUtility.dockerPath() else {
            clearBedrockPerformanceMetrics()
            return
        }

        let containerName = BedrockServerBackend.containerName(forServerId: cfg.id)

        guard DockerUtility.isContainerRunning(name: containerName, dockerPath: docker) else {
            clearBedrockPerformanceMetrics()
            return
        }

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }

            guard let result = DockerUtility.runCapture(
                executable: docker,
                args: ["stats", "--no-stream", "--format", "{{.CPUPerc}}|{{.MemUsage}}", containerName]
            ), result.exitCode == 0 else {
                DispatchQueue.main.async {
                    guard self.selectedServer?.id == server.id else { return }
                    self.bedrockCpuPercent = nil
                    self.bedrockMemoryUsedMB = nil
                    self.bedrockMemoryLimitMB = nil
                    self.updateUptimeDisplay()
                }
                return
            }

            let line = result.output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let fields = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard fields.count == 2 else {
                DispatchQueue.main.async {
                    guard self.selectedServer?.id == server.id else { return }
                    self.bedrockCpuPercent = nil
                    self.bedrockMemoryUsedMB = nil
                    self.bedrockMemoryLimitMB = nil
                    self.updateUptimeDisplay()
                }
                return
            }

            let cpuPercent = Self.parseDockerPercent(fields[0])

            let memoryFields = fields[1].split(separator: "/", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let usedMB = memoryFields.indices.contains(0) ? Self.parseDockerMemoryMB(memoryFields[0]) : nil
            let limitMB = memoryFields.indices.contains(1) ? Self.parseDockerMemoryMB(memoryFields[1]) : nil

            DispatchQueue.main.async {
                guard self.selectedServer?.id == server.id else { return }
                self.bedrockCpuPercent = cpuPercent
                self.bedrockMemoryUsedMB = usedMB
                self.bedrockMemoryLimitMB = limitMB
                self.appendBedrockMetricSample(cpu: cpuPercent)
                self.updateUptimeDisplay()
            }
        }
    }

    private func appendBedrockMetricSample(cpu: Double?) {
        guard let cpu else { return }
        bedrockCpuHistory.append(cpu)
        if bedrockCpuHistory.count > 180 {
            bedrockCpuHistory.removeFirst(bedrockCpuHistory.count - 180)
        }
    }

    private func rollingAverage(from history: [Double], sampleCount: Int) -> Double? {
        guard !history.isEmpty else { return nil }
        let slice = history.suffix(sampleCount)
        guard !slice.isEmpty else { return nil }
        let total = slice.reduce(0, +)
        return total / Double(slice.count)
    }

    nonisolated private static func parseDockerPercent(_ raw: String) -> Double? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        return Double(trimmed)
    }

    nonisolated private static func parseDockerMemoryMB(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        let units: [(suffix: String, multiplierToMB: Double)] = [
            ("tib", 1024.0 * 1024.0),
            ("gib", 1024.0),
            ("mib", 1.0),
            ("kib", 1.0 / 1024.0),
            ("tb", 1_000_000_000_000.0 / 1_048_576.0),
            ("gb", 1_000_000_000.0 / 1_048_576.0),
            ("mb", 1_000_000.0 / 1_048_576.0),
            ("kb", 1_000.0 / 1_048_576.0),
            ("b", 1.0 / 1_048_576.0)
        ]

        for unit in units {
            if cleaned.hasSuffix(unit.suffix) {
                let valueString = String(cleaned.dropLast(unit.suffix.count))
                guard let value = Double(valueString) else { return nil }
                return value * unit.multiplierToMB
            }
        }

        return nil
    }
}
