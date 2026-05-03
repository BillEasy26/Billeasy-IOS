//
//  RemoteAPIClient.swift
//  BillEasy
//

import Foundation

/// Indica qual serviço backend deve receber a requisição.
enum RemoteServiceTarget {
    /// Backend principal em Java (autenticação, dívidas, contratos, etc.).
    case backend
    /// Serviço de IA em Node (OCR, transcrição de áudio, extração de campos).
    case ai
}

/// Erros que podem ocorrer ao se comunicar com os serviços remotos.
enum RemoteAPIClientError: LocalizedError {
    case serviceUnavailable(String)
    case invalidURL
    case invalidResponse
    case serializationFailed
    case networkOffline
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .serviceUnavailable(message):
            return message
        case .invalidURL:
            return "URL remota inválida."
        case .invalidResponse:
            return "Resposta remota inválida."
        case .serializationFailed:
            return "Falha ao serializar a requisição."
        case .networkOffline:
            return "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case let .server(statusCode, message):
            if statusCode >= 500 { return "O servidor está temporariamente indisponível. Tente novamente em instantes." }
            if statusCode == 429 { return "Muitas tentativas. Aguarde alguns instantes e tente novamente." }
            return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Ocorreu um erro inesperado. Tente novamente."
                : message
        }
    }
}

/// URLs base e tokens necessários para se comunicar com os serviços remotos.
/// Carregado do `Info.plist` via xcconfig; pode ser sobrescrito em testes.
struct APIEnvironment {
    let backendBaseURL: URL
    let aiServiceBaseURL: URL?
    /// Token de autenticação serviço-a-serviço do microserviço de IA (não exposto ao usuário).
    let aiServiceToken: String?

    init(backendBaseURL: URL, aiServiceBaseURL: URL? = nil, aiServiceToken: String? = nil) {
        self.backendBaseURL = backendBaseURL
        self.aiServiceBaseURL = aiServiceBaseURL
        self.aiServiceToken = Self.trimmed(aiServiceToken ?? "")
    }

    /// Inicializador padrão: lê as URLs do `Info.plist` (configuradas via xcconfig).
    init(bundle: Bundle = .main) {
        self.backendBaseURL = Self.resolveBackendURL(from: bundle)
        self.aiServiceBaseURL = Self.resolveOptionalURL(bundle.object(forInfoDictionaryKey: "AI_SERVICE_BASE_URL") as? String)
        self.aiServiceToken = Self.trimmed(bundle.object(forInfoDictionaryKey: "AI_SERVICE_TOKEN") as? String ?? "")
    }

    /// `true` se o proxy de IA via backend autenticado está disponível.
    var hasAIProxyConfigured: Bool {
        !backendBaseURL.absoluteString.isEmpty
    }

    /// `true` se o serviço de IA direto (Node) está configurado com URL e token.
    var hasPrivilegedAIServiceConfigured: Bool {
        aiServiceBaseURL != nil && aiServiceToken?.isEmpty == false
    }

    /// Lê a URL do backend do `Info.plist`. Em DEBUG usa localhost como fallback seguro.
    private static func resolveBackendURL(from bundle: Bundle) -> URL {
        let rawValue = bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        if let rawValue, let trimmed = trimmed(rawValue), let url = URL(string: trimmed) {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:8080")!
        #else
        // Em produção, API_BASE_URL deve estar configurado no xcconfig do target Release.
        assertionFailure("API_BASE_URL não está configurado no build de produção.")
        return URL(string: "https://api.billeasy.com.br")!
        #endif
    }

    private static func resolveOptionalURL(_ rawValue: String?) -> URL? {
        guard let rawValue, let trimmed = trimmed(rawValue) else { return nil }
        return URL(string: trimmed)
    }

    private static func trimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Gerencia o estado de segurança compartilhado entre requisições remotas:
/// token CSRF, cookie XSRF e tokens de acesso/refresh.
/// Thread-safe via `NSLock`.
final class RemoteSecurityContext {
    private struct StoredCookie {
        let value: String
        let domain: String
        let path: String
        let isSecure: Bool
    }

    static let shared = RemoteSecurityContext()

    private let lock = NSLock()
    private var csrfToken: String?
    private var xsrfCookie: StoredCookie?
    private var accessToken: String?
    private var refreshToken: String?

    private init() {
        // Carrega os tokens persistidos no Keychain ao inicializar (sobrevivem ao restart do app).
        accessToken = KeychainTokenStore.shared.loadAccessToken()
        refreshToken = KeychainTokenStore.shared.loadRefreshToken()
    }

    /// Injeta os headers de segurança necessários na requisição:
    /// `X-XSRF-TOKEN` (CSRF), `Authorization: Bearer` e o cookie XSRF.
    func applySecurityHeaders(
        to request: inout URLRequest,
        includeAuthorization: Bool = true,
        cookieStorage: HTTPCookieStorage = .shared
    ) {
        lock.lock()
        let currentCSRFToken = csrfToken
        let currentCSRFCookie = xsrfCookie
        let currentAccessToken = accessToken
        lock.unlock()

        if let currentCSRFToken, !currentCSRFToken.isEmpty {
            request.setValue(currentCSRFToken, forHTTPHeaderField: "X-XSRF-TOKEN")
        }
        if includeAuthorization, let currentAccessToken, !currentAccessToken.isEmpty {
            request.setValue("Bearer \(currentAccessToken)", forHTTPHeaderField: "Authorization")
        }
        guard let currentCSRFCookie, let requestURL = request.url else { return }
        storeCookie(currentCSRFCookie, for: requestURL, in: cookieStorage)
    }

    /// Captura e armazena o token CSRF e os cookies de sessão retornados pelo backend.
    /// Só atualiza um campo se o backend realmente enviou aquele cookie (evita sobrescrever com `nil`).
    func captureSecurityState(from response: URLResponse, fallbackRequestURL: URL? = nil) {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        if let token = httpResponse.value(forHTTPHeaderField: "X-CSRF-TOKEN"), !token.isEmpty {
            lock.lock()
            csrfToken = token
            lock.unlock()
        }

        guard let responseURL = httpResponse.url ?? fallbackRequestURL else { return }

        let headerFields = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else { return }
            result[key] = value
        }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: responseURL)
        var updatedCSRFCookie: StoredCookie?
        var updatedAccessToken: String?
        var updatedRefreshToken: String?
        var sawCSRFCookie = false
        var sawAccessCookie = false
        var sawRefreshCookie = false

        for cookie in cookies {
            let expiredOrEmpty = cookie.isExpired || cookie.value.isEmpty
            switch cookie.name {
            case "be_csrf", "XSRF-TOKEN":
                sawCSRFCookie = true
                if !expiredOrEmpty {
                    updatedCSRFCookie = StoredCookie(value: cookie.value, domain: cookie.domain, path: cookie.path, isSecure: cookie.isSecure)
                }
            case "be_at", "fa_at", "access_token":
                sawAccessCookie = true
                if !expiredOrEmpty { updatedAccessToken = cookie.value }
            case "be_rt", "fa_rt", "refresh_token":
                sawRefreshCookie = true
                if !expiredOrEmpty { updatedRefreshToken = cookie.value }
            default:
                continue
            }
        }

        lock.lock()
        if sawCSRFCookie { xsrfCookie = updatedCSRFCookie }
        if sawAccessCookie { accessToken = updatedAccessToken }
        if sawRefreshCookie { refreshToken = updatedRefreshToken }
        let tokenSnapshot = (access: updatedAccessToken, refresh: updatedRefreshToken)
        lock.unlock()

        // Persiste no Keychain para sobreviver ao restart do app.
        if sawAccessCookie, let token = tokenSnapshot.access { KeychainTokenStore.shared.saveAccessToken(token) }
        if sawRefreshCookie, let token = tokenSnapshot.refresh { KeychainTokenStore.shared.saveRefreshToken(token) }
    }

    /// Limpa todos os tokens de sessão da memória e do Keychain (usado no logout).
    func reset() {
        lock.lock()
        csrfToken = nil
        xsrfCookie = nil
        accessToken = nil
        refreshToken = nil
        lock.unlock()
        KeychainTokenStore.shared.clear()
    }

    /// Retorna o refresh token atual (usado para renovar a sessão sem pedir login novamente).
    func currentRefreshToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return refreshToken
    }

    /// Retorna se já temos token/header e cookie CSRF para uma nova tentativa segura.
    func hasCSRFState() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return csrfToken?.isEmpty == false && xsrfCookie != nil
    }

    /// Exposição de depuração do estado interno — disponível apenas em builds DEBUG.
    #if DEBUG
    func debugSnapshot() -> (csrfToken: String?, xsrfCookieValue: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (csrfToken, xsrfCookie?.value)
    }
    #endif

    /// Injeta o cookie XSRF no `HTTPCookieStorage` da requisição, preenchendo domain e path se necessário.
    private func storeCookie(_ cookie: StoredCookie, for requestURL: URL, in cookieStorage: HTTPCookieStorage) {
        let domain = cookie.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (requestURL.host ?? "")
            : cookie.domain
        guard !domain.isEmpty else { return }
        let path = cookie.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : cookie.path

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "XSRF-TOKEN",
            .value: cookie.value,
            .domain: domain,
            .path: path
        ]
        if cookie.isSecure || requestURL.scheme?.lowercased() == "https" {
            properties[.secure] = "TRUE"
        }
        guard let httpCookie = HTTPCookie(properties: properties) else { return }
        cookieStorage.setCookie(httpCookie)
    }
}

/// Cliente HTTP central do app. Gerencia requisições JSON e uploads multipart
/// para os dois serviços remotos (backend Java e serviço de IA Node).
/// Inclui renovação automática de sessão em caso de erro 401.
final class RemoteAPIClient {
    private struct EmptyResponse: Decodable {}
    private enum RefreshAttemptResult { case refreshed, unavailable }

    private let session: URLSession
    private let environment: APIEnvironment
    private let securityContext: RemoteSecurityContext
    private let cookieStorage: HTTPCookieStorage
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        environment: APIEnvironment = APIEnvironment(),
        securityContext: RemoteSecurityContext = .shared,
        cookieStorage: HTTPCookieStorage? = nil
    ) {
        self.session = session
        self.environment = environment
        self.securityContext = securityContext
        self.cookieStorage = cookieStorage ?? session.configuration.httpCookieStorage ?? .shared

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Configuração de ambiente atual (URLs e tokens). Exposto para serviços que decidem fallback.
    var currentEnvironment: APIEnvironment { environment }

    /// Remove tokens e cookies do backend antes de iniciar um novo login público.
    /// Evita que um Bearer/cookie antigo faça o backend tratar `/api/auth/*` como chamada autenticada.
    func clearBackendAuthenticationState() {
        securityContext.reset()
        clearCookies(for: environment.backendBaseURL)
    }

    // MARK: - Requisições sem corpo de resposta

    /// Envia uma requisição sem body e ignora o corpo da resposta (útil para logout, por exemplo).
    func sendVoid(target: RemoteServiceTarget, path: String, method: String) async throws {
        let _: EmptyResponse = try await request(target: target, path: path, method: method, body: Optional<String>.none)
    }

    /// Envia uma requisição com body JSON e ignora o corpo da resposta.
    func sendVoid<Body: Encodable>(target: RemoteServiceTarget, path: String, method: String, body: Body? = nil) async throws {
        let _: EmptyResponse = try await request(target: target, path: path, method: method, body: body)
    }

    // MARK: - Requisições JSON tipadas

    /// Executa uma requisição GET e decodifica a resposta no tipo `Response`.
    func request<Response: Decodable>(target: RemoteServiceTarget, path: String, method: String = "GET") async throws -> Response {
        try await request(target: target, path: path, method: method, body: Optional<String>.none)
    }

    /// Executa uma requisição com body JSON opcional e decodifica a resposta no tipo `Response`.
    /// Aplica automaticamente headers de segurança (CSRF, Bearer) e gerencia cookies.
    func request<Response: Decodable, Body: Encodable>(
        target: RemoteServiceTarget,
        path: String,
        method: String = "GET",
        body: Body? = nil
    ) async throws -> Response {
        let endpointURL = try resolveURL(target: target, path: path)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        applyTargetHeaders(
            for: target,
            path: path,
            to: &request,
            includeAuthorization: shouldSendAuthorization(target: target, path: path)
        )
        if let body { request.httpBody = try encode(body) }

        let data = try await perform(request, target: target)
        return try decode(Response.self, from: data)
    }

    // MARK: - Upload multipart

    /// Envia um arquivo via `multipart/form-data` e decodifica a resposta JSON.
    /// Usado para upload de documentos (OCR), fotos de perfil e gravações de áudio.
    /// - Parameters:
    ///   - fileFieldName: Nome do campo do arquivo no formulário (ex.: `"file"`, `"audio"`).
    ///   - additionalFormFields: Campos de texto adicionais enviados junto com o arquivo.
    ///   - timeoutInterval: Timeout personalizado para uploads grandes (substitui o padrão).
    func upload<Response: Decodable>(
        target: RemoteServiceTarget,
        path: String,
        fileFieldName: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        additionalFormFields: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Response {
        let endpointURL = try resolveURL(target: target, path: path)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        if let timeoutInterval { request.timeoutInterval = timeoutInterval }
        applyTargetHeaders(
            for: target,
            path: path,
            to: &request,
            includeAuthorization: shouldSendAuthorization(target: target, path: path)
        )
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            fileFieldName: fileFieldName,
            fileData: fileData,
            filename: filename,
            mimeType: mimeType,
            additionalFormFields: additionalFormFields
        )

        let data = try await perform(request, target: target)
        return try decode(Response.self, from: data)
    }

    // MARK: - Download de dados brutos

    /// Baixa dados brutos de um endpoint (ex.: PDF de contrato) sem decodificação JSON.
    func download(target: RemoteServiceTarget, path: String, method: String = "GET") async throws -> Data {
        let endpointURL = try resolveURL(target: target, path: path)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = method
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = true
        applyTargetHeaders(
            for: target,
            path: path,
            to: &request,
            includeAuthorization: shouldSendAuthorization(target: target, path: path)
        )

        return try await perform(request, target: target)
    }

    // MARK: - Privado

    /// Monta a URL completa combinando a base do serviço com o caminho do endpoint.
    private func resolveURL(target: RemoteServiceTarget, path: String) throws -> URL {
        let baseURL: URL
        switch target {
        case .backend:
            baseURL = environment.backendBaseURL
        case .ai:
            guard let aiServiceBaseURL = environment.aiServiceBaseURL else {
                throw RemoteAPIClientError.serviceUnavailable("Serviço de IA não configurado no app.")
            }
            baseURL = aiServiceBaseURL
        }
        guard let endpointURL = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RemoteAPIClientError.invalidURL
        }
        return endpointURL
    }

    /// Aplica os headers corretos para cada serviço:
    /// CSRF + Bearer para o backend, token service-to-service para o serviço de IA.
    private func applyTargetHeaders(
        for target: RemoteServiceTarget,
        path: String,
        to request: inout URLRequest,
        includeAuthorization: Bool = true
    ) {
        switch target {
        case .backend:
            securityContext.applySecurityHeaders(to: &request, includeAuthorization: includeAuthorization, cookieStorage: cookieStorage)
        case .ai:
            if let token = environment.aiServiceToken, !token.isEmpty {
                request.setValue(token, forHTTPHeaderField: "X-Service-Token")
            }
        }
    }

    /// Executa a requisição e, em caso de erro 401 no backend, tenta renovar a sessão uma vez
    /// antes de repassar o erro para quem chamou.
    private func perform(
        _ request: URLRequest,
        target: RemoteServiceTarget,
        allowRefreshRetry: Bool = true,
        allowCSRFRetry: Bool = true
    ) async throws -> Data {
        do {
            return try await performRaw(request)
        } catch let error as RemoteAPIClientError {
            if target == .backend, allowCSRFRetry, shouldRetryAfterCSRFFailure(error: error, request: request) {
                var retryRequest = request
                applyTargetHeaders(
                    for: target,
                    path: retryRequest.url?.path ?? "",
                    to: &retryRequest,
                    includeAuthorization: retryRequest.value(forHTTPHeaderField: "Authorization") != nil
                )
                Self.debugLog("Retrying \(retryRequest.httpMethod ?? "GET") \(retryRequest.url?.path ?? "-") after CSRF bootstrap.")
                return try await perform(
                    retryRequest,
                    target: target,
                    allowRefreshRetry: allowRefreshRetry,
                    allowCSRFRetry: false
                )
            }

            guard target == .backend, allowRefreshRetry, shouldRetryAfterUnauthorized(error: error, request: request) else {
                throw error
            }
            let refreshResult = try await refreshBackendSession()
            guard refreshResult == .refreshed else { throw error }

            // Reinjeta os novos headers (token atualizado) e tenta novamente.
            var retryRequest = request
            applyTargetHeaders(
                for: target,
                path: retryRequest.url?.path ?? "",
                to: &retryRequest
            )
            return try await perform(retryRequest, target: target, allowRefreshRetry: false)
        }
    }

    /// Executa a requisição HTTP pura, captura o estado de segurança da resposta
    /// e lança erro tipado em caso de falha de rede ou status HTTP != 2xx.
    private func performRaw(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
                throw RemoteAPIClientError.networkOffline
            default:
                throw RemoteAPIClientError.serviceUnavailable("Erro de conexão. Verifique sua rede e tente novamente.")
            }
        }

        // Captura tokens CSRF e cookies de sessão retornados pelo backend.
        securityContext.captureSecurityState(from: response, fallbackRequestURL: request.url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteAPIClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RemoteAPIClientError.server(statusCode: httpResponse.statusCode, message: Self.extractErrorMessage(from: data))
        }
        return data
    }

    /// Tenta renovar a sessão usando o refresh token.
    /// Espelha o comportamento do frontend web: ao receber 401, tenta o `/auth/refresh` antes de falhar.
    private func refreshBackendSession() async throws -> RefreshAttemptResult {
        struct RefreshRequestBody: Encodable { let refreshToken: String }

        let refreshURL = try resolveURL(target: .backend, path: APIRoutes.Auth.refresh)

        var refreshRequest = URLRequest(url: refreshURL)
        refreshRequest.httpMethod = "POST"
        refreshRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        refreshRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        refreshRequest.httpShouldHandleCookies = true
        // Não inclui o Bearer expirado para não gerar loop.
        applyTargetHeaders(for: .backend, path: APIRoutes.Auth.refresh, to: &refreshRequest, includeAuthorization: false)

        if let refreshToken = securityContext.currentRefreshToken(), !refreshToken.isEmpty {
            refreshRequest.httpBody = try encode(RefreshRequestBody(refreshToken: refreshToken))
        }

        do {
            _ = try await performRaw(refreshRequest)
            return .refreshed
        } catch let error as RemoteAPIClientError {
            if case let .server(statusCode, _) = error, statusCode == 401 { return .unavailable }
            throw error
        }
    }

    /// Decide se deve tentar renovar a sessão após um 401.
    /// Rotas de autenticação nunca entram nesse fluxo para evitar loops infinitos.
    private func shouldRetryAfterUnauthorized(error: RemoteAPIClientError, request: URLRequest) -> Bool {
        guard case let .server(statusCode, _) = error, statusCode == 401 else { return false }
        guard let path = request.url?.path else { return false }

        let noRetryPaths: Set<String> = [
            APIRoutes.Auth.login, APIRoutes.Auth.logout, APIRoutes.Auth.refresh,
            APIRoutes.Auth.forgotPassword, APIRoutes.Auth.validateResetToken, APIRoutes.Auth.resetPassword,
            APIRoutes.Auth.verifyEmail, APIRoutes.Auth.resendVerification,
            APIRoutes.Auth.googleCallback, APIRoutes.Auth.googleLink, APIRoutes.Auth.googleUnlink,
            APIRoutes.Auth.appleCallback
        ]
        return !noRetryPaths.contains(path)
    }

    private func shouldRetryAfterCSRFFailure(error: RemoteAPIClientError, request: URLRequest) -> Bool {
        guard case let .server(statusCode, _) = error, statusCode == 403 else { return false }
        guard request.value(forHTTPHeaderField: "X-XSRF-TOKEN") == nil else { return false }
        guard securityContext.hasCSRFState() else { return false }

        let mutatingMethods: Set<String> = ["POST", "PUT", "PATCH", "DELETE"]
        let method = request.httpMethod?.uppercased() ?? "GET"
        return mutatingMethods.contains(method)
    }

    private func shouldSendAuthorization(target: RemoteServiceTarget, path: String) -> Bool {
        guard target == .backend else { return false }
        let publicAuthPaths: Set<String> = [
            APIRoutes.Auth.login,
            APIRoutes.Auth.forgotPassword,
            APIRoutes.Auth.validateResetToken,
            APIRoutes.Auth.resetPassword,
            APIRoutes.Auth.verifyEmail,
            APIRoutes.Auth.resendVerification,
            APIRoutes.Auth.googleCallback,
            APIRoutes.Auth.appleCallback
        ]
        return !publicAuthPaths.contains(path)
    }

    private func clearCookies(for baseURL: URL) {
        guard let host = baseURL.host else { return }
        let authenticationCookieNames: Set<String> = [
            "be_at", "fa_at", "access_token",
            "be_rt", "fa_rt", "refresh_token",
            "be_csrf", "XSRF-TOKEN",
            "JSESSIONID"
        ]
        cookieStorage.cookies?
            .filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return (host == domain || host.hasSuffix(".\(domain)") || domain.hasSuffix(".\(host)"))
                    && authenticationCookieNames.contains(cookie.name)
            }
            .forEach { cookieStorage.deleteCookie($0) }
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[BillEasy][RemoteAPIClient] \(message)")
        #endif
    }

    /// Serializa o body para JSON. Lança `serializationFailed` em caso de erro.
    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do { return try encoder.encode(body) } catch { throw RemoteAPIClientError.serializationFailed }
    }

    /// Decodifica os dados da resposta no tipo esperado.
    /// Para `EmptyResponse`, retorna diretamente sem tentar decodificar.
    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response { return empty }
        if data.isEmpty { throw RemoteAPIClientError.invalidResponse }
        return try decoder.decode(Response.self, from: data)
    }

    /// Monta manualmente o corpo `multipart/form-data`.
    /// Evita dependência de biblioteca externa para um formato relativamente simples.
    private func makeMultipartBody(
        boundary: String,
        fileFieldName: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        additionalFormFields: [String: String]
    ) -> Data {
        var body = Data()
        for (key, value) in additionalFormFields.sorted(by: { $0.key < $1.key }) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    // MARK: - Extração de mensagem de erro

    /// Tenta extrair uma mensagem legível pelo usuário do corpo da resposta de erro.
    /// Suporta JSON aninhado, strings duplo-codificadas e diferentes formatos do backend.
    static func extractUserFacingErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dictionary = object as? [String: Any] {
                return extractUserFacingErrorMessage(from: dictionary)
            }
            if let rawString = object as? String,
               let nestedData = rawString.data(using: .utf8),
               let nestedMessage = extractUserFacingErrorMessage(from: nestedData) {
                return nestedMessage
            }
        }

        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           let nestedData = text.data(using: .utf8),
           let nestedJSONObject = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any],
           let nestedMessage = extractUserFacingErrorMessage(from: nestedJSONObject) {
            return nestedMessage
        }
        return nil
    }

    /// Extrai a mensagem de erro do corpo da resposta, tentando diferentes encodings como fallback.
    private static func extractErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "Falha na comunicação com o servidor." }
        if let userMessage = extractUserFacingErrorMessage(from: data) { return userMessage }

        for encoding in [String.Encoding.utf8, .isoLatin1] {
            guard let text = String(data: data, encoding: encoding) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let nestedData = trimmed.data(using: .utf8),
               let nestedMessage = extractUserFacingErrorMessage(from: nestedData) {
                return nestedMessage
            }
            return trimmed
        }
        return "Falha na comunicação com o servidor."
    }

    /// Procura a mensagem de erro em chaves conhecidas do JSON do backend (Java e Node).
    /// Também busca recursivamente em objetos e arrays aninhados.
    private static func extractUserFacingErrorMessage(from dictionary: [String: Any]) -> String? {
        // Chaves priorizadas em ordem: mais específico → mais genérico.
        let candidateKeys = ["detalhe", "detail", "mensagemParaUsuario", "userMessage", "message", "error", "erro", "title"]
        for key in candidateKeys {
            if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for value in dictionary.values {
            if let nested = value as? [String: Any], let message = extractUserFacingErrorMessage(from: nested) { return message }
            if let nestedArray = value as? [[String: Any]] {
                for item in nestedArray {
                    if let message = extractUserFacingErrorMessage(from: item) { return message }
                }
            }
        }
        return nil
    }
}

// MARK: - Extensões privadas

private extension HTTPCookie {
    /// `true` se o cookie já passou da data de expiração.
    var isExpired: Bool {
        expiresDate.map { $0 <= Date() } ?? false
    }
}

private extension Data {
    /// Acrescenta uma string UTF-8 ao `Data` de forma conveniente (usado na construção multipart).
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
