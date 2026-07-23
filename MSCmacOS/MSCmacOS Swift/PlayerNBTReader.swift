//
//  PlayerNBTReader.swift
//  MinecraftServerController
//
//  Parses a Java Edition player .dat file (GZIP-compressed NBT big-endian) and
//  extracts PlayerStats and InventoryItem values.
//
//  The NBT reader here is self-contained and intentionally separate from the one
//  in WorldSlotManager — that one operates at level.dat scope and is private.
//

import Foundation
import zlib

enum PlayerNBTReader {

    // MARK: - Public API

    /// Reads and decompresses a player .dat file, then extracts both stats and inventory.
    static func readAll(from datFilePath: String) -> (stats: PlayerStats?, inventory: [InventoryItem]) {
        guard let root = parsePlayerDat(at: datFilePath) else { return (nil, []) }
        return (extractStats(from: root), extractInventory(from: root))
    }

    // MARK: - File loading + GZIP decompression

    private static func parsePlayerDat(at path: String) -> NBTValue? {
        guard let compressedData = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard let raw = gunzip(compressedData) else { return nil }
        var reader = NBTReader(data: raw)
        return try? reader.readRootCompound()
    }

    /// Decompresses GZIP data using zlib (inflateInit2 with gzip auto-detect).
    private static func gunzip(_ data: Data) -> Data? {
        var inBytes = [UInt8](data)
        var stream = z_stream()
        // 32 + MAX_WBITS tells zlib to auto-detect gzip/zlib wrapping
        guard inflateInit2_(&stream, 32 + MAX_WBITS, ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let chunkSize = 65536
        var chunk = [Bytef](repeating: 0, count: chunkSize)
        var output = Data()
        var finalStatus: Int32 = Z_OK

        inBytes.withUnsafeMutableBufferPointer { inBuf in
            stream.next_in  = inBuf.baseAddress!
            stream.avail_in = uInt(inBuf.count)
            var status: Int32 = Z_OK
            while status == Z_OK {
                chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out  = outBuf.baseAddress!
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 { output.append(contentsOf: chunk.prefix(produced)) }
            }
            finalStatus = status
        }

        return finalStatus == Z_STREAM_END ? output : nil
    }

    // MARK: - Stats extraction

    private static func extractStats(from root: NBTValue) -> PlayerStats? {
        guard case .compound(let dict) = root else { return nil }

        // Health — TAG_Float
        let health: Float
        if case .float(let v) = dict["Health"] { health = v } else { health = 20 }

        // Max health from Attributes list (both old and new key names)
        let maxHealth: Float = {
            if case .list(let attrs) = dict["Attributes"] {
                for attr in attrs {
                    guard case .compound(let a) = attr else { continue }
                    guard case .string(let name) = a["Name"] else { continue }
                    if name == "minecraft:generic.max_health" || name == "generic.maxHealth" {
                        if case .double(let base) = a["Base"] { return Float(base) }
                    }
                }
            }
            return 20.0
        }()

        let foodLevel: Int
        if case .int(let v) = dict["FoodLevel"] { foodLevel = Int(v) } else { foodLevel = 20 }

        let xpLevel: Int
        if case .int(let v) = dict["XpLevel"] { xpLevel = Int(v) } else { xpLevel = 0 }

        let xpTotal: Int
        if case .int(let v) = dict["XpTotal"] { xpTotal = Int(v) } else { xpTotal = 0 }

        let gameMode: Int
        if case .int(let v) = dict["playerGameType"] { gameMode = Int(v) } else { gameMode = 0 }

        let score: Int
        if case .int(let v) = dict["Score"] { score = Int(v) } else { score = 0 }

        // Position — TAG_List of TAG_Double
        var posX = 0.0, posY = 0.0, posZ = 0.0
        if case .list(let posList) = dict["Pos"], posList.count >= 3 {
            if case .double(let v) = posList[0] { posX = v }
            if case .double(let v) = posList[1] { posY = v }
            if case .double(let v) = posList[2] { posZ = v }
        }

        // Dimension — TAG_String (1.16+) or TAG_Int (pre-1.16)
        let dimension: String
        if case .string(let v) = dict["Dimension"] {
            dimension = v
        } else if case .int(let v) = dict["Dimension"] {
            switch v {
            case -1: dimension = "minecraft:the_nether"
            case  1: dimension = "minecraft:the_end"
            default: dimension = "minecraft:overworld"
            }
        } else {
            dimension = "minecraft:overworld"
        }

        return PlayerStats(
            health: health,
            maxHealth: maxHealth,
            foodLevel: foodLevel,
            xpLevel: xpLevel,
            xpTotal: xpTotal,
            gameMode: gameMode,
            posX: posX,
            posY: posY,
            posZ: posZ,
            dimension: dimension,
            score: score
        )
    }

    // MARK: - Inventory extraction

    private static func extractInventory(from root: NBTValue) -> [InventoryItem] {
        guard case .compound(let dict) = root,
              case .list(let items) = dict["Inventory"] else { return [] }

        return items.compactMap { entry -> InventoryItem? in
            guard case .compound(let e) = entry else { return nil }

            // Slot — TAG_Byte (standard) or TAG_Int (some mods/versions)
            let slot: Int
            if case .byte(let v) = e["Slot"] { slot = Int(v) }
            else if case .int(let v) = e["Slot"] { slot = Int(v) }
            else { return nil }

            // Item ID — always TAG_String
            guard case .string(let itemID) = e["id"] else { return nil }

            // Count — TAG_Byte/Int with capital C (pre-1.20.5) or lowercase (1.20.5+)
            let count: Int
            if case .byte(let v) = e["Count"]      { count = max(1, Int(v)) }
            else if case .int(let v) = e["Count"]  { count = max(1, Int(v)) }
            else if case .int(let v) = e["count"]  { count = max(1, Int(v)) }  // 1.20.5+
            else                                   { count = 1 }

            // Optional item data — "tag" compound (pre-1.20.5) or "components" (1.20.5+)
            var enchantments: [ItemEnchantment] = []
            var customName: String? = nil
            var damage = 0

            if case .compound(let tag) = e["tag"] {
                // ── Pre-1.20.5 format ──────────────────────────────────────
                // Enchantments on items, or StoredEnchantments on enchanted books
                let enchList: [NBTValue]
                if case .list(let el) = tag["Enchantments"]            { enchList = el }
                else if case .list(let el) = tag["StoredEnchantments"] { enchList = el }
                else                                                    { enchList = [] }

                enchantments = enchList.compactMap { enchEntry -> ItemEnchantment? in
                    guard case .compound(let ec) = enchEntry,
                          case .string(let eid) = ec["id"] else { return nil }
                    let lvl: Int
                    if case .short(let v) = ec["lvl"]   { lvl = Int(v) }
                    else if case .int(let v) = ec["lvl"] { lvl = Int(v) }
                    else                                  { lvl = 1 }
                    return ItemEnchantment(id: eid, level: lvl)
                }

                // Custom name: tag.display.Name (JSON text component)
                if case .compound(let display) = tag["display"],
                   case .string(let nameJSON) = display["Name"] {
                    customName = parseJSONTextComponent(nameJSON)
                }

                // Damage
                if case .int(let v) = tag["Damage"] { damage = Int(v) }

            } else if case .compound(let components) = e["components"] {
                // ── 1.20.5+ component format ───────────────────────────────
                // Enchantments: minecraft:enchantments → {levels: {enchId: lvl}}
                for compKey in ["minecraft:enchantments", "minecraft:stored_enchantments"] {
                    if case .compound(let enchComp) = components[compKey],
                       case .compound(let levels) = enchComp["levels"] {
                        for (eid, val) in levels {
                            let lvl: Int
                            if case .int(let v) = val  { lvl = Int(v) }
                            else                        { lvl = 1 }
                            enchantments.append(ItemEnchantment(id: eid, level: lvl))
                        }
                    }
                }

                // Custom name: minecraft:custom_name (JSON text component string)
                if case .string(let nameJSON) = components["minecraft:custom_name"] {
                    customName = parseJSONTextComponent(nameJSON)
                }

                // Damage: minecraft:damage → int
                if case .int(let v) = components["minecraft:damage"] { damage = Int(v) }
            }

            return InventoryItem(
                slot: slot,
                itemID: itemID,
                count: count,
                enchantments: enchantments,
                customName: customName,
                damage: damage
            )
        }
    }

    /// Extracts the plain text string from a Minecraft JSON text component.
    /// e.g. {"text":"My Sword"} → "My Sword"
    private static func parseJSONTextComponent(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String {
            return text.isEmpty ? nil : text
        }
        return raw
    }

    // MARK: - NBT Types

    private enum NBTTag: UInt8 {
        case end = 0, byte = 1, short = 2, int = 3, long = 4
        case float = 5, double = 6, byteArray = 7, string = 8
        case list = 9, compound = 10, intArray = 11, longArray = 12
    }

    // Internal — also used by extraction helpers above via pattern matching.
    enum NBTValue {
        case byte(Int8)
        case short(Int16)
        case int(Int32)
        case long(Int64)
        case float(Float)
        case double(Double)
        case string(String)
        case byteArray(Data)
        case list([NBTValue])
        case compound([String: NBTValue])
        case intArray([Int32])
        case longArray([Int64])
    }

    private struct NBTReader {
        let data: Data
        var offset: Int = 0

        mutating func readRootCompound() throws -> NBTValue {
            guard let type = NBTTag(rawValue: try readUInt8()), type == .compound else {
                throw CocoaError(.fileReadCorruptFile)
            }
            _ = try readString()   // root compound name (usually empty)
            return try readPayload(type: .compound)
        }

        mutating func readPayload(type: NBTTag) throws -> NBTValue {
            switch type {
            case .end:
                return .compound([:])
            case .byte:
                return .byte(Int8(bitPattern: try readUInt8()))
            case .short:
                return .short(try readInt16())
            case .int:
                return .int(try readInt32())
            case .long:
                return .long(try readInt64())
            case .float:
                return .float(Float(bitPattern: UInt32(bitPattern: try readInt32())))
            case .double:
                return .double(Double(bitPattern: UInt64(bitPattern: try readInt64())))
            case .byteArray:
                let count = max(0, Int(try readInt32()))
                return .byteArray(try readData(count: count))
            case .string:
                return .string(try readString())
            case .list:
                guard let elemType = NBTTag(rawValue: try readUInt8()) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let count = max(0, Int(try readInt32()))
                var values: [NBTValue] = []
                values.reserveCapacity(count)
                for _ in 0..<count { values.append(try readPayload(type: elemType)) }
                return .list(values)
            case .compound:
                var dict: [String: NBTValue] = [:]
                while true {
                    let rawType = try readUInt8()
                    guard rawType != NBTTag.end.rawValue else { break }
                    guard let nestedType = NBTTag(rawValue: rawType) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let name = try readString()
                    dict[name] = try readPayload(type: nestedType)
                }
                return .compound(dict)
            case .intArray:
                let count = max(0, Int(try readInt32()))
                var arr: [Int32] = []; arr.reserveCapacity(count)
                for _ in 0..<count { arr.append(try readInt32()) }
                return .intArray(arr)
            case .longArray:
                let count = max(0, Int(try readInt32()))
                var arr: [Int64] = []; arr.reserveCapacity(count)
                for _ in 0..<count { arr.append(try readInt64()) }
                return .longArray(arr)
            }
        }

        mutating func readUInt8() throws -> UInt8 {
            guard offset < data.count else { throw CocoaError(.fileReadCorruptFile) }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readInt16() throws -> Int16 {
            Int16(bitPattern: UInt16(try readUnsigned(byteCount: 2)))
        }

        mutating func readInt32() throws -> Int32 {
            Int32(bitPattern: UInt32(try readUnsigned(byteCount: 4)))
        }

        mutating func readInt64() throws -> Int64 {
            Int64(bitPattern: try readUnsigned(byteCount: 8))
        }

        /// Reads `byteCount` bytes big-endian and returns them as a UInt64.
        mutating func readUnsigned(byteCount: Int) throws -> UInt64 {
            let chunk = try readData(count: byteCount)
            return chunk.withUnsafeBytes { buf in
                buf.bindMemory(to: UInt8.self).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            }
        }

        mutating func readData(count: Int) throws -> Data {
            guard count >= 0, offset + count <= data.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let range = offset..<(offset + count)
            offset += count
            return data.subdata(in: range)
        }

        mutating func readString() throws -> String {
            let length = max(0, Int(try readInt16()))
            let strData = try readData(count: length)
            return String(data: strData, encoding: .utf8) ?? ""
        }
    }
}
