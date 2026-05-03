import Foundation
import Testing
@testable import BillEasy

struct PortalPrivacyServiceTests {

    @Test("PortalPrivacyService baixa meus dados pela rota LGPD remota")
    @MainActor
    func downloadMyDataUsesExpectedRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/lgpd/meus-dados/download")
            #expect(request.httpMethod == "GET")

            let data = Data("""
            {
              "dadosPessoais": {
                "nome": "Samuel Jammes"
              }
            }
            """.utf8)

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }

        let service = PortalPrivacyService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let fileURL = try await service.downloadMyData()
        let data = try Data(contentsOf: fileURL)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("Samuel Jammes"))
    }

    @Test("PortalPrivacyService consulta o preview LGPD pela rota /api/lgpd/meus-dados")
    @MainActor
    func fetchMyDataUsesExpectedRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/lgpd/meus-dados")
            #expect(request.httpMethod == "GET")

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "dataExportacao": "2026-04-13T19:00:00Z",
                  "usuarioId": "8d3d9b1a-a9c2-4bc4-b16f-f38c4e7f0f25",
                  "dadosPessoais": {
                    "nome": "Samuel Jammes",
                    "email": "samuel@billeasy.ia",
                    "status": "ATIVO"
                  },
                  "papeis": ["USUARIO"],
                  "permissoes": ["perfil:editar"]
                }
                """.utf8)
            )
        }

        let service = PortalPrivacyService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let result = try await service.fetchMyData()
        #expect(result.dadosPessoais?.nome == "Samuel Jammes")
        #expect(result.papeis?.first == "USUARIO")
    }

    @Test("PortalPrivacyService anonimiza a própria conta pelo endpoint LGPD")
    @MainActor
    func anonymizeMyAccountUsesExpectedRouteAndBody() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/lgpd/minha-conta")
            #expect(request.httpMethod == "DELETE")

            let body = try bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(json?["motivo"] as? String == "Solicitação do titular")

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
                Data("""
                {
                  "sucesso": true,
                  "mensagem": "Sua conta foi anonimizada. Você será desconectado."
                }
                """.utf8)
            )
        }

        let service = PortalPrivacyService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let result = try await service.anonymizeMyAccount(reason: "   ")
        #expect(result.sucesso == true)
        #expect(result.mensagem == "Sua conta foi anonimizada. Você será desconectado.")
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
