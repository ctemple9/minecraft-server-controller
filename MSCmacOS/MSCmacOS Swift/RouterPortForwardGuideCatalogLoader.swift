import Foundation

/// Loads and decodes router port-forwarding guide catalogs from bundled JSON seed files into in-memory guide records.
///
/// This file intentionally stays independent from SwiftUI, AppConfig, and AppViewModel.
/// It exists to keep guide loading and validation separate from later rendering and matching phases.
enum RouterPortForwardGuideCatalogLoader {

    struct LoadDiagnostics: Equatable {
        var sourceDescription: String
        var validationMessages: [String] = []
        var nonFatalWarnings: [String] = []

        var isClean: Bool {
            validationMessages.isEmpty && nonFatalWarnings.isEmpty
        }
    }

    struct LoadResult {
        var catalog: RouterPortForwardGuideCatalog
        var diagnostics: LoadDiagnostics
    }

    enum LoaderError: LocalizedError {
        case bundledJSONMissing(String)
        case bundledJSONUnreadable(String)
        case bundledJSONDecodeFailed(String)
        case validationFailed([String])

        var errorDescription: String? {
            switch self {
            case .bundledJSONMissing(let name):
                return "Router guide catalog JSON not found in bundle: \(name)"
            case .bundledJSONUnreadable(let detail):
                return "Router guide catalog JSON could not be read: \(detail)"
            case .bundledJSONDecodeFailed(let detail):
                return "Router guide catalog JSON could not be decoded: \(detail)"
            case .validationFailed(let messages):
                return (["Router guide catalog validation failed:"] + messages).joined(separator: "\n- ")
            }
        }
    }

    enum Source {
        case seedV1
        case bundledJSON(resourceName: String, bundle: Bundle = .main)
    }

    static func load(from source: Source) throws -> LoadResult {
        switch source {
        case .seedV1:
            let catalog = RouterPortForwardGuideCatalog.v1Seed
            let messages = validationMessages(for: catalog)
            guard messages.isEmpty else {
                throw LoaderError.validationFailed(messages)
            }
            return LoadResult(
                catalog: catalog,
                diagnostics: LoadDiagnostics(sourceDescription: "seedV1")
            )

        case .bundledJSON(let resourceName, let bundle):
            guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
                throw LoaderError.bundledJSONMissing(resourceName)
            }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw LoaderError.bundledJSONUnreadable(error.localizedDescription)
            }

            let catalog: RouterPortForwardGuideCatalog
            do {
                catalog = try JSONDecoder().decode(RouterPortForwardGuideCatalog.self, from: data)
            } catch {
                throw LoaderError.bundledJSONDecodeFailed(error.localizedDescription)
            }

            let messages = validationMessages(for: catalog)
            guard messages.isEmpty else {
                throw LoaderError.validationFailed(messages)
            }

            return LoadResult(
                catalog: catalog,
                diagnostics: LoadDiagnostics(sourceDescription: "bundle:\(resourceName).json")
            )
        }
    }

    static func loadWithSeedFallback(preferred source: Source) -> LoadResult {
        do {
            return try load(from: source)
        } catch {
            do {
                var fallback = try load(from: .seedV1)
                fallback.diagnostics.nonFatalWarnings.append(error.localizedDescription)
                return fallback
            } catch {
                fatalError("Router guide loader could not recover. Seed fallback also failed: \(error.localizedDescription)")
            }
        }
    }

    private static func validationMessages(for catalog: RouterPortForwardGuideCatalog) -> [String] {
        RouterPortForwardGuideValidator.validate(catalog).map { issue in
            switch issue {
            case .catalogHasNoGuides:
                return "Catalog has no guides."
            case .duplicateGuideID(let id):
                return "Duplicate guide id: \(id)"
            case .duplicateTroubleshootingID(let id):
                return "Duplicate troubleshooting topic id: \(id)"
            case .emptyDisplayName(let guideID):
                return "Guide has empty display name: \(guideID)"
            case .emptySearchKeywords(let guideID):
                return "Guide has empty search keywords: \(guideID)"
            case .duplicateSearchKeyword(let guideID, let keyword):
                return "Guide \(guideID) has duplicate search keyword: \(keyword)"
            case .invalidAdminAddress(let guideID, let value):
                return "Guide \(guideID) has invalid admin address: \(value)"
            case .guideHasNoSteps(let guideID):
                return "Guide has no steps: \(guideID)"
            case .guideHasNoTroubleshootingReferences(let guideID):
                return "Guide has no troubleshooting references: \(guideID)"
            case .invalidStep(let guideID, let stepID):
                return "Guide \(guideID) has invalid step: \(stepID)"
            case .duplicateStepID(let guideID, let stepID):
                return "Guide \(guideID) has duplicate step id: \(stepID)"
            case .invalidReviewDate(let guideID, let value):
                return "Guide \(guideID) has invalid review date: \(value)"
            }
        }
    }
}
