//
//  BedrockLevelDB.swift
//  MinecraftServerController
//
//  Self-contained LevelDB reader for Bedrock Edition player data. Reads BOTH
//  the compacted SST (.ldb) tables AND the write-ahead log (.log), so recently
//  written records that LevelDB has not yet compacted (e.g. after a short first
//  session) are still found.
//  No external Swift dependencies — uses the system zlib via `import zlib`.
//
//  LevelDB table (.ldb) format (v1):
//    - Footer: 48 bytes at end-of-file (two block handles + 8-byte magic)
//    - Index block: prefix-compressed key→block-handle records
//    - Data blocks: prefix-compressed key→value records
//    - Block compression: type byte follows the raw block bytes in the file
//        0 = uncompressed, 4 = raw deflate (zlib wbits=-15) — used by Bedrock BDS
//    - Internal key: user_key + 8-byte suffix (7-byte seq LE + 1-byte type)
//
//  LevelDB write-ahead log (.log) format:
//    - A sequence of 32 KB blocks; each holds physical records with a 7-byte
//      header: crc(4, LE) + length(2, LE) + type(1). Type 1=FULL, 2=FIRST,
//      3=MIDDLE, 4=LAST — a logical record may be fragmented across blocks.
//      When < 7 bytes remain in a block they are a zero-padded trailer.
//    - Each assembled logical record is a WriteBatch: seq(8, LE) + count(4, LE),
//      then `count` ops. Each op: type(1) [1=value, 0=deletion], varint-prefixed
//      key, and (for value ops) a varint-prefixed value.
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
    ///
    /// Reads the compacted SST tables first, then overlays the write-ahead log(s):
    /// the log holds the newest writes that have not yet been compacted into an
    /// `.ldb` table (e.g. a short session whose data never triggered a flush), so
    /// log entries override table entries and log deletions remove keys.
    static func readPlayerData(dbPath: String) -> [String: Data] {
        var result: [String: Data] = [:]
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dbPath) else { return result }

        // 1. Compacted tables (older, already-flushed data).
        let ldbFiles = contents
            .filter { $0.hasSuffix(".ldb") }
            .map { URL(fileURLWithPath: dbPath).appendingPathComponent($0).path }
        for path in ldbFiles {
            parseSSTFile(at: path, into: &result)
        }

        // 2. Write-ahead log(s) — newest writes, override the tables. Sorted so a
        //    higher-numbered (newer) log is applied last and wins on conflicts.
        let logFiles = contents
            .filter { $0.hasSuffix(".log") }
            .sorted()
            .map { URL(fileURLWithPath: dbPath).appendingPathComponent($0).path }
        for path in logFiles {
            parseLogFile(at: path, into: &result)
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

    // MARK: - Write-ahead log (.log) parsing

    private static let kLogBlockSize  = 32768   // LevelDB log block size
    private static let kLogHeaderSize = 7       // crc(4) + length(2) + type(1)

    /// Reassembles logical records from a `.log` file and applies each contained
    /// WriteBatch. Records are physically fragmented into FULL/FIRST/MIDDLE/LAST
    /// pieces across 32 KB blocks; `pending` accumulates a multi-block record.
    private static func parseLogFile(at path: String, into result: inout [String: Data]) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }

        var pending = Data()   // fragments of an in-progress (FIRST…LAST) record
        var offset  = 0

        while offset + kLogHeaderSize <= data.count {
            // When fewer than a header's worth of bytes remain in the current
            // 32 KB block, they are a zero-padded trailer — skip to the next block.
            let intoBlock = offset % kLogBlockSize
            if kLogBlockSize - intoBlock < kLogHeaderSize {
                offset += (kLogBlockSize - intoBlock)
                continue
            }

            // Header: skip the 4-byte CRC (not verified), read length + type.
            let length = Int(data.readLE16(at: offset + 4))
            let type   = data[offset + 6]
            offset += kLogHeaderSize

            guard length >= 0, offset + length <= data.count else { break }
            let fragment = data[offset..<(offset + length)]
            offset += length

            switch type {
            case 1: // FULL — a complete record on its own
                applyWriteBatch(Data(fragment), into: &result)
                pending.removeAll(keepingCapacity: true)
            case 2: // FIRST — start of a fragmented record
                pending = Data(fragment)
            case 3: // MIDDLE
                pending.append(contentsOf: fragment)
            case 4: // LAST — completes the fragmented record
                pending.append(contentsOf: fragment)
                applyWriteBatch(pending, into: &result)
                pending.removeAll(keepingCapacity: true)
            default: // zero padding / unknown — drop any partial record
                pending.removeAll(keepingCapacity: true)
            }
        }
    }

    /// Parses one WriteBatch payload and applies its player operations to `result`.
    /// Log writes are newer than any SST, so value ops overwrite and deletion ops
    /// remove. Non-player keys are skipped but still length-decoded to advance.
    private static func applyWriteBatch(_ batch: Data, into result: inout [String: Data]) {
        guard batch.count >= 12 else { return }
        let count = batch.readLE32(at: 8)
        var cursor = 12   // skip sequence(8) + count(4)

        func isPlayerKey(_ key: String) -> Bool {
            key.hasPrefix("player_") || key == "~local_player"
        }

        var applied: UInt32 = 0
        while applied < count, cursor < batch.count {
            let opType = batch[cursor]; cursor += 1

            guard let keyLen = readVarint(data: batch, cursor: &cursor) else { return }
            let kl = Int(keyLen)
            guard cursor + kl <= batch.count else { return }
            let keyData = batch[cursor..<(cursor + kl)]
            cursor += kl
            let keyStr = String(data: keyData, encoding: .utf8)

            switch opType {
            case 1: // value
                guard let valLen = readVarint(data: batch, cursor: &cursor) else { return }
                let vl = Int(valLen)
                guard cursor + vl <= batch.count else { return }
                let valData = batch[cursor..<(cursor + vl)]
                cursor += vl
                if let keyStr, isPlayerKey(keyStr) {
                    result[keyStr] = Data(valData)
                }
            case 0: // deletion (no value payload)
                if let keyStr, isPlayerKey(keyStr) {
                    result.removeValue(forKey: keyStr)
                }
            default: // unknown op — can't safely advance further in this batch
                return
            }
            applied += 1
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
    func readLE16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

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
