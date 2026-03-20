//
//  AppUtilities.swift
//  MinecraftServerController
//
//  Pure utility functions with no dependency on app state.
//  Namespaced under a caseless enum so they can never be instantiated.
//

import Foundation
import Darwin   // getifaddrs / inet_ntop

enum AppUtilities {

    // MARK: - Networking

    /// Returns the first IPv4 address on any `en*` interface (Wi-Fi / Ethernet).
    /// Returns `nil` when no suitable address is found.
    static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return nil
        }

        var ptr = first
        while true {
            let interface = ptr.pointee

            guard let addr = interface.ifa_addr else {
                if let next = interface.ifa_next {
                    ptr = next
                    continue
                } else {
                    break
                }
            }

            let family = addr.pointee.sa_family
            if family == sa_family_t(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") { // Wi-Fi / Ethernet
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addrInPtr in
                        var addrIn = addrInPtr.pointee
                        inet_ntop(AF_INET, &addrIn.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                    }
                    address = String(cString: buffer)
                    break
                }
            }

            if let next = interface.ifa_next {
                ptr = next
            } else {
                break
            }
        }

        freeifaddrs(ifaddr)
        return address
    }

    /// Fetches the machine's public (WAN) IP address from api.ipify.org.
    /// Calls `completion` on the main queue with the IP string, or `nil` on failure.
    static func fetchPublicIPAddress(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.ipify.org") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            let ip: String?
            if let data, error == nil {
                let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ip = (raw?.split(separator: ".").count == 4) ? raw : nil
            } else {
                ip = nil
            }
            DispatchQueue.main.async { completion(ip) }
        }.resume()
    }

    /// Returns the default gateway IPv4 address for the current network route when it
    /// can be determined. This is used to prefill router-guide runtime context.
    ///
    /// Strategy:
    /// 1. Prefer `route -n get default` because it is direct and stable on macOS.
    /// 2. Fall back to `netstat -rn -f inet` parsing if needed.
    static func defaultGatewayIPAddress() -> String? {
        if let output = runAndCapture(executable: "/usr/sbin/route", arguments: ["-n", "get", "default"]),
           let gateway = parseGatewayFromRouteGetOutput(output) {
            return gateway
        }

        if let output = runAndCapture(executable: "/usr/sbin/netstat", arguments: ["-rn", "-f", "inet"]),
           let gateway = parseGatewayFromNetstatOutput(output) {
            return gateway
        }

        return nil
    }

    private static func runAndCapture(executable: String, arguments: [String]) -> String? {
        guard FileManager.default.fileExists(atPath: executable) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
    }

    private static func parseGatewayFromRouteGetOutput(_ output: String) -> String? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("gateway:") else { continue }

            let value = line
                .replacingOccurrences(of: "gateway:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if isLikelyIPv4Address(value) {
                return value
            }
        }

        return nil
    }

    private static func parseGatewayFromNetstatOutput(_ output: String) -> String? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("default") else { continue }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }

            let candidate = parts[1]
            if isLikelyIPv4Address(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func isLikelyIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let octet = Int(part), (0...255).contains(octet) else {
                return false
            }
        }

        return true
    }

    // MARK: - Formatting

    /// Formats a byte count as a short human-readable string: "1.8 GB", "950 MB", etc.
    static func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        let oneKB = 1024.0
        let oneMB = oneKB * 1024.0
        let oneGB = oneMB * 1024.0

        if b >= oneGB {
            return String(format: "%.1f GB", b / oneGB)
        } else if b >= oneMB {
            return String(format: "%.0f MB", b / oneMB)
        } else if b >= oneKB {
            return String(format: "%.0f KB", b / oneKB)
        } else {
            return "\(Int(b)) B"
        }
    }

    /// Returns a wall-clock timestamp string in HH:mm:ss format.
    static func timestampString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: Date())
    }

    // MARK: - File System

    /// Recursively sums the sizes of all regular files under `url`.
    /// Skips hidden files and silently ignores individual file errors.
    static func directorySizeInBytes(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true, let fileSize = values.fileSize {
                    total += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        return total
    }

    // MARK: - Console

    /// Strips ANSI SGR escape sequences (e.g. `ESC[32m`) from a console line.
    static func sanitized(_ line: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*m"
        return line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
