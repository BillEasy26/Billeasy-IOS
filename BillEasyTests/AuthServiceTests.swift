import Foundation
import Testing
@testable import BillEasy

@Suite(.serialized)
struct AuthServiceTests {

    @Test("AuthService local mode register/login/logout flow")
    func localModeFlowWorks() async throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let localStore = LocalAuthStore(defaults: helper.defaults)
        let service = AuthService(mode: .local, localStore: localStore)

        let registered = try await service.register(
            nome: "Servico",
            email: "servico@teste.com",
            telefone: "",
            cpfCnpj: "",
            senha: "123456"
        )
        #expect(service.currentSession()?.userID == registered.userID)

        let logged = try await service.login(email: "SERVICO@teste.com", senha: "123456")
        #expect(logged.userID == registered.userID)

        service.logout()
        #expect(service.currentSession() == nil)
    }

    @Test("AuthService local mode validates password reset account existence")
    func localModePasswordResetValidation() async {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let localStore = LocalAuthStore(defaults: helper.defaults)
        let service = AuthService(mode: .local, localStore: localStore)

        do {
            try await service.requestPasswordReset(email: "nao@existe.com")
            Issue.record("Expected accountNotFound to be thrown.")
        } catch AuthServiceError.accountNotFound {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("AuthService local Apple login uses fallback email when not provided")
    func localAppleLoginFallbacks() async throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let localStore = LocalAuthStore(defaults: helper.defaults)
        let service = AuthService(mode: .local, localStore: localStore)

        let session = try await service.loginWithApple(
            identityToken: "token",
            userIdentifier: "abc123",
            email: nil,
            fullName: nil
        )

        #expect(session.provider == .apple)
        #expect(session.email.contains("apple_abc123"))
        #expect(session.displayName == "Conta Apple")
    }

    @Test("AuthService remote register maps hostname failures to a clear Portuguese message")
    func remoteRegisterMapsHostnameFailures() async {
        let session = makeMockSession { _ in
            throw URLError(.cannotFindHost)
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        do {
            _ = try await service.register(
                nome: "Samuel",
                email: "samuel@example.com",
                telefone: "11999999999",
                cpfCnpj: "06427166174",
                senha: "Senha@123"
            )
            Issue.record("Expected remote register to fail with a mapped network error.")
        } catch let error as AuthServiceError {
            #expect(error.errorDescription == "Não foi possível localizar o servidor da API. Verifique a configuração do app ou tente novamente.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("AuthService remote register does not auto-login before email verification")
    func remoteRegisterDoesNotAutoLogin() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/usuarios", request.httpMethod == "POST" {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data())
            }

            Issue.record("Unexpected request during remote register: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        let createdSession = try await service.register(
            nome: "Samuel Jammes",
            email: "samuel@example.com",
            telefone: "11999999999",
            cpfCnpj: "06427166174",
            senha: "Senha@123"
        )

        #expect(createdSession.provider == .email)
        #expect(createdSession.email == "samuel@example.com")
        #expect(createdSession.displayName == "Samuel Jammes")
    }

    @Test("AuthService remote login falha se a sessão remota não puder ser validada")
    func remoteLoginRequiresRemoteSessionValidation() async {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            switch url.path {
            case "/auth/login":
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data())

            case "/api/session/me":
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (
                    response,
                    #"{"message":"Não autenticado. Faça login para continuar."}"#.data(using: .utf8)!
                )

            default:
                Issue.record("Unexpected request during remote login: \(url.absoluteString)")
                throw URLError(.unsupportedURL)
            }
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        do {
            _ = try await service.login(email: "samuel@example.com", senha: "Senha@123")
            Issue.record("Expected remote login to fail when /api/session/me is unauthorized.")
        } catch let error as AuthServiceError {
            #expect(error.errorDescription == "Não foi possível validar sua sessão. Faça login novamente.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("AuthService remote validate password reset token decodes current backend payload")
    func remoteValidatePasswordResetTokenDecodesBackendShape() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/auth/validar-token-reset")
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "token" })?.value == "token.jwt")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let payload = """
            {"valido":true,"usuarioId":"usr-123","email":"samuel@example.com"}
            """.data(using: .utf8)!
            return (response, payload)
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        let validation = try await service.validatePasswordResetToken("token.jwt")
        #expect(validation.isValid)
        #expect(validation.userID == "usr-123")
        #expect(validation.email == "samuel@example.com")
        #expect(validation.errorMessage == nil)
    }

    @Test("AuthService remote reset password uses tokenReset and novaSenha")
    func remoteResetPasswordUsesCurrentPayload() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/auth/redefinir-senha")
            let body = try bodyData(from: request)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(object["tokenReset"] == "reset-token")
            #expect(object["novaSenha"] == "NovaSenha@123")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let payload = """
            {"message":"Senha alterada com sucesso. Você já pode fazer login com sua nova senha."}
            """.data(using: .utf8)!
            return (response, payload)
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        let message = try await service.resetPassword(tokenReset: "reset-token", novaSenha: "NovaSenha@123")
        #expect(message.contains("Senha alterada com sucesso"))
    }

    @Test("AuthService remote verify email and resend verification use current web endpoints")
    func remoteEmailVerificationEndpointsStayAligned() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            if url.path == "/api/auth/verificar-email" {
                let body = try bodyData(from: request)
                let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
                #expect(object["token"] == "verify-token")

                return (response, #"{"message":"Email verificado com sucesso! Você já pode fazer login."}"#.data(using: .utf8)!)
            }

            if url.path == "/api/auth/reenviar-verificacao" {
                let body = try bodyData(from: request)
                let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
                #expect(object["email"] == "samuel@example.com")

                return (response, #"{"message":"Email de verificação enviado! Verifique sua caixa de entrada."}"#.data(using: .utf8)!)
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        let verifyMessage = try await service.verifyEmail(token: "verify-token")
        #expect(verifyMessage.contains("Email verificado com sucesso"))

        let resendMessage = try await service.resendVerification(email: "samuel@example.com")
        #expect(resendMessage.contains("Email de verificação enviado"))
    }

    @Test("AuthService remote Google login envia documento e telefone no primeiro cadastro OAuth")
    func remoteGoogleLoginSendsOAuthCompletionPayload() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/auth/oauth/google" {
                let body = try bodyData(from: request)
                let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
                #expect(object["idToken"] == "google-id-token")
                #expect(object["documento"] == "06427166174")
                #expect(object["telefone"] == "11999999999")

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data())
            }

            if url.path == "/api/session/me" {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let payload = """
                {
                  "id":"user-google-123",
                  "nome":"Samuel Jammes",
                  "email":"samuel@example.com",
                  "telefone":"11999999999",
                  "empresaId":null,
                  "perfilDevedor":false,
                  "papeis":["USUARIO"]
                }
                """.data(using: .utf8)!
                return (response, payload)
            }

            Issue.record("Unexpected request during Google OAuth login: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        let authSession = try await service.loginWithGoogle(
            googleId: "google-123",
            email: "samuel@example.com",
            nome: "Samuel Jammes",
            idToken: "google-id-token",
            documento: "064.271.661-74",
            telefone: "(11) 99999-9999"
        )

        #expect(authSession.provider == .google)
        #expect(authSession.phone == "11999999999")
    }

    @Test("AuthService identifica quando OAuth precisa completar CPF/CNPJ e telefone")
    func remoteGoogleLoginDetectsOAuthCompletionRequirement() async {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            #expect(url.path == "/auth/oauth/google")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                #"{"error":"Primeiro acesso via OAuth exige CPF/CNPJ e telefone."}"#.data(using: .utf8)!
            )
        }

        let service = AuthService(
            session: session,
            environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
            mode: .remote
        )

        do {
            _ = try await service.loginWithGoogle(
                googleId: "google-123",
                email: "samuel@example.com",
                nome: "Samuel Jammes",
                idToken: "google-id-token"
            )
            Issue.record("Expected OAuth completion error.")
        } catch let error as AuthServiceError {
            #expect(error.requiresOAuthProfileCompletion)
            #expect(error.errorDescription == "Primeiro acesso via OAuth exige CPF/CNPJ e telefone.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        AuthServiceMockURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthServiceMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw URLError(.zeroByteResource)
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)

            if readCount < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }

            if readCount == 0 {
                break
            }

            data.append(buffer, count: readCount)
        }

        return data
    }
}

struct RemoteSecurityContextTests {

    @Test("RemoteSecurityContext preserves raw XSRF cookie when backend clears it and refreshes masked token")
    func preservesRawCookieAcrossMaskedRefresh() throws {
        let context = RemoteSecurityContext.shared
        context.reset()
        defer { context.reset() }
        let cookieStorage = try #require(URLSessionConfiguration.ephemeral.httpCookieStorage)
        cookieStorage.removeCookies(since: .distantPast)

        let loginURL = try #require(URL(string: "https://api.example.com/auth/login"))
        let loginResponse = try #require(
            HTTPURLResponse(
                url: loginURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie": "XSRF-TOKEN=raw-login-token; Path=/; Secure; SameSite=Lax",
                    "X-CSRF-TOKEN": "masked-login-token"
                ]
            )
        )

        context.captureSecurityState(from: loginResponse)

        let sessionURL = try #require(URL(string: "https://api.example.com/api/session/me"))
        let sessionResponse = try #require(
            HTTPURLResponse(
                url: sessionURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie": "XSRF-TOKEN=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/; Secure; SameSite=Lax",
                    "X-CSRF-TOKEN": "masked-session-token"
                ]
            )
        )

        context.captureSecurityState(from: sessionResponse)

        let snapshot = context.debugSnapshot()
        #expect(snapshot.csrfToken == "masked-session-token")
        #expect(snapshot.xsrfCookieValue == "raw-login-token")

        var protectedRequest = URLRequest(
            url: try #require(URL(string: "https://api.example.com/api/exato/pessoa-fisica"))
        )
        context.applySecurityHeaders(to: &protectedRequest, cookieStorage: cookieStorage)

        #expect(protectedRequest.value(forHTTPHeaderField: "X-XSRF-TOKEN") == "masked-session-token")

        let storedCookie = cookieStorage.cookies(for: try #require(protectedRequest.url))?.first(where: { $0.name == "XSRF-TOKEN" })
        #expect(storedCookie?.value == "raw-login-token")
    }
}

private final class AuthServiceMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
