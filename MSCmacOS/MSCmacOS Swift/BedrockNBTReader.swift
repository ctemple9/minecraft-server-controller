//
//  BedrockNBTReader.swift
//  MinecraftServerController
//
//  Parses a Bedrock Edition player NBT payload (raw bytes from LevelDB, no GZIP,
//  little-endian byte order) and extracts PlayerStats and InventoryItem values.
//
//  Key differences from PlayerNBTReader (Java):
//    - All multi-byte reads are little-endian.
//    - Root compound starts: type-byte (10) + LE int16 name-len + name + payload.
//    - Item ID key:   "Name" (TAG_String), not "id".
//    - Count:         "Count" (TAG_Byte) in item root.
//    - Damage:        "Damage" (TAG_Short) in item root (not inside "tag").
//    - Enchantments:  "tag.ench" list with numeric TAG_Short id + TAG_Short lvl.
//    - Pos:           TAG_List of TAG_Float (cast to Double for PlayerStats).
//    - Dimension:     "DimensionId" TAG_Int (0=overworld, 1=nether, 2=end).
//    - Armor + Offhand may be in separate lists, mapped to Java-style slot numbers.
//

import Foundation

enum BedrockNBTReader {

    // MARK: - Public API

    static func readAll(from data: Data) -> (stats: PlayerStats?, inventory: [InventoryItem]) {
        guard let root = parseRootCompound(data) else { return (nil, []) }
        return (extractStats(from: root), extractInventory(from: root))
    }

    // MARK: - Root parsing

    private static func parseRootCompound(_ data: Data) -> NBTValue? {
        var reader = NBTReader(data: data)
        return try? reader.readRootCompound()
    }

    // MARK: - Stats extraction

    private static func extractStats(from root: NBTValue) -> PlayerStats? {
        guard case .compound(let dict) = root else { return nil }

        let health: Float
        if case .float(let v) = dict["Health"] { health = v } else { health = 20 }

        let maxHealth: Float = {
            if case .list(let attrs) = dict["Attributes"] {
                for attr in attrs {
                    guard case .compound(let a) = attr else { continue }
                    guard case .string(let name) = a["Name"] else { continue }
                    if name == "minecraft:health" || name == "minecraft:generic.max_health"
                        || name == "generic.maxHealth" {
                        if case .float(let base) = a["Base"] { return base }
                        if case .double(let base) = a["Base"] { return Float(base) }
                    }
                }
            }
            return 20.0
        }()

        let foodLevel: Int
        if case .int(let v) = dict["FoodLevel"] { foodLevel = Int(v) } else { foodLevel = 20 }

        // Bedrock stores XP as PlayerLevel (int) + PlayerLevelProgress (float 0–1).
        // Java's XpLevel / XpTotal keys do not exist in Bedrock NBT.
        let xpLevel: Int
        if case .int(let v) = dict["PlayerLevel"] { xpLevel = Int(v) } else { xpLevel = 0 }

        let xpTotal: Int = {
            let level = xpLevel
            // XP needed to reach `level` from 0, using standard Minecraft formula.
            let base: Int
            if level < 17        { base = level * level + 6 * level }
            else if level < 32   { base = Int(2.5 * Double(level * level)) - 40 * level + 360 }
            else                 { base = Int(4.5 * Double(level * level)) - 162 * level + 2220 }
            // Add fractional progress within the current level.
            let progress: Float
            if case .float(let v) = dict["PlayerLevelProgress"] { progress = v } else { progress = 0 }
            let xpPerLevel = level < 16 ? (2 * level + 7) : level < 31 ? (5 * level - 38) : (9 * level - 158)
            return base + Int(Float(xpPerLevel) * progress)
        }()

        let gameMode: Int
        if case .int(let v) = dict["playerGameType"] { gameMode = Int(v) } else { gameMode = 0 }

        let score: Int
        if case .int(let v) = dict["Score"] { score = Int(v) } else { score = 0 }

        // Pos — TAG_List of TAG_Float (Bedrock) or TAG_Double (some versions)
        var posX = 0.0, posY = 0.0, posZ = 0.0
        if case .list(let posList) = dict["Pos"], posList.count >= 3 {
            switch posList[0] {
            case .float(let v):  posX = Double(v)
            case .double(let v): posX = v
            default: break
            }
            switch posList[1] {
            case .float(let v):  posY = Double(v)
            case .double(let v): posY = v
            default: break
            }
            switch posList[2] {
            case .float(let v):  posZ = Double(v)
            case .double(let v): posZ = v
            default: break
            }
        }

        // Dimension — "DimensionId" TAG_Int in Bedrock (0=overworld, 1=nether, 2=end)
        let dimension: String
        if case .int(let v) = dict["DimensionId"] {
            switch v {
            case 1:  dimension = "minecraft:the_nether"
            case 2:  dimension = "minecraft:the_end"
            default: dimension = "minecraft:overworld"
            }
        } else if case .string(let v) = dict["Dimension"] {
            dimension = v  // Some crossplay versions use the Java string key
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
        guard case .compound(let dict) = root else { return [] }

        var items: [InventoryItem] = []

        // Main inventory + hotbar (slots 0–35, slot number stored in "Slot" TAG_Byte)
        if case .list(let inv) = dict["Inventory"] {
            items += inv.compactMap { parseBedrockItem($0, slotOverride: nil) }
        }

        // Armor — Bedrock stores as a 4-element list (helmet→boots = index 0→3)
        // Map to Java slot numbers: 103=helmet, 102=chest, 101=legs, 100=boots
        let armorSlots = [103, 102, 101, 100]
        if case .list(let armor) = dict["Armor"] {
            for (index, entry) in armor.prefix(4).enumerated() {
                if let item = parseBedrockItem(entry, slotOverride: armorSlots[index]) {
                    items.append(item)
                }
            }
        }

        // Offhand — slot -106
        if case .list(let offhand) = dict["Offhand"], let first = offhand.first {
            if let item = parseBedrockItem(first, slotOverride: -106) {
                items.append(item)
            }
        }

        return items
    }

    /// Parses a single Bedrock item compound into an InventoryItem.
    /// - slotOverride: Use this slot instead of reading from the compound (for armor/offhand).
    private static func parseBedrockItem(_ entry: NBTValue, slotOverride: Int?) -> InventoryItem? {
        guard case .compound(let e) = entry else { return nil }

        // Item name — "Name" TAG_String in Bedrock (e.g. "minecraft:diamond_sword")
        guard case .string(let itemID) = e["Name"] else { return nil }
        // Skip empty/air slots
        if itemID.isEmpty || itemID == "minecraft:air" { return nil }

        // Slot
        let slot: Int
        if let forced = slotOverride {
            slot = forced
        } else if case .byte(let v) = e["Slot"]      { slot = Int(v) }
        else if case .int(let v) = e["Slot"]          { slot = Int(v) }
        else                                           { return nil }

        // Count — TAG_Byte in Bedrock root
        let count: Int
        if case .byte(let v) = e["Count"]     { count = max(1, Int(v)) }
        else if case .int(let v) = e["Count"] { count = max(1, Int(v)) }
        else                                  { count = 1 }

        // Damage — TAG_Short in item root (not inside "tag")
        let damage: Int
        if case .short(let v) = e["Damage"]   { damage = Int(v) }
        else if case .int(let v) = e["Damage"] { damage = Int(v) }
        else                                   { damage = 0 }

        // "tag" compound — enchantments and custom name
        var enchantments: [ItemEnchantment] = []
        var customName: String? = nil

        if case .compound(let tag) = e["tag"] {
            // Enchantments: "ench" list with numeric TAG_Short id + TAG_Short lvl
            let enchKey = tag["ench"] != nil ? "ench" : "StoredEnchantments"
            if case .list(let enchList) = tag[enchKey] {
                enchantments = enchList.compactMap { enchEntry -> ItemEnchantment? in
                    guard case .compound(let ec) = enchEntry else { return nil }
                    let numericID: Int
                    if case .short(let v) = ec["id"]       { numericID = Int(v) }
                    else if case .int(let v) = ec["id"]    { numericID = Int(v) }
                    else                                    { return nil }
                    let lvl: Int
                    if case .short(let v) = ec["lvl"]      { lvl = Int(v) }
                    else if case .int(let v) = ec["lvl"]   { lvl = Int(v) }
                    else                                    { lvl = 1 }
                    return ItemEnchantment(id: namespacedEnchantmentID(numericID), level: lvl)
                }
            }

            // Custom name: tag.display.Name (same JSON text component format as Java pre-1.20.5)
            if case .compound(let display) = tag["display"],
               case .string(let nameJSON) = display["Name"] {
                customName = parseJSONTextComponent(nameJSON)
            }
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

    /// Maps Bedrock numeric enchantment IDs to namespaced Java-style strings.
    private static func namespacedEnchantmentID(_ id: Int) -> String {
        let table: [Int: String] = [
             0: "minecraft:protection",
             1: "minecraft:fire_protection",
             2: "minecraft:feather_falling",
             3: "minecraft:blast_protection",
             4: "minecraft:projectile_protection",
             5: "minecraft:thorns",
             6: "minecraft:respiration",
             7: "minecraft:depth_strider",
             8: "minecraft:aqua_affinity",
             9: "minecraft:sharpness",
            10: "minecraft:smite",
            11: "minecraft:bane_of_arthropods",
            12: "minecraft:knockback",
            13: "minecraft:fire_aspect",
            14: "minecraft:looting",
            15: "minecraft:efficiency",
            16: "minecraft:silk_touch",
            17: "minecraft:unbreaking",
            18: "minecraft:fortune",
            19: "minecraft:power",
            20: "minecraft:punch",
            21: "minecraft:flame",
            22: "minecraft:infinity",
            23: "minecraft:luck_of_the_sea",
            24: "minecraft:lure",
            25: "minecraft:frost_walker",
            26: "minecraft:mending",
            27: "minecraft:binding_curse",
            28: "minecraft:vanishing_curse",
            29: "minecraft:impaling",
            30: "minecraft:riptide",
            31: "minecraft:loyalty",
            32: "minecraft:channeling",
            33: "minecraft:multishot",
            34: "minecraft:piercing",
            35: "minecraft:quick_charge",
            36: "minecraft:soul_speed",
            37: "minecraft:swift_sneak",
        ]
        return table[id] ?? "minecraft:unknown_\(id)"
    }

    /// Extracts the plain text from a Minecraft JSON text component.
    private static func parseJSONTextComponent(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String {
            return text.isEmpty ? nil : text
        }
        return raw
    }

    // MARK: - NBT Types (little-endian)

    private enum NBTTag: UInt8 {
        case end = 0, byte = 1, short = 2, int = 3, long = 4
        case float = 5, double = 6, byteArray = 7, string = 8
        case list = 9, compound = 10, intArray = 11, longArray = 12
    }

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
            _ = try readString()    // root name (usually empty in Bedrock)
            return try readPayload(type: .compound)
        }

        mutating func readPayload(type: NBTTag) throws -> NBTValue {
            switch type {
            case .end:       return .compound([:])
            case .byte:      return .byte(Int8(bitPattern: try readUInt8()))
            case .short:     return .short(try readInt16())
            case .int:       return .int(try readInt32())
            case .long:      return .long(try readInt64())
            case .float:     return .float(Float(bitPattern: UInt32(bitPattern: try readInt32())))
            case .double:    return .double(Double(bitPattern: UInt64(bitPattern: try readInt64())))
            case .byteArray:
                let count = max(0, Int(try readInt32()))
                return .byteArray(try readData(count: count))
            case .string:    return .string(try readString())
            case .list:
                guard let elemType = NBTTag(rawValue: try readUInt8()) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let count = max(0, Int(try readInt32()))
                var values: [NBTValue] = []; values.reserveCapacity(count)
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

        // MARK: Primitive readers (little-endian)

        mutating func readUInt8() throws -> UInt8 {
            guard offset < data.count else { throw CocoaError(.fileReadCorruptFile) }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readInt16() throws -> Int16 {
            let raw = try readLE(byteCount: 2)
            return Int16(bitPattern: UInt16(raw))
        }

        mutating func readInt32() throws -> Int32 {
            let raw = try readLE(byteCount: 4)
            return Int32(bitPattern: UInt32(raw))
        }

        mutating func readInt64() throws -> Int64 {
            let raw = try readLE(byteCount: 8)
            return Int64(bitPattern: raw)
        }

        /// Reads `byteCount` bytes in little-endian order and returns them as a UInt64.
        mutating func readLE(byteCount: Int) throws -> UInt64 {
            let chunk = try readData(count: byteCount)
            return chunk.withUnsafeBytes { buf in
                buf.bindMemory(to: UInt8.self).enumerated().reduce(UInt64(0)) {
                    $0 | (UInt64($1.element) << ($1.offset * 8))
                }
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
