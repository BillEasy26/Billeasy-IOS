import Foundation

enum PortalWebHandoffDestination: String, CaseIterable {
    case debtorLocator = "/localizar"
    case myPlan = "/meu-plano"

    var redirectPath: String {
        rawValue
    }
}

enum PortalWebHandoffError: LocalizedError {
    case unavailableInLocalMode
    case invalidHandoffURL

    var errorDescription: String? {
        switch self {
        case .unavailableInLocalMode:
            return "Este atalho web só está disponível quando o app estiver conectado à sua conta online."
        case .invalidHandoffURL:
            return "Recebi uma URL inválida do servidor. Tente novamente."
        }
    }
}

/// Aqui eu centralizo o bridge mobile → web para que a UI não precise conhecer
/// o contrato de token temporário do backend.
final class PortalWebHandoffService {
    private struct RequestBody: Encodable {
        let redirect: String
    }

    private struct ResponseBody: Decodable {
        let handoffUrl: String
    }

    private let apiClient: RemoteAPIClient
    private let mode: AppAuthMode

    init(
        apiClient: RemoteAPIClient = RemoteAPIClient(),
        mode: AppAuthMode = AppRuntimeConfiguration.authMode
    ) {
        self.apiClient = apiClient
        self.mode = mode
    }

    var isAvailable: Bool {
        mode == .remote
    }

    func fetchURL(for destination: PortalWebHandoffDestination) async throws -> URL {
        guard isAvailable else {
            throw PortalWebHandoffError.unavailableInLocalMode
        }

        let response: ResponseBody = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Auth.mobileWebHandoff,
            method: "POST",
            body: RequestBody(redirect: destination.redirectPath)
        )

        guard let url = URL(string: response.handoffUrl), url.scheme?.isEmpty == false else {
            throw PortalWebHandoffError.invalidHandoffURL
        }

        return url
    }
}
