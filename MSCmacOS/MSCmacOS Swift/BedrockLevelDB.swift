//
//  BedrockLevelDB.swift
//  MinecraftServerController
//
//  Self-contained LevelDB SST (table) reader for reading Bedrock Edition
//  player data from the world's LevelDB database.
//  No external Swift dependencies — uses the system zlib via `import zlib`.
//
//  LevelDB table format (v1):
//    - Footer: 48 bytes at end-of-file (two block handles + 8-byte magic)
//    - Index block: prefix-compressed key→block-handle records
//    - Data blocks: prefix-compressed key→value records
//    - Block compression: type byte follows the raw block bytes in the file
//        0 = uncompressed, 4 = raw deflate (zlib wbits=-15) — used by Bedrock BDS
//    - Internal key: user_key + 8-byte suffix (7-byte seq LE + 1-byte type)
//

import Foundation
import zlib

// MARK: - Public API

enum BedrockLevelDB {

    // Standard LevelDB table magic: 0xdb4775248b80fb57
    // Stored LE in file bytes: 57 fb 80 8b  24 75 47 db
    private static let kMagicLo: UInt32 = 0x8b80fb57   // bytes[40..43] in footer
    private static let kMagicHi: UInt32 = 0xdb477524   // bytes[44..47] in footer

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

    /// Reads a block from file data: checks compression type byte, decompresses if needed.
    /// Compression byte is stored immediately after the block bytes (at offset+size).
    /// Type 0 = uncompressed; Type 4 = raw deflate (wbits=-15), used by Bedrock BDS.
    private static func readBlock(data: Data, offset: Int, size: Int) -> Data? {
        guard offset >= 0, size >= 0, offset + size + 5 <= data.count else { return nil }
        let type = data[offset + size]
        let raw  = data[offset..<(offset + size)]
        switch type {
        case 0: return Data(raw)
        case 4: return ZlibRaw.decompress(Data(raw))
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

            // Internal key = user_key + 8-byte suffix; low byte of LE uint64 = record type
            guard internalKey.count > 8 else { continue }
            let typeAndSeq = internalKey.readLE64(at: internalKey.count - 8)
            guard (typeAndSeq & 0xFF) == 1 else { continue } // 0 = deletion, 1 = value

            let userKey = internalKey.dropLast(8)
            guard let keyStr = String(data: userKey, encoding: .utf8) else { continue }
            guard keyStr.hasPrefix("player_") || keyStr == "~local_player" else { continue }

            // Keep first occurrence per key (newest version wins within an SST)
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

// MARK: - Raw deflate decompressor (zlib wbits = -15)

/// Decompresses a raw deflate stream (no zlib/gzip header) using the system zlib.
/// This is the compression format Bedrock BDS uses for all LevelDB blocks (type=4).
enum ZlibRaw {

    static func decompress(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }

        var stream = z_stream()
        // inflateInit2 with windowBits=-15 selects raw deflate (no header/trailer)
        let initResult = input.withUnsafeBytes { ptr in
            inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initResult == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        // Start with 4× the compressed size as a guess; grow if needed
        var output = Data(count: max(input.count * 4, 4096))
        var totalOut = 0

        var status: Int32 = Z_OK
        input.withUnsafeBytes { srcPtr in
            guard let srcBase = srcPtr.baseAddress else { return }
            stream.next_in  = UnsafeMutablePointer<Bytef>(mutating: srcBase.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(input.count)

            while status != Z_STREAM_END {
                let needed = totalOut + 4096
                if needed > output.count {
                    output.count = needed + 4096
                }

                let capacity = output.count
                output.withUnsafeMutableBytes { dstPtr in
                    guard let dstBase = dstPtr.baseAddress else { return }
                    stream.next_out  = dstBase.advanced(by: totalOut).assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(capacity - totalOut)
                    status = inflate(&stream, Z_NO_FLUSH)
                    totalOut = Int(stream.total_out)
                }

                if status == Z_STREAM_END { break }
                guard status == Z_OK || status == Z_BUF_ERROR else { return }
                if stream.avail_in == 0 { break }
            }
        }

        guard status == Z_STREAM_END || status == Z_OK else { return nil }
        output.count = totalOut
        return output
    }
}
