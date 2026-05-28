//
//  BedrockLevelDB.swift
//  MinecraftServerController
//
//  Self-contained LevelDB SST (table) reader and Snappy decompressor for
//  reading Bedrock Edition player data from the world's LevelDB database.
//  No external dependencies — pure Swift.
//
//  LevelDB table format (v1):
//    - Footer: 48 bytes at end-of-file (two block handles + 8-byte magic)
//    - Index block: prefix-compressed key→block-handle records
//    - Data blocks: prefix-compressed key→value records (optionally Snappy-compressed)
//    - Internal key: user_key + 8-byte suffix (7-byte seq LE + 1-byte type)
//

import Foundation

// MARK: - Public API

enum BedrockLevelDB {

    private static let kMagicLo: UInt32 = 0x24f09b77
    private static let kMagicHi: UInt32 = 0x57fb808b

    /// Reads all `player_<xuid>` and `~local_player` entries from the LevelDB
    /// database at `dbPath`. Returns a mapping of user-key string → raw NBT bytes.
    static func readPlayerData(dbPath: String) -> [String: Data] {
        var result: [String: Data] = [:]
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return result }

        let ldbFiles = contents
            .filter { $0.hasSuffix(".ldb") }
            .map { URL(fileURLWithPath: dbPath).appendingPathComponent($0).path }

        for path in ldbFiles {
            parseSSTFile(at: path, into: &result)
        }
        return result
    }

    // MARK: - SST file parsing

    private static func parseSSTFile(at path: String, into result: inout [String: Data]) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        guard data.count >= 48 else { return }

        // ── Verify footer magic ────────────────────────────────────────────
        let magicOffset = data.count - 8
        let magicLo = data.readLE32(at: magicOffset)
        let magicHi = data.readLE32(at: magicOffset + 4)
        guard magicLo == kMagicLo, magicHi == kMagicHi else { return }

        // ── Parse footer: metaindex handle, then index handle ──────────────
        var cursor = data.count - 48
        guard let _ = readVarint(data: data, cursor: &cursor),
              let _ = readVarint(data: data, cursor: &cursor),
              let indexOffset = readVarint(data: data, cursor: &cursor),
              let indexSize   = readVarint(data: data, cursor: &cursor) else { return }

        // ── Read + parse index block ───────────────────────────────────────
        guard let indexBlock = readBlock(data: data, offset: Int(indexOffset), size: Int(indexSize)) else { return }
        let dataHandles = parseIndexBlock(indexBlock)

        // ── For each data block, parse key-value records ───────────────────
        for (blockOffset, blockSize) in dataHandles {
            guard let dataBlock = readBlock(data: data, offset: Int(blockOffset), size: Int(blockSize)) else { continue }
            parseDataBlock(dataBlock, into: &result)
        }
    }

    // MARK: - Block reading

    /// Reads a block from file data: checks compression byte, decompresses if Snappy.
    private static func readBlock(data: Data, offset: Int, size: Int) -> Data? {
        guard offset >= 0, size >= 0, offset + size + 5 <= data.count else { return nil }
        let type = data[offset + size]
        let raw  = data[offset..<(offset + size)]
        switch type {
        case 0: return Data(raw)
        case 1: return Snappy.decompress(Data(raw))
        default: return nil
        }
    }

    // MARK: - Index block parsing

    /// Returns (offset, size) handles for each data block listed in the index.
    private static func parseIndexBlock(_ block: Data) -> [(UInt64, UInt64)] {
        var handles: [(UInt64, UInt64)] = []
        guard block.count >= 4 else { return handles }

        let restartCount = Int(block.readLE32(at: block.count - 4))
        let restartArrayStart = block.count - 4 - restartCount * 4
        guard restartArrayStart >= 0 else { return handles }

        var cursor = 0
        var prevKey = Data()

        while cursor < restartArrayStart {
            guard let sharedLen    = readVarint(data: block, cursor: &cursor),
                  let nonSharedLen = readVarint(data: block, cursor: &cursor),
                  let valueLen     = readVarint(data: block, cursor: &cursor) else { break }

            let ns = Int(nonSharedLen), vl = Int(valueLen)
            guard cursor + ns + vl <= restartArrayStart else { break }

            prevKey = Data(prevKey.prefix(Int(sharedLen))) + block[cursor..<(cursor + ns)]
            cursor += ns

            var valCursor = cursor
            if let dataOffset = readVarint(data: block, cursor: &valCursor),
               let dataSize   = readVarint(data: block, cursor: &valCursor) {
                handles.append((dataOffset, dataSize))
            }
            cursor += vl
        }
        return handles
    }

    // MARK: - Data block parsing

    /// Iterates records in a data block; extracts Bedrock player entries.
    private static func parseDataBlock(_ block: Data, into result: inout [String: Data]) {
        guard block.count >= 4 else { return }

        let restartCount = Int(block.readLE32(at: block.count - 4))
        let restartArrayStart = block.count - 4 - restartCount * 4
        guard restartArrayStart >= 0 else { return }

        var cursor = 0
        var prevKey = Data()

        while cursor < restartArrayStart {
            guard let sharedLen    = readVarint(data: block, cursor: &cursor),
                  let nonSharedLen = readVarint(data: block, cursor: &cursor),
                  let valueLen     = readVarint(data: block, cursor: &cursor) else { break }

            let ns = Int(nonSharedLen), vl = Int(valueLen)
            guard cursor + ns + vl <= block.count else { break }

            let internalKey = Data(prevKey.prefix(Int(sharedLen))) + block[cursor..<(cursor + ns)]
            prevKey = internalKey
            cursor += ns

            let value = block[cursor..<(cursor + vl)]
            cursor += vl

            // Internal key = user_key + 8-byte suffix: low byte of LE uint64 = record type
            guard internalKey.count > 8 else { continue }
            let typeAndSeq = internalKey.readLE64(at: internalKey.count - 8)
            guard (typeAndSeq & 0xFF) == 1 else { continue } // 0 = deletion, 1 = value

            let userKey = internalKey.dropLast(8)
            guard let keyStr = String(data: userKey, encoding: .utf8) else { continue }
            guard keyStr.hasPrefix("player_") || keyStr == "~local_player" else { continue }

            // LevelDB iterates newest-first within a SST; keep first occurrence per key
            if result[keyStr] == nil {
                result[keyStr] = Data(value)
            }
        }
    }

    // MARK: - Varint reader

    @discardableResult
    static func readVarint(data: Data, cursor: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift = 0
        while cursor < data.count {
            let byte = data[cursor]; cursor += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}

// MARK: - Data extensions

private extension Data {
    func readLE32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
             | (UInt32(self[offset + 1]) << 8)
             | (UInt32(self[offset + 2]) << 16)
             | (UInt32(self[offset + 3]) << 24)
    }

    func readLE64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return UInt64(readLE32(at: offset)) | (UInt64(readLE32(at: offset + 4)) << 32)
    }
}

// MARK: - Snappy decompressor

enum Snappy {

    /// Decompresses a Snappy-compressed block (raw/block format, not the framing format).
    /// Returns nil on any parse error or if the output exceeds the sanity cap.
    static func decompress(_ input: Data) -> Data? {
        var src = 0

        // Uncompressed length (varint)
        guard let uncompressedLen = readVarint(input, cursor: &src) else { return nil }
        let outLen = Int(uncompressedLen)
        guard outLen >= 0, outLen <= 64 * 1024 * 1024 else { return nil }

        var output = [UInt8]()
        output.reserveCapacity(outLen)

        while src < input.count {
            let tag = input[src]; src += 1

            switch tag & 0x03 {

            case 0x00: // Literal
                let lenBits = Int(tag >> 2)
                let literalLen: Int
                if lenBits < 60 {
                    literalLen = lenBits + 1
                } else {
                    let extraCount = lenBits - 59   // 1, 2, 3, or 4
                    guard src + extraCount <= input.count else { return nil }
                    var len = 0
                    for i in 0..<extraCount { len |= Int(input[src + i]) << (i * 8) }
                    src += extraCount
                    literalLen = len + 1
                }
                guard src + literalLen <= input.count else { return nil }
                output.append(contentsOf: input[src..<(src + literalLen)])
                src += literalLen

            case 0x01: // Copy 1-byte offset  (ooolll01 | offset_lo)
                let length = Int((tag >> 2) & 0x07) + 4
                guard src < input.count else { return nil }
                let offsetLo = Int(input[src]); src += 1
                let copyOffset = (Int(tag >> 5) << 8) | offsetLo
                guard copyOffset > 0, copyOffset <= output.count else { return nil }
                let base = output.count - copyOffset
                for i in 0..<length { output.append(output[base + (i % copyOffset)]) }

            case 0x02: // Copy 2-byte offset  (llllll10 | offset_lo | offset_hi)
                let length = Int(tag >> 2) + 1
                guard src + 2 <= input.count else { return nil }
                let copyOffset = Int(input[src]) | (Int(input[src + 1]) << 8); src += 2
                guard copyOffset > 0, copyOffset <= output.count else { return nil }
                let base = output.count - copyOffset
                for i in 0..<length { output.append(output[base + (i % copyOffset)]) }

            case 0x03: // Copy 4-byte offset  (llllll11 | 4-byte LE offset)
                let length = Int(tag >> 2) + 1
                guard src + 4 <= input.count else { return nil }
                let copyOffset = Int(input[src])
                                | (Int(input[src + 1]) << 8)
                                | (Int(input[src + 2]) << 16)
                                | (Int(input[src + 3]) << 24)
                src += 4
                guard copyOffset > 0, copyOffset <= output.count else { return nil }
                let base = output.count - copyOffset
                for i in 0..<length { output.append(output[base + (i % copyOffset)]) }

            default:
                return nil
            }
        }

        return Data(output)
    }

    private static func readVarint(_ data: Data, cursor: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift = 0
        while cursor < data.count {
            let byte = data[cursor]; cursor += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}
