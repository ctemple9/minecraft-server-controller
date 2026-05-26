//
//  PlayerInventoryView.swift
//  MinecraftServerController
//
//  Minecraft-style inventory grid: armor + offhand, 3-row main, and hotbar.
//  Item icons are loaded asynchronously from mc-heads.net and cached in memory.
//

import SwiftUI
import AppKit

// MARK: - Item icon cache (process-lifetime, keyed by item name)

private actor ItemIconCache {
    static let shared = ItemIconCache()
    private var cache: [String: NSImage] = [:]

    func image(for key: String) -> NSImage? { cache[key] }
    func store(_ image: NSImage, for key: String) { cache[key] = image }
}

// MARK: - Single inventory slot

struct InventorySlotView: View {
    let item: InventoryItem?
    let size: CGFloat
    var highlighted: Bool = false   // true for hotbar slots

    @State private var image: NSImage? = nil

    var body: some View {
        ZStack {
            // Slot background
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(highlighted ? Color.white.opacity(0.18) : Color.white.opacity(0.06), lineWidth: 1)
                )

            if let item {
                // Item icon
                Group {
                    if let img = image {
                        Image(nsImage: img)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(3)
                    } else {
                        // Tiny placeholder while loading
                        Image(systemName: "cube")
                            .font(.system(size: size * 0.32))
                            .foregroundStyle(MSC.Colors.tertiary.opacity(0.5))
                    }
                }

                // Stack count badge (bottom-right)
                if item.count > 1 {
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 0) {
                            Spacer()
                            Text("\(item.count)")
                                .font(.system(size: max(7, size * 0.27), weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.8), radius: 1, x: 0.5, y: 0.5)
                                .padding(.trailing, 1.5)
                                .padding(.bottom, 1)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .help(tooltipText)
        .task(id: item?.itemID) { await loadIcon() }
    }

    private var tooltipText: String {
        guard let item else { return "Empty" }
        var lines = [item.displayName]
        if item.count > 1 { lines.append("×\(item.count)") }
        for ench in item.enchantments { lines.append(ench.displayName) }
        if item.damage > 0 { lines.append("Durability damage: \(item.damage)") }
        return lines.joined(separator: "\n")
    }

    private func loadIcon() async {
        guard let name = item?.iconName else { image = nil; return }

        // Check in-memory cache first
        if let cached = await ItemIconCache.shared.image(for: name) {
            image = cached
            return
        }

        image = nil

        // Minecraft textures from the InventivetalentDev asset repo.
        // Try /item/ first (tools, food, etc.) then /block/ as fallback (placeable blocks).
        let base = "https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.21.1/assets/minecraft/textures"
        let candidates = ["\(base)/item/\(name).png", "\(base)/block/\(name).png"]

        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }
            var req = URLRequest(url: url)
            req.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 8
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else { continue }
            await ItemIconCache.shared.store(img, for: name)
            image = img
            return
        }
    }
}

// MARK: - Full inventory grid

struct PlayerInventoryView: View {
    let inventory: [InventoryItem]

    private let slotSize: CGFloat = 36
    private let gap: CGFloat = 3

    /// O(1) slot lookup
    private var bySlot: [Int: InventoryItem] {
        Dictionary(uniqueKeysWithValues: inventory.map { ($0.slot, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.md) {

            // ── Armor + Offhand ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Equipment")
                    .font(MSC.Typography.captionBold)
                    .foregroundStyle(.secondary)

                HStack(spacing: gap) {
                    // Helmet → chestplate → leggings → boots (top to bottom = 103..100)
                    ForEach([103, 102, 101, 100], id: \.self) { slot in
                        InventorySlotView(item: bySlot[slot], size: slotSize)
                    }

                    Spacer().frame(width: slotSize * 0.6)

                    // Offhand (slot -106)
                    VStack(spacing: 2) {
                        InventorySlotView(item: bySlot[-106], size: slotSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                            )
                        Text("Off")
                            .font(.system(size: 8))
                            .foregroundStyle(MSC.Colors.tertiary)
                    }
                }
            }

            Divider()

            // ── Main Inventory (3 rows × 9, slots 9–35) ───────────────────
            VStack(alignment: .leading, spacing: MSC.Spacing.xs) {
                Text("Inventory")
                    .font(MSC.Typography.captionBold)
                    .foregroundStyle(.secondary)

                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<9, id: \.self) { col in
                                InventorySlotView(item: bySlot[9 + row * 9 + col], size: slotSize)
                            }
                        }
                    }
                }
            }

            // ── Hotbar (slots 0–8) ─────────────────────────────────────────
            VStack(spacing: gap) {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                HStack(spacing: gap) {
                    ForEach(0..<9, id: \.self) { slot in
                        InventorySlotView(item: bySlot[slot], size: slotSize, highlighted: true)
                    }
                }
            }
        }
    }
}
