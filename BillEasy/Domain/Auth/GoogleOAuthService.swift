import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit
import WebKit

struct GoogleOAuthIdentity: Equatable {
    let googleID: String
    let email: String
    let name: String
    let avatarURL: String?
    let idToken: String

    init(googleID: String, email: String, name: String, avatarURL: String? = nil, idToken: String = "") {
        self.googleID = googleID
        self.email = email
        self.name = name
        self.avatarURL = avatarURL
        self.idToken = idToken
    }
}

struct GoogleOAuthConfiguration {
    let clientID: String?
    let serverClientID: String?
    let redirectScheme: String?
    let redirectPath: String

    init(
        clientID: String? = nil,
        serverClientID: String? = nil,
        redirectScheme: String? = nil,
        redirectPath: String? = nil,
        bundle: Bundle = .main
    ) {
        self.clientID = Self.trimmed(
            clientID ?? bundle.object(forInfoDictionaryKey: "GOOGLE_OAUTH_CLIENT_ID") as? String
        )
        self.serverClientID = Self.trimmed(
            serverClientID ?? bundle.object(forInfoDictionaryKey: "GOOGLE_WEB_CLIENT_ID") as? String
        )
        self.redirectScheme = Self.trimmed(
            redirectScheme ?? bundle.object(forInfoDictionaryKey: "GOOGLE_OAUTH_REDIRECT_SCHEME") as? String
        )
        self.redirectPath = Self.trimmed(
            redirectPath ?? bundle.object(forInfoDictionaryKey: "GOOGLE_OAUTH_REDIRECT_PATH") as? String
        ) ?? "/oauth2redirect/google"
    }

    var redirectURI: String? {
        guard let redirectScheme else { return nil }
        let normalizedPath = redirectPath.hasPrefix("/") ? redirectPath : "/\(redirectPath)"
        return "\(redirectScheme):\(normalizedPath)"
    }

    private static func trimmed(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct GoogleWebOAuthConfiguration {
    let clientID: String?
    let frontendBaseURL: URL?
    let callbackPath: String

    init(
        clientID: String? = nil,
        frontendBaseURL: URL? = nil,
        callbackPath: String = "/auth/google/callback",
        bundle: Bundle = .main
    ) {
        self.clientID = Self.trimmed(
            clientID ?? bundle.object(forInfoDictionaryKey: "GOOGLE_WEB_CLIENT_ID") as? String
        )

        if let frontendBaseURL {
            self.frontendBaseURL = frontendBaseURL
        } else {
            self.frontendBaseURL = Self.resolveOptionalURL(
                bundle.object(forInfoDictionaryKey: "FRONTEND_BASE_URL") as? String
            )
        }

        self.callbackPath = callbackPath.hasPrefix("/") ? callbackPath : "/\(callbackPath)"
    }

    var isConfigured: Bool {
        clientID?.isEmpty == false && frontendBaseURL != nil
    }

    var redirectURI: URL? {
        guard let frontendBaseURL else { return nil }
        return frontendBaseURL.appendingPathComponent(callbackPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static func trimmed(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func resolveOptionalURL(_ rawValue: String?) -> URL? {
        guard let trimmed = trimmed(rawValue) else { return nil }
        return URL(string: trimmed)
    }
}

enum GoogleOAuthServiceError: LocalizedError {
    case notConfigured
    case cancelled
    case browserStartFailed
    case invalidCallback
    case invalidState
    case missingAuthorizationCode
    case invalidIdentityToken
    case invalidNonce
    case missingEmail
    case missingGoogleIdentifier
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "O login com Google não está disponível no momento. Use outro método de acesso ou tente novamente mais tarde."
        case .cancelled:
            return "O login com Google foi cancelado."
        case .browserStartFailed:
            return "Não foi possível iniciar o fluxo seguro do Google neste dispositivo."
        case .invalidCallback:
            return "O app recebeu um retorno inválido do Google."
        case .invalidState:
            return "A validação de segurança do login com Google falhou. Tente novamente."
        case .missingAuthorizationCode:
            return "O Google não retornou o código de autorização esperado."
        case .invalidIdentityToken:
            return "O Google retornou um token inválido para este login."
        case .invalidNonce:
            return "A validação de segurança do token do Google falhou."
        case .missingEmail:
            return "A conta Google não retornou um e-mail válido para continuar."
        case .missingGoogleIdentifier:
            return "A conta Google não retornou um identificador válido para continuar."
        case let .authorizationFailed(message):
            return message
        case let .tokenExchangeFailed(message):
            return message
        case let .network(message):
            return message
        }
    }
}

struct GoogleOAuthAuthorizationRequest {
    let authorizationURL: URL
    let callbackScheme: String
}

protocol GoogleOAuthAuthorizationRunning {
    @MainActor
    func authorize(using request: GoogleOAuthAuthorizationRequest, presentationAnchor: ASPresentationAnchor?) async throws -> URL
}

private final class SystemGoogleOAuthAuthorizationRunner: NSObject, GoogleOAuthAuthorizationRunning, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?
    private weak var activeAnchor: ASPresentationAnchor?

    @MainActor
    func authorize(using request: GoogleOAuthAuthorizationRequest, presentationAnchor: ASPresentationAnchor?) async throws -> URL {
        activeAnchor = presentationAnchor

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: request.authorizationURL,
                callbackURLScheme: request.callbackScheme
            ) { [weak self] callbackURL, error in
                defer {
                    self?.activeSession = nil
                    self?.activeAnchor = nil
                }

                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: GoogleOAuthServiceError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: GoogleOAuthServiceError.authorizationFailed(error.localizedDescription))
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: GoogleOAuthServiceError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            activeSession = session

            guard session.start() else {
                activeSession = nil
                activeAnchor = nil
                continuation.resume(throwing: GoogleOAuthServiceError.browserStartFailed)
                return
            }
        }
    }

    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let activeAnchor {
            return activeAnchor
        }

        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow
        }

        return UIWindow()
    }
}

final class GoogleOAuthService {
    private struct TokenResponse: Decodable {
        let accessToken: String?
        let idToken: String?
        let tokenType: String?
        let error: String?
        let errorDescription: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case idToken = "id_token"
            case tokenType = "token_type"
            case error
            case errorDescription = "error_description"
        }
    }

    private struct IDTokenPayload: Decodable {
        let sub: String?
        let email: String?
        let name: String?
        let nonce: String?
        let picture: String?
        let aud: String?
        let azp: String?
    }

    private struct UserInfoResponse: Decodable {
        let picture: String?
    }

    private let configuration: GoogleOAuthConfiguration
    private let webConfiguration: GoogleWebOAuthConfiguration
    private let session: URLSession
    private let authorizationRunner: GoogleOAuthAuthorizationRunning

    init(
        configuration: GoogleOAuthConfiguration = GoogleOAuthConfiguration(),
        webConfiguration: GoogleWebOAuthConfiguration = GoogleWebOAuthConfiguration(),
        session: URLSession = .shared,
        authorizationRunner: GoogleOAuthAuthorizationRunning = SystemGoogleOAuthAuthorizationRunner()
    ) {
        self.configuration = configuration
        self.webConfiguration = webConfiguration
        self.session = session
        self.authorizationRunner = authorizationRunner
    }

    @MainActor
    func authenticate(presenter: UIViewController) async throws -> GoogleOAuthIdentity {
        if let mockIdentity = Self.mockIdentityFromEnvironment() {
            return mockIdentity
        }

        guard
            configuration.clientID?.isEmpty == false,
            configuration.redirectScheme?.isEmpty == false,
            configuration.redirectURI?.isEmpty == false
        else {
            throw GoogleOAuthServiceError.notConfigured
        }

        return try await authenticate(presentationAnchor: presenter.view.window)
    }

    @MainActor
    func authenticate(presentationAnchor: ASPresentationAnchor?) async throws -> GoogleOAuthIdentity {
        if let mockIdentity = Self.mockIdentityFromEnvironment() {
            Self.debugLog("Using mock identity from environment.")
            return mockIdentity
        }

        guard
            let clientID = configuration.clientID,
            let serverClientID = configuration.serverClientID,
            let redirectScheme = configuration.redirectScheme,
            let redirectURI = configuration.redirectURI
        else {
            Self.debugLog("OAuth configuration is incomplete.")
            throw GoogleOAuthServiceError.notConfigured
        }

        Self.debugLog("Starting native OAuth. clientID=\(Self.redactedClientID(clientID)) serverClientID=\(Self.redactedClientID(serverClientID)) redirectURI=\(redirectURI)")
        let state = Self.randomURLSafeString(byteCount: 32)
        let nonce = Self.randomURLSafeString(byteCount: 32)
        let codeVerifier = Self.randomURLSafeString(byteCount: 64)
        let authorizationURL = try makeAuthorizationURL(
            clientID: clientID,
            serverClientID: serverClientID,
            redirectURI: redirectURI,
            state: state,
            nonce: nonce,
            codeChallenge: Self.codeChallenge(from: codeVerifier)
        )

        let callbackURL = try await authorizationRunner.authorize(
            using: GoogleOAuthAuthorizationRequest(
                authorizationURL: authorizationURL,
                callbackScheme: redirectScheme
            ),
            presentationAnchor: presentationAnchor
        )

        Self.debugLog("Received callback. scheme=\(callbackURL.scheme ?? "-") host=\(callbackURL.host ?? "-") path=\(callbackURL.path)")
        let authorizationCode = try parseAuthorizationCode(from: callbackURL, expectedState: state)
        Self.debugLog("Authorization code received. Exchanging token.")
        let tokenResponse = try await exchangeCodeForTokens(
            authorizationCode: authorizationCode,
            clientID: clientID,
            serverClientID: serverClientID,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier
        )

        let identity = try await decodeIdentity(from: tokenResponse, expectedNonce: nonce)
        Self.debugLog("Identity decoded for \(Self.redactedEmail(identity.email)).")
        return identity
    }

    private func makeAuthorizationURL(
        clientID: String,
        serverClientID: String,
        redirectURI: String,
        state: String,
        nonce: String,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "audience", value: serverClientID),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            throw GoogleOAuthServiceError.invalidCallback
        }

        return url
    }

    private func parseAuthorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        let parameters = Self.parameters(from: callbackURL)

        if let error = parameters["error"], error.isEmpty == false {
            let description = parameters["error_description"]?.nilIfEmpty ?? error
            throw GoogleOAuthServiceError.authorizationFailed(description)
        }

        guard parameters["state"] == expectedState else {
            throw GoogleOAuthServiceError.invalidState
        }

        guard let code = parameters["code"], code.isEmpty == false else {
            throw GoogleOAuthServiceError.missingAuthorizationCode
        }

        return code
    }

    private func exchangeCodeForTokens(
        authorizationCode: String,
        clientID: String,
        serverClientID: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> TokenResponse {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleOAuthServiceError.invalidCallback
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncodedBody([
            "audience": serverClientID,
            "client_id": clientID,
            "code": authorizationCode,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                Self.debugLog("Token exchange returned a non-HTTP response.")
                throw GoogleOAuthServiceError.invalidCallback
            }

            Self.debugLog("Token exchange HTTP \(httpResponse.statusCode).")
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                let message = Self.extractMessage(from: data) ?? "Falha ao trocar o código do Google por token."
                Self.debugLog("Token exchange failed: \(message)")
                throw GoogleOAuthServiceError.tokenExchangeFailed(message)
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            if let error = tokenResponse.error?.nilIfEmpty {
                Self.debugLog("Token response contained error: \(error)")
                throw GoogleOAuthServiceError.tokenExchangeFailed(
                    tokenResponse.errorDescription?.nilIfEmpty ?? error
                )
            }
            return tokenResponse
        } catch let error as GoogleOAuthServiceError {
            throw error
        } catch let error as URLError {
            Self.debugLog("Token exchange transport error: \(error.localizedDescription)")
            throw GoogleOAuthServiceError.network(Self.mapTransportError(error))
        } catch {
            Self.debugLog("Token exchange unexpected error: \(error.localizedDescription)")
            throw GoogleOAuthServiceError.tokenExchangeFailed(error.localizedDescription)
        }
    }

    private func decodeIdentity(from tokenResponse: TokenResponse, expectedNonce: String) async throws -> GoogleOAuthIdentity {
        guard let idToken = tokenResponse.idToken?.nilIfEmpty else {
            throw GoogleOAuthServiceError.invalidIdentityToken
        }

        let payload = try decodeIdentityPayload(fromIDToken: idToken, expectedNonce: expectedNonce)
        Self.debugLog("Decoded idToken audience=\(Self.redactedClientID(payload.audience ?? "-")) authorizedParty=\(Self.redactedClientID(payload.authorizedParty ?? "-"))")
        let avatarURL: String?
        if let picture = payload.picture?.nilIfEmpty {
            avatarURL = picture
        } else {
            avatarURL = try await fetchUserInfoPictureURL(accessToken: tokenResponse.accessToken)
        }
        return GoogleOAuthIdentity(
            googleID: payload.googleID,
            email: payload.email,
            name: payload.name,
            avatarURL: avatarURL,
            idToken: idToken
        )
    }

    private func decodeIdentityPayload(fromIDToken idToken: String, expectedNonce: String) throws -> (googleID: String, email: String, name: String, picture: String?, audience: String?, authorizedParty: String?) {
        let payload = try Self.decodeJWTBody(IDTokenPayload.self, from: idToken)

        guard payload.nonce == expectedNonce else {
            throw GoogleOAuthServiceError.invalidNonce
        }

        guard let googleID = payload.sub?.nilIfEmpty else {
            throw GoogleOAuthServiceError.missingGoogleIdentifier
        }

        guard let email = payload.email?.nilIfEmpty else {
            throw GoogleOAuthServiceError.missingEmail
        }

        let name = payload.name?.nilIfEmpty ?? email.components(separatedBy: "@").first ?? "Conta Google"
        return (googleID, email, name, payload.picture?.nilIfEmpty, payload.aud?.nilIfEmpty, payload.azp?.nilIfEmpty)
    }

    private func fetchUserInfoPictureURL(accessToken: String?) async throws -> String? {
        guard let accessToken = accessToken?.nilIfEmpty else { return nil }
        guard let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else {
            return nil
        }

        var request = URLRequest(url: userInfoURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                return nil
            }

            let userInfo = try JSONDecoder().decode(UserInfoResponse.self, from: data)
            return userInfo.picture?.nilIfEmpty
        } catch {
            return nil
        }
    }

    private static func formURLEncodedBody(_ fields: [String: String]) -> Data? {
        let body = fields
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "\(key.urlQueryEncoded)=\(value.urlQueryEncoded)"
            }
            .joined(separator: "&")
        return body.data(using: .utf8)
    }

    private static func extractMessage(from data: Data) -> String? {
        guard data.isEmpty == false else { return nil }

        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["error_description"] as? String ?? object["error"] as? String ?? object["message"] as? String,
            message.isEmpty == false
        {
            return message
        }

        if let text = String(data: data, encoding: .utf8), text.isEmpty == false {
            return text
        }

        return nil
    }

    private static func decodeJWTBody<T: Decodable>(_ type: T.Type, from token: String) throws -> T {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            throw GoogleOAuthServiceError.invalidIdentityToken
        }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }

        guard let data = Data(base64Encoded: base64) else {
            throw GoogleOAuthServiceError.invalidIdentityToken
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GoogleOAuthServiceError.invalidIdentityToken
        }
    }

    private static func parameters(from url: URL) -> [String: String] {
        var parameters: [String: String] = [:]

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                parameters[item.name] = item.value
            }
        }

        if let fragment = url.fragment,
           let fragmentComponents = URLComponents(string: "?\(fragment)") {
            for item in fragmentComponents.queryItems ?? [] {
                parameters[item.name] = item.value
            }
        }

        return parameters
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func mapTransportError(_ error: URLError) -> String {
        switch error.code {
        case .cancelled:
            return "O login com Google foi cancelado."
        case .notConnectedToInternet:
            return "Sem conexão com a internet para continuar o login com Google."
        case .timedOut:
            return "O Google demorou para responder. Tente novamente."
        default:
            return error.localizedDescription
        }
    }

    private static func mockIdentityFromEnvironment() -> GoogleOAuthIdentity? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard
            let googleID = environment["UITEST_GOOGLE_OAUTH_GOOGLE_ID"]?.nilIfEmpty,
            let email = environment["UITEST_GOOGLE_OAUTH_EMAIL"]?.nilIfEmpty,
            let name = environment["UITEST_GOOGLE_OAUTH_NAME"]?.nilIfEmpty
        else {
            return nil
        }

        let avatarURL = environment["UITEST_GOOGLE_OAUTH_AVATAR_URL"]?.nilIfEmpty
        let idToken = environment["UITEST_GOOGLE_OAUTH_ID_TOKEN"]?.nilIfEmpty ?? "uitest-google-id-token"
        return GoogleOAuthIdentity(googleID: googleID, email: email, name: name, avatarURL: avatarURL, idToken: idToken)
        #else
        return nil
        #endif
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[BillEasy][GoogleOAuth] \(message)")
        #endif
    }

    private static func redactedClientID(_ clientID: String) -> String {
        guard let first = clientID.split(separator: ".").first else { return "configured" }
        return "\(first.prefix(8))..."
    }

    private static func redactedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let firstCharacter = parts[0].first else { return "redacted" }
        return "\(firstCharacter)***@\(parts[1])"
    }
}

@MainActor
private final class GoogleWebOAuthViewController: UIViewController, WKNavigationDelegate {
    private let configuration: GoogleWebOAuthConfiguration
    private let expectedNonce: String
    private let completion: (Result<String, Error>) -> Void
    private var hasCompleted = false

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .secondaryLabel
        button.addTarget(self, action: #selector(handleCloseTapped), for: .touchUpInside)
        return button
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = .label
        label.text = "Entrar com Google"
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = "Continue no navegador para fazer login com sua conta Google."
        return label
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        return indicator
    }()

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isHidden = true
        return webView
    }()

    init(
        configuration: GoogleWebOAuthConfiguration,
        expectedNonce: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        self.configuration = configuration
        self.expectedNonce = expectedNonce
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        startFlow()
    }

    static func authenticate(
        configuration: GoogleWebOAuthConfiguration,
        expectedNonce: String,
        presenter: UIViewController
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let controller = GoogleWebOAuthViewController(
                configuration: configuration,
                expectedNonce: expectedNonce
            ) { result in
                continuation.resume(with: result)
            }

            presenter.present(controller, animated: true)
        }
    }

    private func configureUI() {
        view.backgroundColor = UIColor.systemBackground

        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(activityIndicator)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),

            webView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func startFlow() {
        guard
            let clientID = configuration.clientID,
            let redirectURI = configuration.redirectURI,
            let authorizationURL = makeAuthorizationURL(clientID: clientID, redirectURI: redirectURI)
        else {
            finish(with: .failure(GoogleOAuthServiceError.notConfigured))
            return
        }

        webView.load(URLRequest(url: authorizationURL))
    }

    private func makeAuthorizationURL(clientID: String, redirectURI: URL) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "token id_token"),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "nonce", value: expectedNonce)
        ]
        return components?.url
    }

    private func matchesCallback(_ url: URL) -> Bool {
        guard let redirectURI = configuration.redirectURI else { return false }
        let lhsPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rhsPath = redirectURI.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return url.scheme == redirectURI.scheme && url.host == redirectURI.host && lhsPath == rhsPath
    }

    private func maybeHandleCallback(url: URL) -> Bool {
        guard matchesCallback(url) else { return false }
        let parameters = Self.parameters(from: url)

        if let error = parameters["error"]?.nilIfEmpty {
            finish(with: .failure(GoogleOAuthServiceError.authorizationFailed(error)))
            return true
        }

        guard let idToken = parameters["id_token"]?.nilIfEmpty else {
            return false
        }

        finish(with: .success(idToken))
        return true
    }

    private func maybeHandleHashString(_ hash: String) {
        guard hash.isEmpty == false else { return }
        let sanitizedHash = hash.hasPrefix("#") ? String(hash.dropFirst()) : hash
        guard let components = URLComponents(string: "?\(sanitizedHash)") else { return }
        let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        if let error = parameters["error"]?.nilIfEmpty {
            finish(with: .failure(GoogleOAuthServiceError.authorizationFailed(error)))
            return
        }

        guard let idToken = parameters["id_token"]?.nilIfEmpty else { return }
        finish(with: .success(idToken))
    }

    private func finish(with result: Result<String, Error>) {
        guard hasCompleted == false else { return }
        hasCompleted = true

        dismiss(animated: true) { [completion] in
            completion(result)
        }
    }

    @objc
    private func handleCloseTapped() {
        finish(with: .failure(GoogleOAuthServiceError.cancelled))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, maybeHandleCallback(url: url) {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        webView.isHidden = false

        guard let currentURL = webView.url, matchesCallback(currentURL) else { return }

        webView.evaluateJavaScript("window.location.hash") { [weak self] result, _ in
            guard let self, let hash = result as? String else { return }
            self.maybeHandleHashString(hash)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard hasCompleted == false else { return }
        finish(with: .failure(GoogleOAuthServiceError.network(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard hasCompleted == false else { return }
        finish(with: .failure(GoogleOAuthServiceError.network(error.localizedDescription)))
    }

    private static func parameters(from url: URL) -> [String: String] {
        var parameters: [String: String] = [:]

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                parameters[item.name] = item.value
            }
        }

        if let fragment = url.fragment,
           let fragmentComponents = URLComponents(string: "?\(fragment)") {
            for item in fragmentComponents.queryItems ?? [] {
                parameters[item.name] = item.value
            }
        }

        return parameters
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?/"))) ?? self
    }
}
