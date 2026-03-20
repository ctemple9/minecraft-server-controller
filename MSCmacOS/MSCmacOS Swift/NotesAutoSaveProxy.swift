//
//  NotesAutoSaveProxy.swift
//  MinecraftServerController
//

import Foundation

// MARK: - NotesAutoSaveProxy
// A tiny Obj-C-compatible trampoline that lets us debounce TextEditor saves
// using Foundation's cancelPreviousPerformRequests API.
final class NotesAutoSaveProxy: NSObject {
    static let shared = NotesAutoSaveProxy()
    var action: (() -> Void)?

    @objc func fire() {
        action?()
    }
}
