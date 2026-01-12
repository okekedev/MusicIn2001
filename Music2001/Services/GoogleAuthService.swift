import Foundation
import AuthenticationServices
import CryptoKit

enum GoogleAuthError: Error, LocalizedError {
    case configNotFound
    case authFailed(String)
    case tokenExchangeFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "OAuth configuration not found"
        case .authFailed(let message):
            return "Authentication failed: \(message)"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        case .notAuthenticated:
            return "Not authenticated. Please sign in first."
        }
    }
}

struct OAuthConfig: Codable {
    struct Installed: Codable {
        let clientId: String
        let authUri: String
        let tokenUri: String
        let redirectUris: [String]

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case authUri = "auth_uri"
            case tokenUri = "token_uri"
            case redirectUris = "redirect_uris"
        }
    }
    let installed: Installed
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

@MainActor
class GoogleAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var accessToken: String?
    @Published var userEmail: String?

    private var clientId: String = ""
    private let redirectURI = "com.okekedev.mixor:/oauth2redirect"
    private let scopes = [
        "https://www.googleapis.com/auth/youtube.upload",
        "https://www.googleapis.com/auth/userinfo.email"
    ]

    private var codeVerifier: String?
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        loadConfig()
        loadStoredTokens()
    }

    private func loadConfig() {
        // Try to load from bundled config
        if let configURL = Bundle.main.url(forResource: "client_config", withExtension: "json", subdirectory: "OAuth"),
           let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(OAuthConfig.self, from: data) {
            clientId = config.installed.clientId
        } else {
            // Development: use placeholder - user needs to add their own config
            print("OAuth config not found. Please add OAuth/client_config.json")
        }
    }

    private func loadStoredTokens() {
        if let token = KeychainService.load(key: "access_token") {
            accessToken = token
            userEmail = KeychainService.load(key: "user_email")
            isAuthenticated = true
        }
    }

    func startOAuthFlow() async throws {
        guard !clientId.isEmpty else {
            throw GoogleAuthError.configNotFound
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        // Generate PKCE code verifier and challenge
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier!)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw GoogleAuthError.authFailed("Invalid auth URL")
        }

        // Use ASWebAuthenticationSession
        return try await withCheckedThrowingContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.okekedev.mixor"
            ) { [weak self] callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleAuthError.authFailed("User cancelled"))
                    } else {
                        continuation.resume(throwing: GoogleAuthError.authFailed(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: GoogleAuthError.authFailed("No callback URL"))
                    return
                }

                Task { @MainActor [weak self] in
                    do {
                        try await self?.handleCallback(url: callbackURL)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            authSession?.start()
        }
    }

    private func handleCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let codeVerifier = codeVerifier else {
            throw GoogleAuthError.authFailed("Invalid callback")
        }

        try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id=\(clientId)",
            "code=\(code)",
            "code_verifier=\(codeVerifier)",
            "grant_type=authorization_code",
            "redirect_uri=\(redirectURI)"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleAuthError.tokenExchangeFailed
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)

        accessToken = tokens.accessToken
        isAuthenticated = true
        storeTokens(tokens)

        // Fetch user email
        try await fetchUserEmail()
    }

    private func fetchUserEmail() async throws {
        guard let token = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        struct UserInfo: Codable {
            let email: String
        }

        if let userInfo = try? JSONDecoder().decode(UserInfo.self, from: data) {
            userEmail = userInfo.email
            KeychainService.save(key: "user_email", value: userInfo.email)
        }
    }

    func refreshTokenIfNeeded() async throws {
        guard let refreshToken = KeychainService.load(key: "refresh_token") else {
            throw GoogleAuthError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id=\(clientId)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Refresh failed, need to re-authenticate
            logout()
            throw GoogleAuthError.notAuthenticated
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokens.accessToken
        KeychainService.save(key: "access_token", value: tokens.accessToken)
    }

    func logout() {
        KeychainService.delete(key: "access_token")
        KeychainService.delete(key: "refresh_token")
        KeychainService.delete(key: "user_email")
        accessToken = nil
        userEmail = nil
        isAuthenticated = false
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func storeTokens(_ tokens: TokenResponse) {
        KeychainService.save(key: "access_token", value: tokens.accessToken)
        if let refreshToken = tokens.refreshToken {
            KeychainService.save(key: "refresh_token", value: refreshToken)
        }
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
