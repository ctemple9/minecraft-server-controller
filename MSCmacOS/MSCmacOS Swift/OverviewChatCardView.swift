//
//  OverviewChatCardView.swift
//  MinecraftServerController
//
//  Overview tab — "Chat" card. Reads the live server output (ConsoleManager)
//  and surfaces the in-game chat feed a player would see by pressing "T":
//  chat messages, advancements/achievements, and join/leave events. Auto-scrolls
//  to the newest line.
//
//  Note: Java logs chat to the console. Bedrock (BDS) does not log chat, so for
//  Bedrock only connect/disconnect events appear.
//

import SwiftUI

// MARK: - Parsed chat message

struct ChatFeedMessage: Identifiable, Sendable {
    enum Kind: Sendable { case chat, advancement, join, leave }
    let id = UUID()
    let kind: Kind
    let player: String?
    let text: String
    let time: Date
}

// MARK: - Card

struct OverviewChatCardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject var console: ConsoleManager

    private var messages: [ChatFeedMessage] {
        // Prebuilt incrementally by ConsoleManager (parsed off-main as lines arrive), so
        // this card no longer re-scans the whole entries buffer on every render.
        console.chatFeed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MSC.Spacing.sm) {

            // Header
            HStack(spacing: MSC.Spacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MSC.Colors.tertiary)
                MSCOverline("Chat")
                Spacer()
            }

            let msgs = messages
            if msgs.isEmpty {
                emptyState
            } else {
                feed(msgs)
            }
        }
        .padding(MSC.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .fill(MSC.Colors.tierContent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MSC.Radius.md, style: .continuous)
                .stroke(MSC.Colors.contentBorder, lineWidth: 1)
        )
    }

    // MARK: Feed

    private func feed(_ msgs: [ChatFeedMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(msgs) { msg in
                        row(msg).id(msg.id)
                    }
                    // Invisible bottom anchor for auto-scroll.
                    Color.clear.frame(height: 1).id("chat.bottom")
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: msgs.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("chat.bottom", anchor: .bottom)
                }
            }
            .onAppear { proxy.scrollTo("chat.bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func row(_ msg: ChatFeedMessage) -> some View {
        switch msg.kind {
        case .chat:
            (
                Text(msg.player ?? "")
                    .foregroundColor(MSC.Colors.accent)
                    .fontWeight(.semibold)
                + Text("  \(msg.text)")
                    .foregroundColor(MSC.Colors.body)
            )
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)

        case .advancement:
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "rosette")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.yellow.opacity(0.85))
                    .padding(.top, 1)
                (
                    Text(msg.player ?? "").fontWeight(.semibold).foregroundColor(MSC.Colors.body)
                    + Text(" earned ").foregroundColor(MSC.Colors.tertiary)
                    + Text(msg.text).foregroundColor(Color.yellow.opacity(0.9))
                )
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            }

        case .join, .leave:
            HStack(spacing: 5) {
                Circle()
                    .fill(msg.kind == .join ? MSC.Colors.success : MSC.Colors.neutral)
                    .frame(width: 5, height: 5)
                (
                    Text(msg.player ?? "").fontWeight(.medium).foregroundColor(MSC.Colors.body)
                    + Text(" \(msg.text)").foregroundColor(MSC.Colors.tertiary)
                )
                .font(.system(size: 10))
                .lineLimit(1)
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: MSC.Spacing.xs) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 18))
                .foregroundStyle(MSC.Colors.tertiary)
            Text("No chat yet")
                .font(MSC.Typography.captionBold)
                .foregroundStyle(MSC.Colors.caption)
            Text(viewModel.isServerRunning
                 ? "Player chat and advancements will appear here."
                 : "Start the server to see live chat.")
                .font(.system(size: 10))
                .foregroundStyle(MSC.Colors.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, MSC.Spacing.sm)
    }
}

// MARK: - Parser

enum ChatFeedParser {

    /// Parse a single console entry into a chat-feed message, if it is one. Only server
    /// output carries chat / advancement / join-leave lines. Pure and non-isolated, so it
    /// can run on the console parse queue off the main thread.
    static func parseEntry(_ entry: ConsoleEntry) -> ChatFeedMessage? {
        guard entry.source == .server else { return nil }
        return parseLine(entry.raw, time: entry.createdAt)
    }

    private static func parseLine(_ raw: String, time: Date) -> ChatFeedMessage? {
        var payload = strippedPayload(raw)

        // Paper tags unsigned chat with a "[Not Secure]" prefix — drop it.
        if payload.hasPrefix("[Not Secure] ") {
            payload = String(payload.dropFirst("[Not Secure] ".count))
        }
        payload = payload.trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }

        // Chat: "<player> message"
        if payload.hasPrefix("<"), let gt = payload.firstIndex(of: ">") {
            let name = String(payload[payload.index(after: payload.startIndex)..<gt])
                .trimmingCharacters(in: .whitespaces)
            let text = String(payload[payload.index(after: gt)...])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !text.isEmpty else { return nil }
            return ChatFeedMessage(kind: .chat, player: name, text: text, time: time)
        }

        // Advancements / achievements
        for marker in [" has made the advancement ",
                       " has completed the challenge ",
                       " has reached the goal "] {
            if let r = payload.range(of: marker) {
                let name = String(payload[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                var ach = String(payload[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if ach.hasPrefix("["), ach.hasSuffix("]") { ach = String(ach.dropFirst().dropLast()) }
                guard !name.isEmpty, name.count < 40 else { return nil }
                return ChatFeedMessage(kind: .advancement, player: name, text: ach, time: time)
            }
        }

        // Java join / leave
        if payload.hasSuffix(" joined the game") {
            let name = String(payload.dropLast(" joined the game".count))
            return ChatFeedMessage(kind: .join, player: name, text: "joined the game", time: time)
        }
        if payload.hasSuffix(" left the game") {
            let name = String(payload.dropLast(" left the game".count))
            return ChatFeedMessage(kind: .leave, player: name, text: "left the game", time: time)
        }

        // Bedrock connect / disconnect
        if let r = payload.range(of: "Player connected: ") {
            return ChatFeedMessage(kind: .join, player: firstField(after: r.upperBound, in: payload),
                                   text: "connected", time: time)
        }
        if let r = payload.range(of: "Player disconnected: ") {
            return ChatFeedMessage(kind: .leave, player: firstField(after: r.upperBound, in: payload),
                                   text: "disconnected", time: time)
        }

        return nil
    }

    /// Returns the message body after the final "]: " log prefix.
    private static func strippedPayload(_ raw: String) -> String {
        if let r = raw.range(of: "]: ", options: .backwards) {
            return String(raw[r.upperBound...])
        }
        return raw
    }

    /// Bedrock connect lines look like "name, xuid: 123" — take the name up to the comma.
    private static func firstField(after idx: String.Index, in payload: String) -> String {
        var who = String(payload[idx...])
        if let comma = who.firstIndex(of: ",") { who = String(who[..<comma]) }
        return who.trimmingCharacters(in: .whitespaces)
    }
}
