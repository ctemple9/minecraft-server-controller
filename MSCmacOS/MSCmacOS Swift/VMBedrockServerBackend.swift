// VMBedrockServerBackend.swift
//  MinecraftServerController
//
// ServerBackend implementation that runs Bedrock Dedicated Server inside a
// lightweight Linux VM built on Apple's Virtualization.framework — the native
// replacement for the Docker (itzg/minecraft-bedrock-server) backend.
//
// Architecture (proven in ~/Desktop/msc-vm-prototype; see grapes.md WS3):
//   - Boots a bundled "appliance": a Kata virtio-built-in kernel + a small custom
//     initramfs-as-rootfs (busybox + glibc + our /init). No disk, no systemd.
//   - The server's serverDir (BDS install + world) is shared into the guest over
//     virtio-fs (tag "world"), mounted at /mnt — the equivalent of Docker's
//     `-v serverDir:/data`. World files persist on the host between runs.
//   - The guest /init brings up DHCP networking, mounts the share, and runs
//     bedrock_server in the foreground with stdin/stdout wired to the virtio
//     serial console. On graceful exit it powers the guest off cleanly.
//   - Console output is read on a background thread (→ onOutputLine), the
//     Docker-logs equivalent. Commands are written to the console (→ BDS stdin),
//     the `docker exec send-command` equivalent.
//   - A host-side UDP relay (UDPRelay) forwards 0.0.0.0:<port> (covers LAN and
//     playit's 127.0.0.1) to the guest's BDS — the `-p 19132:19132/udp` equivalent.
//
// Docker → VM operation mapping:
//   docker run            → VZVirtualMachine.start()
//   docker logs -f        → read serial console
//   docker exec send-cmd  → write serial console
//   docker stop           → write "stop" → guest poweroff (fallback vm.stop())
//   isContainerRunning    → vm.state == .running
//
// Requires entitlement com.apple.security.virtualization; app must NOT be sandboxed.

import Foundation
import Virtualization

final class VMBedrockServerBackend: NSObject, ServerBackend {

    // MARK: - ServerBackend conformance

    var onOutputLine: ((String) -> Void)?
    var onDidTerminate: (() -> Void)?
    var lastCommandError: String? = nil

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isRunning
    }

    // MARK: - Internal state

    /// All VZVirtualMachine access must happen on this queue.
    private let vmQueue = DispatchQueue(label: "msc.vm.bedrock")
    private var vm: VZVirtualMachine?

    /// Serial console pipes. We READ guest stdout (→ onOutputLine) and WRITE guest
    /// stdin (← sendCommand). The console MUST be a Pipe — Virtualization silently
    /// drops writes to a plain file (learned in WS3 session 1).
    private var guestOutPipe: Pipe?   // guest console -> host (read)
    private var guestInPipe: Pipe?    // host -> guest console (write)
    private var pendingOutput = Data()
    private let outputLock = NSLock()

    private let stateLock = NSLock()
    private var _isRunning = false
    private var hasFiredTerminate = false

    /// Host-side UDP relay (0.0.0.0:port -> guest:port). Started once the guest IP
    /// is learned from the console.
    private var relay: UDPRelay?
    private var bedrockPort: UInt16 = 19132
    private var guestIP: String?

    /// Latest guest performance snapshot (from the in-guest [MSCSTATS] reporter).
    private let statsLock = NSLock()
    private var lastCpuPercent: Double?
    private var lastMemUsedMB: Double?
    private var lastMemTotalMB: Double?

    /// Fallback force-stop if a graceful "stop" doesn't power the guest off.
    private var forceStopWorkItem: DispatchWorkItem?

    // MARK: - Bundled appliance resources

    /// The virtio-built-in kernel (bzImage) bundled in the app.
    private static func kernelURL() -> URL? {
        Bundle.main.url(forResource: "vmlinuz-kata", withExtension: nil)
            ?? Bundle.main.url(forResource: "vmlinuz-kata-6.18.35", withExtension: nil)
    }
    /// The appliance initramfs (busybox + glibc + /init) bundled in the app.
    private static func initramfsURL() -> URL? {
        Bundle.main.url(forResource: "appliance-initramfs", withExtension: "gz")
    }

    // MARK: - Start

    func start(config: ConfigServer, appConfig: AppConfig) throws {
        stateLock.lock()
        if _isRunning {
            stateLock.unlock()
            throw ServerBackendError.alreadyRunning
        }
        hasFiredTerminate = false
        stateLock.unlock()

        guard VZVirtualMachine.isSupported else {
            throw ServerBackendError.failedToStart(makeError(
                "This Mac does not support virtualization, so Bedrock servers can't run here."))
        }
        guard let kernel = Self.kernelURL() else {
            throw ServerBackendError.failedToStart(makeError(
                "Bundled VM kernel is missing from the app."))
        }
        guard let initramfs = Self.initramfsURL() else {
            throw ServerBackendError.failedToStart(makeError(
                "Bundled VM initramfs is missing from the app."))
        }

        // The serverDir holds the BDS install + world, shared into the guest at /mnt.
        let serverDir = URL(fileURLWithPath: config.serverDir, isDirectory: true)
        guard FileManager.default.fileExists(atPath: serverDir.path) else {
            throw ServerBackendError.failedToStart(makeError(
                "Server folder not found: \(serverDir.path)"))
        }

        let savedProps = BedrockPropertiesManager.readModel(serverDir: serverDir.path)
        bedrockPort = UInt16(savedProps.serverPort)
        let memoryGB = config.maxRamGB
        let version = config.bedrockVersion

        // We've committed to starting. The heavy work — installing BDS if needed,
        // then booting the VM — runs off the main thread so the UI stays responsive
        // and progress streams to the console. Errors surface via the console and
        // onDidTerminate (the app treats that as the server having stopped).
        stateLock.lock(); _isRunning = true; stateLock.unlock()
        emitLine("[VM] Preparing Bedrock appliance...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try BedrockProvisioner.ensureInstalled(serverDir: serverDir, version: version) { line in
                    self.emitLine(line)
                }
                let vmConfig = try self.buildVMConfiguration(kernel: kernel,
                                                             initramfs: initramfs,
                                                             worldDir: serverDir,
                                                             memoryGB: memoryGB)
                self.vmQueue.async {
                    let machine = VZVirtualMachine(configuration: vmConfig, queue: self.vmQueue)
                    machine.delegate = self
                    self.vm = machine
                    self.emitLine("[VM] Booting Bedrock appliance on UDP port \(self.bedrockPort)...")
                    machine.start { result in
                        if case .failure(let err) = result {
                            self.emitLine("[VM] Failed to start VM: \(err.localizedDescription)")
                            self.teardown()
                            self.fireDidTerminate()
                        }
                    }
                }
            } catch {
                self.emitLine("[VM] Could not start Bedrock server: \(error.localizedDescription)")
                self.teardown()
                self.fireDidTerminate()
            }
        }
    }

    // MARK: - VM configuration

    private func buildVMConfiguration(kernel: URL,
                                      initramfs: URL,
                                      worldDir: URL,
                                      memoryGB: Int) throws -> VZVirtualMachineConfiguration {
        let cfg = VZVirtualMachineConfiguration()

        // Boot: explicit kernel + our initramfs-as-rootfs, console on hvc0 (diskless).
        let boot = VZLinuxBootLoader(kernelURL: kernel)
        boot.initialRamdiskURL = initramfs
        boot.commandLine = "console=hvc0"
        cfg.bootLoader = boot

        cfg.platform = VZGenericPlatformConfiguration()

        let cpu = max(VZVirtualMachineConfiguration.minimumAllowedCPUCount,
                      min(2, VZVirtualMachineConfiguration.maximumAllowedCPUCount))
        cfg.cpuCount = cpu

        // BDS needs ~1–1.5 GB; honor the user's RAM cap when set, else 2 GB.
        let requested = UInt64(memoryGB > 0 ? memoryGB : 2) * 1024 * 1024 * 1024
        cfg.memorySize = max(VZVirtualMachineConfiguration.minimumAllowedMemorySize,
                             min(requested, VZVirtualMachineConfiguration.maximumAllowedMemorySize))

        // Serial console wired to Pipes for read (logs) + write (commands).
        let outPipe = Pipe(); let inPipe = Pipe()
        self.guestOutPipe = outPipe; self.guestInPipe = inPipe
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: inPipe.fileHandleForReading,
            fileHandleForWriting: outPipe.fileHandleForWriting)
        cfg.serialPorts = [serial]
        startConsoleReader(outPipe)

        // NAT network (guest gets a 192.168.64.x lease; host reaches it via bridge100).
        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = VZNATNetworkDeviceAttachment()
        cfg.networkDevices = [net]

        // virtio-fs share of the world folder, tag "world" (mounted at /mnt in-guest).
        try VZVirtioFileSystemDeviceConfiguration.validateTag("world")
        let fsDevice = VZVirtioFileSystemDeviceConfiguration(tag: "world")
        fsDevice.share = VZSingleDirectoryShare(
            directory: VZSharedDirectory(url: worldDir, readOnly: false))
        cfg.directorySharingDevices = [fsDevice]

        cfg.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        cfg.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        try cfg.validate()
        return cfg
    }

    // MARK: - Console read (guest stdout -> onOutputLine), with guest-IP discovery

    private func startConsoleReader(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                self.flushPendingOutput()
                return
            }
            self.handleIncoming(data: data)
        }
    }

    private func handleIncoming(data: Data) {
        outputLock.lock()
        pendingOutput.append(data)
        let newline = Data([0x0A])
        var lines: [String] = []
        while let range = pendingOutput.firstRange(of: newline) {
            let lineData = pendingOutput.subdata(in: 0..<range.lowerBound)
            pendingOutput.removeSubrange(0..<range.upperBound)
            lines.append(String(decoding: lineData, as: UTF8.self))
        }
        outputLock.unlock()
        for line in lines { processLine(line) }
    }

    private func processLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))

        // Performance stats from the in-guest reporter — parse and hide from the log.
        if line.contains("[MSCSTATS]") {
            parseStats(line)
            return
        }

        // Learn the guest IP from our /init banner ("[appliance] dhcp: 192.168.64.X/..."),
        // then start the host-side UDP relay so LAN + playit can reach BDS.
        if guestIP == nil, line.contains("[appliance] dhcp:"),
           let ip = Self.parseGuestIP(line) {
            guestIP = ip
            startRelay(guestIP: ip)
        }

        emitLine(line)
    }

    // MARK: - Performance stats (from the in-guest [MSCSTATS] reporter)

    struct VMStats {
        let cpuPercent: Double?
        let memUsedMB: Double?
        let memTotalMB: Double?
    }

    /// Latest guest CPU/memory snapshot for the Performance tab. Thread-safe.
    func currentStats() -> VMStats {
        statsLock.lock(); defer { statsLock.unlock() }
        return VMStats(cpuPercent: lastCpuPercent, memUsedMB: lastMemUsedMB, memTotalMB: lastMemTotalMB)
    }

    private func parseStats(_ line: String) {
        // "[MSCSTATS] cpu=NN memUsedMB=NN memTotalMB=NN"
        var cpu: Double?, used: Double?, total: Double?
        for token in line.split(separator: " ") {
            let kv = token.split(separator: "=", maxSplits: 1)
            guard kv.count == 2, let value = Double(kv[1]) else { continue }
            switch kv[0] {
            case "cpu":        cpu = value
            case "memUsedMB":  used = value
            case "memTotalMB": total = value
            default:           break
            }
        }
        statsLock.lock()
        if let cpu { lastCpuPercent = cpu }
        if let used { lastMemUsedMB = used }
        if let total { lastMemTotalMB = total }
        statsLock.unlock()
    }

    static func parseGuestIP(_ line: String) -> String? {
        // matches the first 192.168.x.y in the line
        guard let r = line.range(of: #"\d{1,3}(\.\d{1,3}){3}"#, options: .regularExpression) else { return nil }
        return String(line[r])
    }

    private func startRelay(guestIP: String) {
        do {
            // Bind 0.0.0.0 so both LAN clients and playit (127.0.0.1) are covered.
            let r = try UDPRelay(listenHost: "0.0.0.0", listenPort: bedrockPort,
                                 guestHost: guestIP, guestPort: bedrockPort)
            r.start()
            relay = r
            emitLine("[VM] UDP relay 0.0.0.0:\(bedrockPort) -> \(guestIP):\(bedrockPort) started.")
        } catch {
            emitLine("[VM] WARNING: failed to start UDP relay: \(error.localizedDescription)")
        }
    }

    // MARK: - Send command (host -> guest console = BDS stdin)

    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        guard isRunning, let inPipe = guestInPipe else {
            lastCommandError = "Server is not running."
            return false
        }
        let payload = command.hasSuffix("\n") ? command : command + "\n"
        guard let data = payload.data(using: .utf8) else {
            lastCommandError = "Could not encode command."
            return false
        }
        inPipe.fileHandleForWriting.write(data)
        lastCommandError = nil
        return true
    }

    // MARK: - Stop (graceful) and terminate (force)

    @discardableResult
    func stop() -> Bool {
        guard isRunning else {
            lastCommandError = "Server is not running."
            return false
        }
        // A second Stop press (while a graceful stop is already pending) forces an
        // immediate power-off — handy if BDS never came up and the guest is at a shell.
        if forceStopWorkItem != nil {
            emitLine("[VM] Forcing the VM to power off now...")
            forceStopWorkItem?.cancel()
            forceStopWorkItem = nil
            forceStopVM()
            return true
        }
        emitLine("[VM] Sending 'stop' to BDS (world saves, then the VM powers off). Press Stop again to force.")
        _ = sendCommand("stop")

        // Fallback: if the guest doesn't power off in time, force-stop the VM.
        let work = DispatchWorkItem { [weak self] in
            self?.emitLine("[VM] Graceful stop timed out — forcing power off.")
            self?.forceStopVM()
        }
        forceStopWorkItem = work
        vmQueue.asyncAfter(deadline: .now() + 20, execute: work)
        return true
    }

    func terminate() {
        forceStopVM()
    }

    /// Force power-off the VM and signal termination. Safe to call repeatedly.
    private func forceStopVM() {
        vmQueue.async { [weak self] in
            guard let self else { return }
            self.forceStopWorkItem?.cancel()
            self.forceStopWorkItem = nil
            guard let vm = self.vm, vm.state == .running || vm.state == .paused else {
                // Nothing running (or already stopped) — make sure the app is notified.
                self.teardown()
                self.fireDidTerminate()
                return
            }
            vm.stop { [weak self] _ in
                // VZVirtualMachine.stop() is a hard power-off and does NOT call
                // guestDidStop, so tear down and notify the app here.
                self?.teardown()
                self?.fireDidTerminate()
            }
        }
    }

    // MARK: - Cleanup / termination signalling

    private func teardown() {
        forceStopWorkItem?.cancel(); forceStopWorkItem = nil
        relay?.cancel(); relay = nil
        guestOutPipe?.fileHandleForReading.readabilityHandler = nil
        guestOutPipe = nil
        guestInPipe = nil
        guestIP = nil
        stateLock.lock(); _isRunning = false; stateLock.unlock()
    }

    private func fireDidTerminate() {
        stateLock.lock()
        if hasFiredTerminate { stateLock.unlock(); return }
        hasFiredTerminate = true
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onDidTerminate?() }
    }

    // MARK: - Helpers

    private func emitLine(_ line: String) {
        DispatchQueue.main.async { [weak self] in self?.onOutputLine?(line) }
    }

    private func flushPendingOutput() {
        outputLock.lock()
        guard !pendingOutput.isEmpty else { outputLock.unlock(); return }
        let data = pendingOutput; pendingOutput.removeAll(keepingCapacity: false)
        outputLock.unlock()
        emitLine(String(decoding: data, as: UTF8.self))
    }

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "MinecraftServerController.VMBedrockServerBackend", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - VZVirtualMachineDelegate

extension VMBedrockServerBackend: VZVirtualMachineDelegate {
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        flushPendingOutput()
        emitLine("[VM] Guest powered off (server stopped).")
        teardown()
        fireDidTerminate()
    }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        flushPendingOutput()
        emitLine("[VM] Guest stopped with error: \(error.localizedDescription)")
        teardown()
        fireDidTerminate()
    }
}
