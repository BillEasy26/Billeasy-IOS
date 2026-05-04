//
//  AuthService.swift
//  BillEasy
//

import Foundation

/// Resultado da validação de um token de redefinição de senha.
struct PasswordResetTokenValidation {
    let isValid: Bool
    let userID: String?
    let email: String?
    let errorMessage: String?
}

/// Erros possíveis durante os fluxos de autenticação.
enum AuthServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String)
    case serializationFailed
    case network(message: String)
    case invalidCredentials
    case emailAlreadyRegistered
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL da API inválida."
        case .invalidResponse:
            return "Resposta inválida da API."
        case let .server(statusCode, message):
            if statusCode >= 500 {
                return "O servidor está temporariamente indisponível. Tente novamente em instantes."
            }
            if statusCode == 429 {
                return "Muitas tentativas. Aguarde alguns instantes e tente novamente."
            }
            return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Ocorreu um erro inesperado. Tente novamente."
                : message
        case .serializationFailed:
            return "Falha ao serializar a requisição."
        case let .network(message):
            return message
        case .invalidCredentials:
            return "E-mail ou senha inválidos."
        case .emailAlreadyRegistered:
            return "Este e-mail já está cadastrado."
        case .accountNotFound:
            return "Conta não encontrada para este e-mail."
        }
    }
}

extension AuthServiceError {
    var requiresOAuthProfileCompletion: Bool {
        guard case let .server(_, message) = self else { return false }
        return message.localizedCaseInsensitiveContains("Primeiro acesso via OAuth")
            || message.localizedCaseInsensitiveContains("CPF/CNPJ e telefone")
    }
}

/// Serviço central de autenticação. Abstrai o modo de operação (local ou remoto)
/// para que as telas não precisem saber como os dados são persistidos ou de onde vêm.
final class AuthService {

    // MARK: - Payloads de requisição (privados)

    private struct LoginRequest: Encodable {
        let email: String
        let senha: String
    }

    private struct RegisterRequest: Encodable {
        let nome: String
        let email: String
        let telefone: String
        let cpfCnpjEnc: String
        let senha: String
    }

    private struct EmailRequest: Encodable {
        let email: String
    }

    private struct TokenRequest: Encodable {
        let token: String
    }

    private struct ResetPasswordRequest: Encodable {
        let tokenReset: String
        let novaSenha: String
    }

    private struct GoogleLoginRequest: Encodable {
        let idToken: String
        let documento: String?
        let telefone: String?
    }

    private struct AppleLoginRequest: Encodable {
        let identityToken: String
        let userIdentifier: String
        let email: String?
        let fullName: String?
    }

    // MARK: - Payloads de resposta (privados)

    /// Dados do usuário retornados pelo endpoint de sessão.
    /// Aceita o contrato legado (`nome`, `telefone`, etc.) e o contrato atual do backend (`nomeCompleto`, `papel`).
    private struct RemoteSessionPayload: Decodable {
        let id: String
        let nome: String?
        let email: String
        let telefone: String?
        let empresaId: String?
        let perfilDevedor: Bool?
        let papeis: [String]?
        let papel: String?

        var normalizedRoles: [String] {
            var seen = Set<String>()
            return ((papeis ?? []) + [papel].compactMap { $0 })
                .compactMap { $0.nilIfEmpty }
                .filter { seen.insert($0).inserted }
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case nome
            case nomeCompleto
            case email
            case telefone
            case empresaId
            case perfilDevedor
            case papeis
            case papel
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            nome = try container.decodeIfPresent(String.self, forKey: .nome)
                ?? container.decodeIfPresent(String.self, forKey: .nomeCompleto)
            email = try container.decode(String.self, forKey: .email)
            telefone = try container.decodeIfPresent(String.self, forKey: .telefone)
            empresaId = try container.decodeIfPresent(String.self, forKey: .empresaId)
            perfilDevedor = try container.decodeIfPresent(Bool.self, forKey: .perfilDevedor)
            papeis = try container.decodeIfPresent([String].self, forKey: .papeis)
            papel = try container.decodeIfPresent(String.self, forKey: .papel)
        }
    }

    /// Resposta genérica de endpoints que retornam apenas uma mensagem de texto.
    private struct MessageResponse: Decodable {
        let message: String?
        let error: String?
    }

    /// Resposta do endpoint de validação de token de reset.
    /// Aceita tanto `valid` quanto `valido` (variações de API) e `userId` ou `usuarioId`.
    private struct PasswordResetTokenValidationResponse: Decodable {
        let isValid: Bool
        let userID: String?
        let email: String?
        let errorMessage: String?

        private enum CodingKeys: String, CodingKey {
            case valid, valido
            case userID = "userId"
            case usuarioID = "usuarioId"
            case email
            case error, message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isValid = try container.decodeIfPresent(Bool.self, forKey: .valid)
                ?? container.decodeIfPresent(Bool.self, forKey: .valido)
                ?? false
            userID = try container.decodeIfPresent(String.self, forKey: .userID)
                ?? container.decodeIfPresent(String.self, forKey: .usuarioID)
            email = try container.decodeIfPresent(String.self, forKey: .email)
            errorMessage = try container.decodeIfPresent(String.self, forKey: .error)
                ?? container.decodeIfPresent(String.self, forKey: .message)
        }
    }

    // MARK: - Dependências

    private let apiClient: RemoteAPIClient
    private let mode: AppAuthMode
    private let localStore: LocalAuthStore

    init(
        session: URLSession = .shared,
        environment: APIEnvironment = APIEnvironment(),
        mode: AppAuthMode = AppRuntimeConfiguration.authMode,
        localStore: LocalAuthStore = LocalAuthStore(),
        apiClient: RemoteAPIClient? = nil
    ) {
        self.apiClient = apiClient ?? RemoteAPIClient(session: session, environment: environment)
        self.mode = mode
        self.localStore = localStore
    }

    // MARK: - Interface pública

    /// `true` quando o app está operando totalmente offline (dados locais no dispositivo).
    var isLocalMode: Bool { mode == .local }

    /// Retorna a sessão do usuário logado. Em modo remoto, retorna `nil`
    /// (a sessão remota é gerenciada por cookies, não em memória local).
    func currentSession() -> AuthSession? {
        guard isLocalMode else { return nil }
        return localStore.currentSession()
    }

    /// Encerra a sessão do usuário.
    /// Em modo local, apaga o usuário ativo do `UserDefaults`.
    /// Em modo remoto, limpa os tokens e notifica o backend (fire-and-forget).
    func logout() {
        if isLocalMode {
            localStore.logout()
            return
        }
        RemoteSecurityContext.shared.reset()
        Task {
            try? await apiClient.sendVoid(target: .backend, path: APIRoutes.Auth.logout, method: "POST")
        }
    }

    /// Autentica com e-mail e senha.
    /// Em modo remoto, chama `/auth/login` e em seguida o endpoint de sessão para montar a sessão.
    func login(email: String, senha: String) async throws -> AuthSession {
        if isLocalMode {
            return try localStore.login(email: email, senha: senha)
        }
        apiClient.clearBackendAuthenticationState()
        try await performRemoteMutation(
            path: APIRoutes.Auth.login,
            method: "POST",
            body: LoginRequest(email: email, senha: senha)
        )
        return try await fetchRemoteSession(provider: .email, fallbackDisplayName: email, fallbackEmail: email)
    }

    /// Cadastra um novo usuário.
    /// Em modo remoto, o backend exige verificação de e-mail antes de liberar o login,
    /// por isso retorna uma sessão provisória sem chamar `/auth/login` automaticamente.
    @discardableResult
    func register(nome: String, email: String, telefone: String, cpfCnpj: String, senha: String) async throws -> AuthSession {
        if isLocalMode {
            return try localStore.register(nome: nome, email: email, telefone: telefone, cpfCnpj: cpfCnpj, senha: senha)
        }
        try await performRemoteMutation(
            path: APIRoutes.Usuarios.base,
            method: "POST",
            body: RegisterRequest(nome: nome, email: email, telefone: telefone, cpfCnpjEnc: cpfCnpj, senha: senha)
        )
        // O backend exige verificação de e-mail antes do primeiro login — retorna sessão provisória.
        return makeSession(userID: UUID().uuidString, displayName: nome, email: email, provider: .email, phone: telefone.nilIfEmpty)
    }

    /// Solicita o envio de e-mail para redefinição de senha.
    func requestPasswordReset(email: String) async throws {
        if isLocalMode {
            try localStore.requestPasswordReset(email: email)
            return
        }
        try await performRemoteMutation(path: APIRoutes.Auth.forgotPassword, method: "POST", body: EmailRequest(email: email))
    }

    /// Valida o token de redefinição de senha (link recebido por e-mail).
    /// Retorna se o token é válido e, se sim, o ID e e-mail do usuário associado.
    func validatePasswordResetToken(_ token: String) async throws -> PasswordResetTokenValidation {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        if isLocalMode {
            let isValid = !normalizedToken.isEmpty
            return PasswordResetTokenValidation(
                isValid: isValid,
                userID: nil,
                email: nil,
                errorMessage: isValid ? nil : "Token de recuperação inválido ou expirado."
            )
        }

        let response: PasswordResetTokenValidationResponse = try await apiClient.request(
            target: .backend,
            path: "\(APIRoutes.Auth.validateResetToken)?token=\(normalizedToken.encodedForURLQuery)"
        )
        return PasswordResetTokenValidation(
            isValid: response.isValid,
            userID: response.userID,
            email: response.email,
            errorMessage: response.errorMessage
        )
    }

    /// Define uma nova senha usando o token recebido por e-mail.
    /// Retorna a mensagem de confirmação do backend.
    @discardableResult
    func resetPassword(tokenReset: String, novaSenha: String) async throws -> String {
        if isLocalMode { return "Senha alterada com sucesso. Você já pode fazer login com sua nova senha." }
        return try await performRemoteMessageMutation(
            path: APIRoutes.Auth.resetPassword,
            method: "POST",
            body: ResetPasswordRequest(tokenReset: tokenReset, novaSenha: novaSenha),
            fallbackMessage: "Senha alterada com sucesso. Você já pode fazer login com sua nova senha."
        )
    }

    /// Confirma o e-mail do usuário usando o token recebido no link de verificação.
    @discardableResult
    func verifyEmail(token: String) async throws -> String {
        if isLocalMode { return "Email verificado com sucesso! Você já pode fazer login." }
        return try await performRemoteMessageMutation(
            path: APIRoutes.Auth.verifyEmail,
            method: "POST",
            body: TokenRequest(token: token),
            fallbackMessage: "Email verificado com sucesso! Você já pode fazer login."
        )
    }

    /// Reenvia o e-mail de verificação de cadastro.
    @discardableResult
    func resendVerification(email: String) async throws -> String {
        if isLocalMode { return "Se o email estiver cadastrado, você receberá as instruções de verificação." }
        return try await performRemoteMessageMutation(
            path: APIRoutes.Auth.resendVerification,
            method: "POST",
            body: EmailRequest(email: email),
            fallbackMessage: "Se o email estiver cadastrado, você receberá as instruções de verificação."
        )
    }

    /// Autentica com uma conta Google. Envia os dados validados pelo OAuth ao backend
    /// e em seguida busca a sessão completa no endpoint de sessão.
    func loginWithGoogle(
        googleId: String,
        email: String,
        nome: String,
        avatarURL: String? = nil,
        idToken: String? = nil,
        documento: String? = nil,
        telefone: String? = nil
    ) async throws -> AuthSession {
        if isLocalMode { return try localStore.loginSocial(provider: .google, email: email, nome: nome) }
        guard let idToken = idToken?.nilIfEmpty else {
            throw AuthServiceError.server(statusCode: 400, message: "O Google não retornou o token necessário para autenticar no servidor.")
        }
        let normalizedDocumento = Formatters.digitsOnly(documento ?? "").nilIfEmpty
        let normalizedTelefone = Formatters.digitsOnly(telefone ?? "").nilIfEmpty
        apiClient.clearBackendAuthenticationState()
        Self.debugGoogleLogin("POST \(APIRoutes.Auth.googleCallback) for \(Self.redactedEmail(email)).")
        do {
            do {
                try await apiClient.sendVoid(
                    target: .backend,
                    path: APIRoutes.Auth.googleCallback,
                    method: "POST",
                    body: GoogleLoginRequest(
                        idToken: idToken,
                        documento: normalizedDocumento,
                        telefone: normalizedTelefone
                    )
                )
            } catch let error as RemoteAPIClientError {
                Self.debugGoogleLogin("Raw backend Google error: \(Self.describeRemoteError(error))")
                throw mapGoogleRemoteError(error)
            } catch let error as URLError {
                throw mapTransportError(error)
            }
            Self.debugGoogleLogin("Google callback accepted. Fetching remote session.")
            let session = try await fetchRemoteSession(provider: .google, fallbackDisplayName: nome, fallbackEmail: email, fallbackAvatarURL: avatarURL)
            Self.debugGoogleLogin("Remote session fetched. userID=\(session.userID)")
            return session
        } catch {
            Self.debugGoogleLogin("Backend Google login failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Autentica com uma conta Apple.
    /// O Apple não retorna e-mail/nome em logins subsequentes — por isso usamos fallbacks locais.
    func loginWithApple(
        identityToken: String,
        userIdentifier: String,
        email: String?,
        fullName: String?
    ) async throws -> AuthSession {
        if isLocalMode {
            let localEmail = resolvedAppleEmail(userIdentifier: userIdentifier, email: email)
            let localName = fullName?.nilIfEmpty ?? "Conta Apple"
            return try localStore.loginSocial(provider: .apple, email: localEmail, nome: localName)
        }
        apiClient.clearBackendAuthenticationState()
        try await performRemoteMutation(
            path: APIRoutes.Auth.appleCallback,
            method: "POST",
            body: AppleLoginRequest(
                identityToken: identityToken,
                userIdentifier: userIdentifier,
                email: email?.nilIfEmpty,
                fullName: fullName?.nilIfEmpty
            )
        )
        return try await fetchRemoteSession(
            provider: .apple,
            fallbackDisplayName: fullName ?? "Conta Apple",
            fallbackEmail: email ?? resolvedAppleEmail(userIdentifier: userIdentifier, email: email)
        )
    }

    // MARK: - Privado

    /// Executa uma mutação remota sem payload de resposta (ex.: login, logout).
    /// Converte erros de rede e de API no contrato `AuthServiceError`.
    private func performRemoteMutation<Body: Encodable>(path: String, method: String, body: Body? = nil) async throws {
        do {
            try await apiClient.sendVoid(target: .backend, path: path, method: method, body: body)
        } catch let error as RemoteAPIClientError {
            throw mapRemoteError(error)
        } catch let error as URLError {
            throw mapTransportError(error)
        }
    }

    /// Executa uma mutação remota que retorna uma mensagem de texto (ex.: redefinição de senha).
    /// Usa `fallbackMessage` se o backend não retornar mensagem ou retornar vazia.
    private func performRemoteMessageMutation<Body: Encodable>(
        path: String,
        method: String,
        body: Body? = nil,
        fallbackMessage: String
    ) async throws -> String {
        do {
            let response: MessageResponse = try await apiClient.request(target: .backend, path: path, method: method, body: body)
            return response.message?.nilIfEmpty ?? response.error?.nilIfEmpty ?? fallbackMessage
        } catch let error as RemoteAPIClientError {
            throw mapRemoteError(error)
        } catch let error as URLError {
            throw mapTransportError(error)
        }
    }

    /// Busca os dados completos da sessão após um login bem-sucedido.
    /// Os parâmetros `fallback*` são usados se o endpoint retornar campos ausentes.
    private func fetchRemoteSession(
        provider: AuthProvider,
        fallbackDisplayName: String,
        fallbackEmail: String,
        fallbackAvatarURL: String? = nil
    ) async throws -> AuthSession {
        do {
            let payload: RemoteSessionPayload = try await apiClient.request(target: .backend, path: APIRoutes.Session.me)
            return makeSession(
                userID: payload.id,
                displayName: payload.nome?.nilIfEmpty ?? fallbackDisplayName,
                email: payload.email.nilIfEmpty ?? fallbackEmail,
                provider: provider,
                avatarURL: fallbackAvatarURL,
                empresaID: payload.empresaId?.nilIfEmpty,
                phone: payload.telefone?.nilIfEmpty,
                roles: payload.normalizedRoles,
                hasDebtorProfile: payload.perfilDevedor ?? false
            )
        } catch let error as RemoteAPIClientError {
            if case let .server(statusCode, _) = error, statusCode == 401 {
                throw AuthServiceError.server(statusCode: statusCode, message: "Não foi possível validar sua sessão. Faça login novamente.")
            }
            throw mapRemoteError(error)
        } catch let error as URLError {
            throw mapTransportError(error)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    /// Converte erros do `RemoteAPIClient` para o tipo `AuthServiceError` com mensagens em português.
    private func mapRemoteError(_ error: RemoteAPIClientError) -> AuthServiceError {
        switch error {
        case .invalidURL: return .invalidURL
        case .invalidResponse: return .invalidResponse
        case .serializationFailed: return .serializationFailed
        case .networkOffline: return .network(message: "Sem conexão com a internet. Verifique sua rede e tente novamente.")
        case let .serviceUnavailable(message): return .server(statusCode: 503, message: message)
        case let .server(statusCode, message):
            if statusCode == 401 { return .invalidCredentials }
            if statusCode == 404, message.localizedCaseInsensitiveContains("conta") { return .accountNotFound }
            if statusCode == 409 || message.localizedCaseInsensitiveContains("já cadastrado") { return .emailAlreadyRegistered }
            return .server(statusCode: statusCode, message: message)
        }
    }

    /// Preserva mensagens técnicas úteis do backend no login social.
    /// Um 401 aqui normalmente significa token Google recusado, não senha inválida.
    private func mapGoogleRemoteError(_ error: RemoteAPIClientError) -> AuthServiceError {
        if case let .server(statusCode, message) = error, statusCode == 401 {
            return .server(statusCode: statusCode, message: message)
        }
        return mapRemoteError(error)
    }

    /// Converte erros do `URLSession` para mensagens amigáveis de rede.
    private func mapTransportError(_ error: URLError) -> AuthServiceError {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return .network(message: "Não foi possível localizar o servidor da API. Verifique a configuração do app ou tente novamente.")
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff:
            return .network(message: "Sem conexão com a internet. Verifique sua rede e tente novamente.")
        case .timedOut:
            return .network(message: "A API demorou para responder. Tente novamente em instantes.")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired:
            return .network(message: "Não foi possível estabelecer uma conexão segura com a API.")
        default:
            return .network(message: "Falha de rede ao acessar a API. Tente novamente.")
        }
    }

    /// Cria um objeto `AuthSession` normalizando o e-mail para letras minúsculas.
    private func makeSession(
        userID: String,
        displayName: String,
        email: String,
        provider: AuthProvider,
        avatarURL: String? = nil,
        empresaID: String? = nil,
        phone: String? = nil,
        roles: [String] = [],
        hasDebtorProfile: Bool = false
    ) -> AuthSession {
        AuthSession(
            userID: userID,
            displayName: displayName,
            email: email.lowercased(),
            provider: provider,
            avatarURL: avatarURL,
            empresaID: empresaID,
            phone: phone,
            roles: roles,
            hasDebtorProfile: hasDebtorProfile
        )
    }

    /// Gera um e-mail local previsível quando o Apple não retorna o e-mail (logins subsequentes).
    private func resolvedAppleEmail(userIdentifier: String, email: String?) -> String {
        email?.nilIfEmpty ?? "apple_\(userIdentifier.prefix(8))@local.billeasy.ai"
    }

    private static func debugGoogleLogin(_ message: String) {
        #if DEBUG
        print("[BillEasy][AuthService][Google] \(message)")
        #endif
    }

    private static func describeRemoteError(_ error: RemoteAPIClientError) -> String {
        switch error {
        case .invalidURL:
            return "invalidURL"
        case .invalidResponse:
            return "invalidResponse"
        case .serializationFailed:
            return "serializationFailed"
        case .networkOffline:
            return "networkOffline"
        case let .serviceUnavailable(message):
            return "serviceUnavailable(\(message))"
        case let .server(statusCode, message):
            return "server(statusCode: \(statusCode), message: \(message))"
        }
    }

    private static func redactedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let firstCharacter = parts[0].first else { return "redacted" }
        return "\(firstCharacter)***@\(parts[1])"
    }
}

// MARK: - Extensões privadas de String

private extension String {
    /// Retorna `nil` se a string for vazia após remover espaços, ou a string trimada caso contrário.
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Codifica a string para uso seguro em query strings de URL (percent-encoding RFC 3986).
    var encodedForURLQuery: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
