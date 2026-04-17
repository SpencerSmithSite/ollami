import Foundation
import AppKit

extension Notification.Name {
    /// Posted by AuthService.signOut() so views can reset @AppStorage-backed properties directly.
    static let userDidSignOut = Notification.Name("com.omi.desktop.userDidSignOut")
}

@MainActor
class AuthService {
    static let shared = AuthService()

    private var authState: AuthState { AuthState.shared }

    var isSignedIn: Bool {
        get { authState.isSignedIn }
        set { authState.isSignedIn = newValue }
    }
    var isLoading: Bool {
        get { authState.isLoading }
        set { authState.isLoading = newValue }
    }
    var error: String? {
        get { authState.error }
        set { authState.error = newValue }
    }

    private var isConfigured: Bool = false

    private let kAuthGivenName = "auth_givenName"
    private let kAuthFamilyName = "auth_familyName"
    private let kAuthUserId = "auth_userId"
    private let kAuthIsSignedIn = "auth_isSignedIn"

    // MARK: - Token Storage

    private static let tokenDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ollami", isDirectory: true)
    }()

    private static let tokenFile: URL = {
        return tokenDir.appendingPathComponent("token")
    }()

    private var localToken: String {
        if let existing = try? String(contentsOf: Self.tokenFile, encoding: .utf8), !existing.isEmpty {
            return existing
        }
        let token = UUID().uuidString
        try? FileManager.default.createDirectory(at: Self.tokenDir, withIntermediateDirectories: true)
        try? token.write(to: Self.tokenFile, atomically: true, encoding: .utf8)
        NSLog("OLLAMI AUTH: Created new local token at %@", Self.tokenFile.path)
        return token
    }

    // MARK: - User Name Properties

    var givenName: String {
        get { UserDefaults.standard.string(forKey: kAuthGivenName) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kAuthGivenName) }
    }

    var familyName: String {
        get { UserDefaults.standard.string(forKey: kAuthFamilyName) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kAuthFamilyName) }
    }

    var displayName: String {
        let given = givenName
        let family = familyName
        if !given.isEmpty && !family.isEmpty { return "\(given) \(family)" }
        if !given.isEmpty { return given }
        if !family.isEmpty { return family }
        return ""
    }

    init() {}

    // MARK: - Configuration

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        let token = localToken
        let userId = UserDefaults.standard.string(forKey: kAuthUserId) ?? token
        UserDefaults.standard.set(userId, forKey: kAuthUserId)
        UserDefaults.standard.set(true, forKey: kAuthIsSignedIn)

        isSignedIn = true
        AuthState.shared.isRestoringAuth = false

        Task { await RewindDatabase.shared.configure(userId: userId) }
        Task { await SettingsSyncManager.shared.syncFromServer() }

        NSLog("OLLAMI AUTH: Configured with local token, userId=%@", userId)
        fetchConversations()
    }

    // MARK: - Sign In (auto sign-in — no OAuth needed)

    func signInWithApple() async throws {
        configure()
    }

    func signInWithGoogle() async throws {
        configure()
    }

    func cancelSignIn() {
        isLoading = false
    }

    func handleOAuthCallback(url: URL) {
        // No OAuth flow in Ollami — no-op
    }

    // MARK: - Token Access

    func getIdToken(forceRefresh: Bool = false) async throws -> String {
        return localToken
    }

    func getAuthHeader() async throws -> String {
        return "Bearer \(localToken)"
    }

    // MARK: - User Name Management

    @MainActor
    func updateGivenName(_ fullName: String) async {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        givenName = parts.first.map(String.init) ?? trimmed
        familyName = parts.count > 1 ? String(parts[1]) : ""

        do {
            try await APIClient.shared.updateUserProfile(name: trimmed)
        } catch {
            NSLog("OLLAMI AUTH: Failed to update backend profile name (non-fatal): %@", error.localizedDescription)
        }
    }

    func loadNameFromFirebaseIfNeeded() {
        // No Firebase — no-op
    }

    func loadNameFromBackendIfNeeded() {
        guard givenName.isEmpty else { return }
        Task {
            do {
                let profile = try await APIClient.shared.getUserProfile()
                if let name = profile.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                    await MainActor.run {
                        givenName = parts.first.map(String.init) ?? name.trimmingCharacters(in: .whitespaces)
                        familyName = parts.count > 1 ? String(parts[1]) : ""
                    }
                }
            } catch {
                NSLog("OLLAMI AUTH: Failed to fetch backend profile (non-fatal): %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Fetch Conversations

    func fetchConversations() {
        Task {
            do {
                let conversations = try await APIClient.shared.getConversations(limit: 10)
                log("OLLAMI AUTH: Fetched \(conversations.count) conversations")
            } catch {
                logError("OLLAMI AUTH: Failed to fetch conversations", error: error)
            }
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        AnalyticsManager.shared.signedOut()
        AnalyticsManager.shared.reset()

        isSignedIn = false
        UserDefaults.standard.set(false, forKey: kAuthIsSignedIn)

        Task { await AgentSyncService.shared.stop() }

        let closeGeneration = RewindDatabase.configureGeneration
        Task {
            await RewindDatabase.shared.closeIfStale(generation: closeGeneration)
            await RewindIndexer.shared.reset()
            await RewindStorage.shared.reset()
            await TranscriptionStorage.shared.invalidateCache()
            await MemoryStorage.shared.invalidateCache()
            await ActionItemStorage.shared.invalidateCache()
            await ProactiveStorage.shared.invalidateCache()
            await NoteStorage.shared.invalidateCache()
            await AIUserProfileService.shared.invalidateCache()
        }

        NotificationCenter.default.post(name: .userDidSignOut, object: nil)

        UserDefaults.standard.removeObject(forKey: "onboardingStep")
        UserDefaults.standard.removeObject(forKey: "hasTriggeredNotification")
        UserDefaults.standard.removeObject(forKey: "hasTriggeredAutomation")
        UserDefaults.standard.removeObject(forKey: "hasTriggeredScreenRecording")
        UserDefaults.standard.removeObject(forKey: "hasTriggeredMicrophone")
        UserDefaults.standard.removeObject(forKey: "hasTriggeredSystemAudio")
        UserDefaults.standard.removeObject(forKey: "onboardingChatMessages")
        UserDefaults.standard.removeObject(forKey: "onboardingACPSessionId")
        UserDefaults.standard.removeObject(forKey: "onboardingJustCompleted")
        UserDefaults.standard.removeObject(forKey: "transcriptionEnabled")

        NSLog("OLLAMI AUTH: Signed out")
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notSignedIn
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "User is not signed in"
        case .cancelled: return "Sign in cancelled"
        }
    }
}
