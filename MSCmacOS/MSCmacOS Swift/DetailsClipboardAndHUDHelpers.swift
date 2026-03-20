//
//  DetailsClipboardAndHUDHelpers.swift
//  MinecraftServerController
//

import SwiftUI
import AppKit

enum DetailsClipboardAndHUDHelpers {

    // MARK: - Pasteboard helper

    static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Copy-to-clipboard HUD feedback

    static func showHUDMessage(_ text: String, copiedHUDText: Binding<String>, showCopiedHUD: Binding<Bool>) {
        copiedHUDText.wrappedValue = text
        withAnimation { showCopiedHUD.wrappedValue = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showCopiedHUD.wrappedValue = false }
        }
    }
}
