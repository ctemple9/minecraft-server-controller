//
//  AppViewModel+APIWiringBackupsHealth.swift
//  MSCmacOS
//
//  M1 (flowstate) slice 3: backup and health/diagnostics Remote API providers.
//  Extracted verbatim from AppViewModel.init. Health keeps its providers as locals
//  (repairHealthProblemProvider calls healthProblemsProvider) and assigns them by
//  reference, exactly as init did.
//

import Foundation

extension AppViewModel {

    /// Backup listing, on-demand backup creation, and restore. `isoFmt` formats timestamps.
    func wireBackupProviders(into server: RemoteAPIServer, isoFmt: ISO8601DateFormatter) {
        server.backupItemsProvider = { [weak self, isoFmt] in
            guard let self else { return RemoteAPIServer.BackupsResponseDTO(backups: []) }
            let items = Thread.isMainThread ? self.backupItems : DispatchQueue.main.sync { self.backupItems }
            let dtos = items.map { RemoteAPIServer.BackupItemDTO(id: $0.filename, displayName: $0.displayName,
                                                                 fileSize: $0.fileSize,
                                                                 modificationDate: $0.modificationDate.map { isoFmt.string(from: $0) },
                                                                 isAutomatic: $0.isAutomatic, slotId: $0.slotId,
                                                                 slotName: $0.slotName, triggerReason: $0.triggerReason) }
            return RemoteAPIServer.BackupsResponseDTO(backups: dtos)
        }
        server.createBackupNowProvider = { [weak self] in
            DispatchQueue.main.async { self?.createBackupForSelectedServer(isAutomatic: false) }
        }
        server.restoreBackupProvider = { [weak self] filename in
            guard let self else { return false }
            let items = Thread.isMainThread ? self.backupItems : DispatchQueue.main.sync { self.backupItems }
            guard let backup = items.first(where: { $0.filename == filename }) else { return false }
            DispatchQueue.main.async { self.restoreBackup(backup) }
            return true
        }
    }

    /// Health cards + startup-problem diagnostics and their repair actions, plus the
    /// presentational id→title/short/icon helpers ported from HealthCardsGridView.
    func wireHealthProviders(into server: RemoteAPIServer) {
        // Small presentational id→title/short/icon maps, ported from HealthCardsGridView so
        // iOS renders identical labels without re-deriving them.
        func healthCardTitle(_ id: String) -> String {
            switch id {
            case "directory":   return "Server Directory"
            case "java":        return "Java Runtime"
            case "vm":          return "VM Runtime"
            case "jar":         return "Components"
            case "ram":         return "RAM Allocation"
            case "worldData":   return "World Data"
            case "port":        return "Port Reachability"
            case "lastStartup": return "Last Startup"
            default:            return id
            }
        }
        func healthCardShort(_ id: String) -> String {
            switch id {
            case "directory":   return "Directory"
            case "java":        return "Java"
            case "vm":          return "VM Runtime"
            case "jar":         return "Components"
            case "ram":         return "RAM"
            case "worldData":   return "World Data"
            case "port":        return "Port"
            case "lastStartup": return "Last Start"
            default:            return id
            }
        }
        func healthCardIcon(_ id: String, _ status: HealthStatus) -> String {
            switch id {
            case "directory":  return "folder.fill"
            case "java":       return "cup.and.saucer.fill"
            case "vm":         return "memorychip"
            case "jar":        return "puzzlepiece.extension.fill"
            case "ram":        return "memorychip"
            case "worldData":  return "globe"
            case "port":       return "network"
            case "lastStartup":
                switch status {
                case .green: return "checkmark.seal.fill"
                case .gray:  return "seal"
                default:     return "exclamationmark.seal.fill"
                }
            default: return "questionmark.circle"
            }
        }
        func healthActionCode(_ a: HealthCardAction?) -> String? {
            switch a {
            case .none:                          return nil
            case .openURL(let s):                return "openURL:\(s)"
            case .openDockerDesktop:             return "openDockerDesktop"
            case .pullDockerImage:               return "pullDockerImage"
            case .openConsoleLog:                return "openConsoleLog"
            case .locateFolder:                  return "locateFolder"
            case .triggerDownload:               return "triggerDownload"
            case .openComponentsTab:             return "openComponentsTab"
            case .openRouterPortForwardGuide:    return "openRouterPortForwardGuide"
            case .diagnoseStartup:               return "diagnoseStartup"
            }
        }
        func mapHealthCard(_ c: HealthCardResult) -> RemoteAPIServer.HealthCardDTO {
            RemoteAPIServer.HealthCardDTO(
                id: c.id, title: healthCardTitle(c.id), shortLabel: healthCardShort(c.id),
                severity: c.status.rawValue, detail: c.detectedValue,
                iconSystemName: healthCardIcon(c.id, c.status),
                actionLabel: c.actionLabel, actionCode: healthActionCode(c.actionType))
        }

        // Reconstructs startup problems from {serverDir}/last_startup_result.json when the
        // in-memory set is empty (e.g. the Mac app was restarted since the failure).
        func loadPersistedProblems(_ cfg: ConfigServer) -> (problems: [StartupProblem], wasClean: Bool)? {
            let path = (cfg.serverDir as NSString).appendingPathComponent("last_startup_result.json")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let result = try? JSONDecoder().decode(LastStartupResult.self, from: data),
                  let problems = result.problems, !problems.isEmpty else { return nil }
            return (problems, result.wasClean)
        }

        func mapProblem(_ p: StartupProblem, cfg: ConfigServer, isRepairing: Bool) -> RemoteAPIServer.StartupProblemDTO {
            var actions: [String] = []
            if p.kind == .incompatibleVersion, p.installedFile != nil { actions.append("update") }
            if p.kind == .missingDependency, p.missingDependency != nil { actions.append("install") }
            if p.installedJarStem != nil { actions.append("disable"); actions.append("delete") }
            let linkedSlug = cfg.addonLinks?.values.first { $0.installedFileName == p.installedFile }?.slug
            let canonicalSlug = ModrinthSlugNormalizer.canonicalSlug(
                for: p.offenderId ?? p.offenderName, forgeFamily: cfg.javaFlavor.isForgeFamily)
            let slug = (linkedSlug ?? canonicalSlug)
                .trimmingCharacters(in: .whitespaces)
            let modrinthURL = slug.isEmpty ? nil : "https://modrinth.com/project/\(slug)"
            return RemoteAPIServer.StartupProblemDTO(
                id: p.id, kind: p.kind.rawValue, kindTitle: p.kind.title, iconSystemName: p.kind.symbol,
                offenderName: p.offenderName, requirement: p.requirement,
                installedFile: p.installedFile, installedJarStem: p.installedJarStem,
                missingDependency: p.missingDependency, rawExcerpt: p.rawExcerpt,
                isRepairing: isRepairing, availableActions: actions, modrinthURL: modrinthURL)
        }
        // GET /health — runs the Mac's diagnostic checks fresh, then maps the published cards.
        let healthProvider: () async -> RemoteAPIServer.HealthResponseDTO = { [weak self] in
            guard let self else { return RemoteAPIServer.HealthResponseDTO(serverType: "java", note: "not_available") }
            let ctx = await MainActor.run { () -> (ConfigServer, Bool)? in
                guard let sel = self.selectedServer, let cfg = self.configServer(for: sel) else { return nil }
                return (cfg, self.isServerRunning)
            }
            guard let (cfg, running) = ctx else {
                return RemoteAPIServer.HealthResponseDTO(serverType: "java", note: "no_active_server")
            }
            await self.refreshHealthCards(for: cfg)
            let cards = await MainActor.run { self.healthCards }
            let dtos = cards.map { mapHealthCard($0) }
            let overall: String = dtos.contains { $0.severity == "red" } ? "red"
                : dtos.contains { $0.severity == "yellow" } ? "yellow"
                : dtos.contains { $0.severity == "green" } ? "green" : "gray"
            return RemoteAPIServer.HealthResponseDTO(
                serverType: cfg.isBedrock ? "bedrock" : "java", serverName: cfg.displayName,
                serverRunning: running, overallSeverity: overall, cards: dtos)
        }

        // GET /health/problems — pure read of parsed startup problems (in-memory or from disk).
        let healthProblemsProvider: () async -> RemoteAPIServer.HealthProblemsResponseDTO = { [weak self] in
            guard let self else { return RemoteAPIServer.HealthProblemsResponseDTO(serverType: "java", note: "not_available") }
            let state = await MainActor.run { () -> (ConfigServer, Bool, [StartupProblem], Bool, Set<String>, String?)? in
                guard let sel = self.selectedServer, let cfg = self.configServer(for: sel) else { return nil }
                return (cfg, self.isServerRunning, self.startupProblems, self.startupProblemsAreSoftFail,
                        self.repairingProblemIds, self.startupProblemsServerId)
            }
            guard let (cfg, running, inMem, softFail, repairing, problemsServerId) = state else {
                return RemoteAPIServer.HealthProblemsResponseDTO(serverType: "java", note: "no_active_server")
            }
            let problems: [StartupProblem]
            let isSoft: Bool
            if !inMem.isEmpty, problemsServerId == cfg.id {
                problems = inMem; isSoft = softFail
            } else if let disk = loadPersistedProblems(cfg) {
                problems = disk.problems; isSoft = disk.wasClean
            } else {
                problems = []; isSoft = false
            }
            let dtos = problems.map { mapProblem($0, cfg: cfg, isRepairing: repairing.contains($0.id)) }
            return RemoteAPIServer.HealthProblemsResponseDTO(
                serverType: cfg.isBedrock ? "bedrock" : "java", serverRunning: running,
                isSoftFail: isSoft, problems: dtos)
        }

        // POST /health/repair — dispatches to the SAME repair methods StartupProblemsSheet uses.
        let repairHealthProblemProvider: (String, String) async -> RemoteAPIServer.HealthRepairResultDTO = { [weak self] problemId, action in
            guard let self else { return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "not_available") }
            let act = action.lowercased()
            guard ["update", "install", "disable", "delete"].contains(act) else {
                return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "invalid_action")
            }
            let outcome: RemoteAPIServer.HealthRepairResultDTO = await MainActor.run {
                guard let sel = self.selectedServer, let cfg = self.configServer(for: sel) else {
                    return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "no_active_server")
                }
                if self.isServerRunning {
                    return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "server_running")
                }
                // Ensure the live set holds this problem so finishRepair can drop it on success.
                if !self.startupProblems.contains(where: { $0.id == problemId }) || self.startupProblemsServerId != cfg.id {
                    if let disk = loadPersistedProblems(cfg) {
                        self.startupProblems = disk.problems
                        self.startupProblemsServerId = cfg.id
                        self.startupProblemsAreSoftFail = disk.wasClean
                    }
                }
                guard let problem = self.startupProblems.first(where: { $0.id == problemId }) else {
                    return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "problem_not_found")
                }
                let isMod = cfg.javaFlavor.addOnKind == .mod
                switch act {
                case "update":
                    guard problem.kind == .incompatibleVersion, problem.installedFile != nil else {
                        return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "action_unavailable")
                    }
                    self.repairIncompatibleAddon(problem, for: cfg)
                    return RemoteAPIServer.HealthRepairResultDTO(success: true, message: "repair_started")
                case "install":
                    guard problem.missingDependency != nil else {
                        return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "action_unavailable")
                    }
                    self.installMissingDependency(problem, for: cfg)
                    return RemoteAPIServer.HealthRepairResultDTO(success: true, message: "repair_started")
                case "disable":
                    guard let stem = problem.installedJarStem else {
                        return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "action_unavailable")
                    }
                    if isMod { self.toggleMod(jarStem: stem) } else { self.togglePlugin(jarStem: stem) }
                    self.startupProblems.removeAll { $0.id == problem.id }
                    return RemoteAPIServer.HealthRepairResultDTO(success: true, message: "disabled")
                case "delete":
                    guard let stem = problem.installedJarStem else {
                        return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "action_unavailable")
                    }
                    if isMod { self.removeMod(jarStem: stem) } else { self.removePlugin(jarStem: stem) }
                    self.startupProblems.removeAll { $0.id == problem.id }
                    return RemoteAPIServer.HealthRepairResultDTO(success: true, message: "deleted")
                default:
                    return RemoteAPIServer.HealthRepairResultDTO(success: false, message: "invalid_action")
                }
            }
            guard outcome.success else { return outcome }
            let updated = await healthProblemsProvider()
            return RemoteAPIServer.HealthRepairResultDTO(success: true, message: outcome.message, updated: updated)
        }
        server.healthProvider = healthProvider
        server.healthProblemsProvider = healthProblemsProvider
        server.repairHealthProblemProvider = repairHealthProblemProvider
    }
}
