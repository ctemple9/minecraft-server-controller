//
//  YAMLHelper.swift
//  MinecraftServerController
//
//  Created by Cameron Temple on 12/2/25.
//

//
//  YAMLHelper.swift
//

import Foundation

struct YAMLHelper {

    static func parseYAML(_ text: String) -> [String: Any] {
        var result: [String: Any] = [:]
        var currentSection: String?

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // section:
            if trimmed.hasSuffix(":") {
                let section = String(trimmed.dropLast())
                currentSection = section
                result[section] = [:]
                continue
            }

            guard let idx = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<idx].trimmingCharacters(in: .whitespaces)
            let valuePart = trimmed[trimmed.index(after: idx)...].trimmingCharacters(in: .whitespaces)

            let value: Any
            if let intVal = Int(valuePart) {
                value = intVal
            } else {
                value = valuePart.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }

            if let section = currentSection {
                var dict = result[section] as? [String: Any] ?? [:]
                dict[key] = value
                result[section] = dict
            } else {
                result[key] = value
            }
        }

        return result
    }
}
