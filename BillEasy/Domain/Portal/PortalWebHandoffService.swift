import Foundation

enum PortalWebHandoffDestination: String, CaseIterable {
    case debtorLocator = "/app/localizar-devedor"
    case myPlan = "/app/conta/plano"

    var nextPath: String {
        rawValue
    }
}

enum PortalWebHandoffError: LocalizedError {
    case unavailableInLocalMode
    case missingFrontendBaseURL
    case invalidToken
    case invalidHandoffURL

    var errorDescription: String? {
        switch self {
        case .unavailableInLocalMode:
            return "Este atalho web só está disponível quando o app estiver conectado à sua conta online."
        case .missingFrontendBaseURL:
            return "Não encontrei a URL da versão web configurada neste build."
        case .invalidToken:
            return "Recebi um token de acesso inválido do servidor. Tente novamente."
        case .invalidHandoffURL:
            return "Recebi uma URL inválida do servidor. Tente novamente."
        }
    }
}

/// Aqui eu centralizo o bridge mobile → web para que a UI não precise conhecer
/// o contrato de token temporário do backend.
final class PortalWebHandoffService {
    private struct ResponseBody: Decodable {
        let token: String
    }

    private let apiClient: RemoteAPIClient
    private let mode: AppAuthMode
    private let frontendBaseURL: URL?

    init(
        apiClient: RemoteAPIClient = RemoteAPIClient(),
        mode: AppAuthMode = AppRuntimeConfiguration.authMode,
        frontendBaseURL: URL? = FrontendWebRouteBuilder.resolveBaseURL()
    ) {
        self.apiClient = apiClient
        self.mode = mode
        self.frontendBaseURL = frontendBaseURL
    }

    var isAvailable: Bool {
        mode == .remote
    }

    func fetchURL(for destination: PortalWebHandoffDestination) async throws -> URL {
        guard isAvailable else {
            throw PortalWebHandoffError.unavailableInLocalMode
        }
        guard let frontendBaseURL else {
            throw PortalWebHandoffError.missingFrontendBaseURL
        }

        let response: ResponseBody = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Auth.mobileHandoff,
            method: "POST"
        )

        let token = response.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty == false else {
            throw PortalWebHandoffError.invalidToken
        }

        guard var components = URLComponents(
            url: frontendBaseURL.appendingPathComponent("handoff"),
            resolvingAgainstBaseURL: false
        ) else {
            throw PortalWebHandoffError.invalidHandoffURL
        }
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "next", value: destination.nextPath)
        ]

        guard let url = components.url, url.scheme?.isEmpty == false else {
            throw PortalWebHandoffError.invalidHandoffURL
        }

        return url
    }
}
