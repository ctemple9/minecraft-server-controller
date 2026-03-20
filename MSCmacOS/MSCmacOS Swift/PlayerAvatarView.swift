//
//  PlayerAvatarView.swift
//  MinecraftServerController
//
//  Fetches the player's Minecraft avatar for either Java or Bedrock.
//  Java preserves the existing minotar.net username flow.
//  Bedrock uses MC Heads, which supports Bedrock players when the gamertag
//  is prefixed with a dot.
//
//  Flow:
//    1. No username/gamertag set for the selected edition → prompt the user
//    2. Java selected → fetch full-body skin render by Java username
//    3. Bedrock selected → fetch full-body skin render by Bedrock gamertag
//    4. Error at any step → friendly inline error with retry
//

import SwiftUI
import AppKit

// MARK: - Avatar fetch state

private enum AvatarState {
    case noUsername
    case loading
    case loaded(image: NSImage, displayName: String)
    case error(message: String)
}

private enum AvatarEdition: String, CaseIterable, Identifiable {
    case java
    case bedrock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .java: return "Java"
        case .bedrock: return "Bedrock"
        }
    }

    var placeholder: String {
        switch self {
        case .java: return "Java username"
        case .bedrock: return "Bedrock gamertag"
        }
    }

    var helperText: String {
        switch self {
        case .java:
            return "Enter your Minecraft Java Edition username to show your skin here."
        case .bedrock:
            return "Enter your Minecraft Bedrock gamertag to show your skin here."
        }
    }

    var changeLabel: String {
        switch self {
        case .java: return "Change Username"
        case .bedrock: return "Change Gamertag"
        }
    }

    var setLabel: String {
        switch self {
        case .java: return "Add Username"
        case .bedrock: return "Add Gamertag"
        }
    }
}

// MARK: - PlayerAvatarView

struct PlayerAvatarView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var state: AvatarState = .noUsername
    @State private var usernameInput: String = ""
    @State private var isEditingUsername: Bool = false
    @State private var selectedEdition: AvatarEdition = .java
    @FocusState private var inputFocused: Bool

    private let avatarGuideID = "sidebar.avatar"
    private let avatarHeaderAnchorID = "sidebar.avatar.header"
    private let avatarEditionAnchorID = "sidebar.avatar.edition"
    private let avatarIdentityAnchorID = "sidebar.avatar.identity"

    private var contextualHelpGuideIDs: Set<String> {
        [avatarGuideID]
    }

    private var avatarHelpGuide: ContextualHelpGuide {
        ContextualHelpGuide(
            id: avatarGuideID,
            steps: [
                ContextualHelpStep(
                                    id: "avatar.header",
                                    title: "Your Avatar",
                                    body: "This is a personal identity panel for the app. It is only here to show your skin or render inside MSC, not to manage the server itself.",
                                    anchorID: avatarHeaderAnchorID,
                                    preferredPlacement: .above
                                ),
                                ContextualHelpStep(
                                    id: "avatar.edition",
                                    title: "Java or Bedrock",
                                    body: "Choose the edition first so MSC knows which identity to use. Java expects a Java username, while Bedrock expects a Bedrock gamertag.",
                                    anchorID: avatarEditionAnchorID,
                                    preferredPlacement: .above
                                ),
                                ContextualHelpStep(
                                    id: "avatar.identity",
                                    title: "Saving and lookup behavior",
                                    body: "Use Add or Change to store one name per edition. Java and Bedrock lookups do not resolve the same way, so a failed fetch usually means the spelling or the selected edition does not match.",
                                    anchorID: avatarIdentityAnchorID,
                                    nextLabel: "Done",
                                    preferredPlacement: .above
                                )
            ]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Your Avatar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        ContextualHelpManager.shared.start(avatarHelpGuide)
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Explain Your Avatar")

                    Spacer(minLength: 0)
                }
                .contextualHelpAnchor(avatarHeaderAnchorID)

                HStack(alignment: .center, spacing: 10) {
                    Picker("Edition", selection: $selectedEdition) {
                        ForEach(AvatarEdition.allCases) { edition in
                            Text(edition.title).tag(edition)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 118)
                    .contextualHelpAnchor(avatarEditionAnchorID)

                    Spacer(minLength: 0)

                    if currentIdentity?.isEmpty != false {
                        Button(selectedEdition.setLabel) {
                            state = .noUsername
                            isEditingUsername = true
                            usernameInput = currentIdentity ?? ""
                            inputFocused = true
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        Button("Change") {
                            state = .noUsername
                            isEditingUsername = true
                            usernameInput = currentIdentity ?? ""
                            inputFocused = true
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Group {
                switch state {
                case .noUsername:
                    usernamePrompt

                case .loading:
                    loadingView

                case .loaded(let image, let displayName):
                    avatarView(image: image, displayName: displayName)

                case .error(let message):
                    errorView(message: message)
                }
            }
            .contextualHelpAnchor(avatarIdentityAnchorID)
        }
        .onAppear {
            loadFromConfig()
        }
        .onChange(of: selectedEdition) { _ in
            persistSelectedEdition()
            loadIdentityForSelectedEdition()
        }
        .contextualHelpHost(guideIDs: contextualHelpGuideIDs)
    }

    // MARK: - State views

    private var usernamePrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isEditingUsername {
                Text(selectedEdition.helperText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                TextField(selectedEdition.placeholder, text: $usernameInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($inputFocused)
                    .onSubmit { commitUsername() }

                Button(isEditingUsername ? "Save" : selectedEdition.setLabel) {
                    commitUsername()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            usernameInput = currentIdentity ?? ""
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Fetching skin…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }

    private func avatarView(image: NSImage, displayName: String) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .idleSway()

            Text(displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Retry") {
                    if let identity = currentIdentity, !identity.isEmpty {
                        fetchAvatar(for: identity, edition: selectedEdition)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(selectedEdition.changeLabel) {
                    state = .noUsername
                    isEditingUsername = true
                    usernameInput = currentIdentity ?? ""
                    inputFocused = true
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Logic

    private var currentIdentity: String? {
        switch selectedEdition {
        case .java:
            return viewModel.configManager.config.minecraftUsername
        case .bedrock:
            return viewModel.configManager.config.minecraftBedrockGamertag
        }
    }

    private func loadFromConfig() {
        let storedEdition = viewModel.configManager.config.minecraftAvatarEditionRawValue
        selectedEdition = AvatarEdition(rawValue: storedEdition ?? "") ?? .java
        loadIdentityForSelectedEdition()
    }

    private func loadIdentityForSelectedEdition() {
        guard let identity = currentIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identity.isEmpty else {
            usernameInput = ""
            state = .noUsername
            return
        }

        usernameInput = identity
        isEditingUsername = false
        fetchAvatar(for: identity, edition: selectedEdition)
    }

    private func persistSelectedEdition() {
        viewModel.configManager.config.minecraftAvatarEditionRawValue = selectedEdition.rawValue
        viewModel.configManager.save()
    }

    private func commitUsername() {
        let trimmed = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch selectedEdition {
        case .java:
            viewModel.configManager.config.minecraftUsername = trimmed
        case .bedrock:
            viewModel.configManager.config.minecraftBedrockGamertag = trimmed
        }

        persistSelectedEdition()
        viewModel.configManager.save()

        isEditingUsername = false
        fetchAvatar(for: trimmed, edition: selectedEdition)
    }

    private func fetchAvatar(for identity: String, edition: AvatarEdition) {
        state = .loading

        Task {
            do {
                let image: NSImage
                switch edition {
                case .java:
                    image = try await fetchMinotarImage(username: identity)
                case .bedrock:
                    image = try await fetchBedrockImage(gamertag: identity)
                }

                await MainActor.run {
                    state = .loaded(image: image, displayName: identity)
                }
            } catch AvatarFetchError.usernameNotFound {
                await MainActor.run {
                    switch edition {
                    case .java:
                        state = .error(message: "Username \"\(identity)\" wasn't found. Check the spelling — this must be a Java Edition username.")
                    case .bedrock:
                        state = .error(message: "Gamertag \"\(identity)\" wasn't found. Check the spelling and use the player's Bedrock gamertag.")
                    }
                }
            } catch AvatarFetchError.imageDecode {
                await MainActor.run {
                    state = .error(message: "Skin loaded but couldn't be decoded. Try again.")
                }
            } catch {
                await MainActor.run {
                    state = .error(message: "Network error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Java path: preserve the current minotar.net username-based render flow.
    private func fetchMinotarImage(username: String) async throws -> NSImage {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let url = URL(string: "https://minotar.net/body/\(encoded)/160")!

        var request = URLRequest(url: url)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AvatarFetchError.network
        }

        if http.statusCode == 404 {
            throw AvatarFetchError.usernameNotFound
        }

        guard http.statusCode == 200 else {
            throw AvatarFetchError.network
        }

        guard let image = NSImage(data: data) else {
            throw AvatarFetchError.imageDecode
        }

        return image
    }

    /// Bedrock path:
    /// 1. Resolve the prefixed Bedrock name through Geyser's utility endpoint.
    /// 2. Use the returned Floodgate UUID with MCHeads, which supports Floodgate UUIDs.
    /// 3. Fall back to the direct dotted-gamertag render if resolution is unavailable.
    private func fetchBedrockImage(gamertag: String) async throws -> NSImage {
        let trimmed = gamertag.trimmingCharacters(in: .whitespacesAndNewlines)
        let dottedGamertag = trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"

        if let resolvedImage = try await fetchBedrockImageViaResolvedFloodgateIdentity(dottedGamertag: dottedGamertag) {
            return resolvedImage
        }

        return try await fetchDirectBedrockRender(dottedGamertag: dottedGamertag)
    }

    private func fetchBedrockImageViaResolvedFloodgateIdentity(dottedGamertag: String) async throws -> NSImage? {
        let encodedName = dottedGamertag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dottedGamertag
        var components = URLComponents(string: "https://api.geysermc.org/v2/utils/uuid/bedrock_or_java/\(encodedName)")
        components?.queryItems = [
            URLQueryItem(name: "prefix", value: ".")
        ]

        guard let url = components?.url else {
            throw AvatarFetchError.network
        }

        var request = URLRequest(url: url)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AvatarFetchError.network
        }

        switch http.statusCode {
        case 200:
            let resolved = try JSONDecoder().decode(GeyserResolvedBedrockIdentity.self, from: data)
            let identifier = resolved.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resolved.id
            let renderURL = URL(string: "https://mc-heads.net/body/\(identifier)/160")!

            var renderRequest = URLRequest(url: renderURL)
            renderRequest.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")

            let (renderData, renderResponse) = try await URLSession.shared.data(for: renderRequest)

            guard let renderHTTP = renderResponse as? HTTPURLResponse else {
                throw AvatarFetchError.network
            }

            guard renderHTTP.statusCode == 200 else {
                return nil
            }

            guard let image = NSImage(data: renderData) else {
                throw AvatarFetchError.imageDecode
            }

            return image

        case 204, 400, 503:
            return nil

        default:
            return nil
        }
    }

    private func fetchDirectBedrockRender(dottedGamertag: String) async throws -> NSImage {
        let encoded = dottedGamertag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dottedGamertag
        let url = URL(string: "https://api.mcheads.org/body/\(encoded)/160")!

        var request = URLRequest(url: url)
        request.setValue("MinecraftServerController/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AvatarFetchError.network
        }

        if http.statusCode == 404 {
            throw AvatarFetchError.usernameNotFound
        }

        guard http.statusCode == 200 else {
            throw AvatarFetchError.network
        }

        guard let image = NSImage(data: data) else {
            throw AvatarFetchError.imageDecode
        }

        return image
    }
}

private struct GeyserResolvedBedrockIdentity: Decodable {
    let id: String
    let name: String
}

// MARK: - Error types

private enum AvatarFetchError: Error {
    case usernameNotFound
    case imageDecode
    case network
}

// MARK: - Idle sway modifier
// A gentle rock side-to-side — looks like a Minecraft idle animation
// and avoids the "disappears at 90°" problem of full 3D rotation.

private struct IdleSwayModifier: ViewModifier {
    @State private var angle: Double = -8

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.8)
                    .repeatForever(autoreverses: true)
                ) {
                    angle = 8
                }
            }
    }
}

private extension View {
    func idleSway() -> some View {
        modifier(IdleSwayModifier())
    }
}
