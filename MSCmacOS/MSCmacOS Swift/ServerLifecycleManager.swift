//
//  ServerLifecycleManager.swift
//  MinecraftServerController
//

import Foundation

@MainActor
/// Encapsulates per-run server lifecycle state (timers and readiness flags) used by `AppViewModel`.
final class ServerLifecycleManager {

    // MARK: - Metrics timer

    /// Fires every 5 s while the server is running to collect TPS / player / resource data.
    private(set) var metricsTimer: Timer?

    // MARK: - Server-readiness flags (reset on every new run)

    /// Set to true once the server logs "Done (" — gates auto TPS/player commands.
    var serverReadyForAutoMetrics: Bool = false

    /// Prevents the "Server is ready" controller message from appearing more than once per run.
    var hasLoggedReadyOnce: Bool = false

    // MARK: - Running server identity

    /// ID of the server whose process is currently active.
    /// Guards against stale delayed callbacks acting on a different server.
    var runningServerId: String? = nil

    // MARK: - Stop requested

    /// Set to true when the user initiates a stop.
    /// Used to prevent delayed auto-start tasks (Broadcast/BedrockConnect) from firing during shutdown.
    var isStopRequested: Bool = false

    // MARK: - Initiate / first-run state (per run, per server)

    /// Non-nil only during an "Initiate" run. Holds the server ID so auto-stop
    /// can guard against acting on a different server if the user switches.
    var initiatingFirstRunServerId: String? = nil

    /// Prevents more than one auto-stop from firing for a single Initiate run.
    var hasIssuedAutoStopForInitiate: Bool = false

    // MARK: - Timer management

    /// Start (or restart) the metrics timer.
    /// - Parameters:
    ///   - interval: Seconds between ticks (default 5).
    ///   - tick: Closure called on each timer fire. Runs on the RunLoop.main thread.
    func startMetricsTimer(interval: TimeInterval = 5, tick: @escaping () -> Void) {
        metricsTimer?.invalidate()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            tick()
        }
    }

    /// Stop the metrics timer and nil it out.
    func stopMetricsTimer() {
        metricsTimer?.invalidate()
        metricsTimer = nil
    }

    // MARK: - Convenience reset helpers

    /// Call at the beginning of every new server start to clear per-run flags.
    func resetForNewRun(serverId: String) {
        runningServerId = serverId
        serverReadyForAutoMetrics = false
        hasLoggedReadyOnce = false
        isStopRequested = false
    }

    /// Call after a server process terminates to clean up all runtime state.
    func resetAfterTermination() {
        stopMetricsTimer()
        runningServerId = nil
        serverReadyForAutoMetrics = false
        hasLoggedReadyOnce = false
        initiatingFirstRunServerId = nil
        hasIssuedAutoStopForInitiate = false
        isStopRequested = false
    }

    /// Call to arm one-run Initiate mode for the given server.
    func beginInitiateRun(serverId: String) {
        initiatingFirstRunServerId = serverId
        hasIssuedAutoStopForInitiate = false
    }

    /// Call when the Initiate auto-stop has been issued (or when a run completes normally).
    func clearInitiateState() {
        initiatingFirstRunServerId = nil
        hasIssuedAutoStopForInitiate = false
    }
}

