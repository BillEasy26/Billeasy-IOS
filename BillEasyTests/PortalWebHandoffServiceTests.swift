import Foundation
import Testing
@testable import BillEasy

struct PortalWebHandoffServiceTests {

    @Test("PortalWebHandoffService cria handoff para /localizar")
    @MainActor
    func fetchURLUsesExpectedRouteForDebtorLocator() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/auth/mobile-web-handoff")
            #expect(request.httpMethod == "POST")

            let body = try bodyData(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["redirect"] == "/localizar")

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "handoffUrl": "https://api.billeasy.com.br/api/auth/mobile-handoff?token=abc123"
                }
                """.utf8)
            )
        }

        let service = PortalWebHandoffService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let handoffURL = try await service.fetchURL(for: .debtorLocator)
        #expect(handoffURL.absoluteString == "https://api.billeasy.com.br/api/auth/mobile-handoff?token=abc123")
    }

    @Test("PortalWebHandoffService cria handoff para /meu-plano")
    @MainActor
    func fetchURLUsesExpectedRouteForMyPlan() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            let body = try bodyData(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["redirect"] == "/meu-plano")

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "handoffUrl": "https://api.billeasy.com.br/api/auth/mobile-handoff?token=xyz789"
                }
                """.utf8)
            )
        }

        let service = PortalWebHandoffService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let handoffURL = try await service.fetchURL(for: .myPlan)
        #expect(handoffURL.absoluteString == "https://api.billeasy.com.br/api/auth/mobile-handoff?token=xyz789")
    }

    @Test("PortalWebHandoffService bloqueia o fluxo em modo local")
    @MainActor
    func fetchURLFailsInLocalMode() async {
        let service = PortalWebHandoffService(mode: .local)

        await #expect(throws: PortalWebHandoffError.self) {
            _ = try await service.fetchURL(for: .myPlan)
        }
    }

    @Test("PortalWebHandoffService rejeita URL inválida vinda do backend")
    @MainActor
    func fetchURLRejectsInvalidBackendURL() async {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "handoffUrl": "%%%%"
                }
                """.utf8)
            )
        }

        let service = PortalWebHandoffService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        await #expect(throws: PortalWebHandoffError.self) {
            _ = try await service.fetchURL(for: .debtorLocator)
        }
    }

    @Test("PortalWebHandoffService renova a sessão quando o handoff volta 401")
    @MainActor
    func fetchURLRefreshesExpiredSessionForMobileWebHandoff() async throws {
        let securityContext = RemoteSecurityContext.shared
        securityContext.reset()
        defer { securityContext.reset() }

        seed(
            securityContext: securityContext,
            accessToken: "expired-access-token",
            refreshToken: "refresh-token-123"
        )

        var requestStep = 0
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            requestStep += 1

            switch requestStep {
            case 1:
                #expect(url.path == "/api/auth/mobile-web-handoff")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access-token")

                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data("""
                    {
                      "message": "Não autenticado. Faça login para continuar."
                    }
                    """.utf8)
                )

            case 2:
                #expect(url.path == "/auth/refresh")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

                let body = try bodyData(from: request)
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
                #expect(json["refreshToken"] == "refresh-token-123")

                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": "application/json",
                            "Set-Cookie": "be_at=renewed-access-token; Path=/; Secure; SameSite=Lax"
                        ]
                    )!,
                    Data("{}".utf8)
                )

            case 3:
                #expect(url.path == "/api/auth/mobile-web-handoff")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-access-token")

                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data("""
                    {
                      "handoffUrl": "https://api.billeasy.com.br/api/auth/mobile-handoff?token=retry-ok"
                    }
                    """.utf8)
                )

            default:
                throw URLError(.badServerResponse)
            }
        }

        let service = PortalWebHandoffService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!),
                securityContext: securityContext
            ),
            mode: .remote
        )

        let handoffURL = try await service.fetchURL(for: .debtorLocator)
        #expect(handoffURL.absoluteString == "https://api.billeasy.com.br/api/auth/mobile-handoff?token=retry-ok")
        #expect(requestStep == 3)
    }

    private func makeMockSession(
        responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = responder
        return URLSession(configuration: configuration)
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let data = request.httpBody {
            return data
        }

        guard let bodyStream = request.httpBodyStream else {
            throw URLError(.cannotParseResponse)
        }

        bodyStream.open()
        defer { bodyStream.close() }

        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while bodyStream.hasBytesAvailable {
            let read = bodyStream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                throw bodyStream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }

        return data
    }

    private func seed(
        securityContext: RemoteSecurityContext,
        accessToken: String,
        refreshToken: String
    ) {
        let baseURL = URL(string: "https://api.example.com")!

        let accessResponse = HTTPURLResponse(
            url: baseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "be_at=\(accessToken); Path=/; Secure; SameSite=Lax"]
        )!
        securityContext.captureSecurityState(from: accessResponse, fallbackRequestURL: baseURL)

        let refreshResponse = HTTPURLResponse(
            url: baseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "be_rt=\(refreshToken); Path=/; Secure; SameSite=Lax"]
        )!
        securityContext.captureSecurityState(from: refreshResponse, fallbackRequestURL: baseURL)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
