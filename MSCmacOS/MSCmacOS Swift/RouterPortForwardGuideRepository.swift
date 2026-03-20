import Foundation

/// Read-only repository for validated router guide content.
///
/// Exposes catalog access in one place and keeps raw seed and JSON loading
/// details out of the rest of the app. Selection, matching, and rendering
/// are handled by dedicated downstream types.
final class RouterPortForwardGuideRepository {

    private let catalog: RouterPortForwardGuideCatalog
    private(set) var diagnostics: RouterPortForwardGuideCatalogLoader.LoadDiagnostics

    init(loadResult: RouterPortForwardGuideCatalogLoader.LoadResult) {
        self.catalog = loadResult.catalog
        self.diagnostics = loadResult.diagnostics
    }

    convenience init(source: RouterPortForwardGuideCatalogLoader.Source = .seedV1) {
        self.init(loadResult: RouterPortForwardGuideCatalogLoader.loadWithSeedFallback(preferred: source))
    }

    var allGuides: [RouterPortForwardGuide] {
        catalog.guides
    }

    var allTroubleshootingTopics: [RouterGuideTroubleshootingTopic] {
        catalog.troubleshootingTopics
    }

    func guide(id: String) -> RouterPortForwardGuide? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return catalog.guides.first { $0.id == trimmed }
    }

    func guides(category: RouterGuideCategory) -> [RouterPortForwardGuide] {
        catalog.guides.filter { $0.category == category }
    }

    func guides(family: RouterGuideFamily) -> [RouterPortForwardGuide] {
        catalog.guides.filter { $0.family == family }
    }

    func guides(category: RouterGuideCategory?, family: RouterGuideFamily?) -> [RouterPortForwardGuide] {
        catalog.guides.filter { guide in
            let categoryMatches = category.map { guide.category == $0 } ?? true
            let familyMatches = family.map { guide.family == $0 } ?? true
            return categoryMatches && familyMatches
        }
    }

    func troubleshootingTopic(id: RouterGuideTroubleshootingTopicID) -> RouterGuideTroubleshootingTopic? {
        catalog.troubleshootingTopics.first { $0.id == id }
    }

    func troubleshootingTopic(rawID: String) -> RouterGuideTroubleshootingTopic? {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = RouterGuideTroubleshootingTopicID(rawValue: trimmed) else { return nil }
        return troubleshootingTopic(id: id)
    }

    func troubleshootingTopics(for guide: RouterPortForwardGuide) -> [RouterGuideTroubleshootingTopic] {
        let ids = Set(guide.troubleshooting)
        guard !ids.isEmpty else { return [] }
        return catalog.troubleshootingTopics.filter { ids.contains($0.id) }
    }

    /// Lightweight metadata keyword search. Full router matching and
    /// ranked scoring is handled by RouterPortForwardGuideMatcher.
    func searchByKeyword(_ rawQuery: String) -> [RouterPortForwardGuide] {
        let normalized = Self.normalize(rawQuery)
        guard !normalized.isEmpty else { return [] }

        return catalog.guides.filter { guide in
            let haystacks = guide.searchKeywords.map(Self.normalize)
            return haystacks.contains(where: { keyword in
                keyword == normalized || keyword.contains(normalized) || normalized.contains(keyword)
            })
        }
    }

    func catalogSummary() -> String {
        "\(catalog.guides.count) guides, \(catalog.troubleshootingTopics.count) troubleshooting topics"
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
