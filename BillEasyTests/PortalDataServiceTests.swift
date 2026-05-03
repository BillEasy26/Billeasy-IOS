import Foundation
import Testing
@testable import BillEasy

struct PortalDataServiceTests {

    @Test("PortalDataService expõe paginação do feed receber com page e size")
    func receivableDebtPagePreservesPagingMetadata() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/dividas/receber")
            #expect(url.query?.contains("page=2") == true)
            #expect(url.query?.contains("size=10") == true)

            return jsonResponse(
                url: url,
                json: """
                {
                  "content": [
                    {
                      "id": "div-201",
                      "descricao": "Recebível paginado",
                      "valorPrincipal": 350.00,
                      "status": "NAO_PAGO",
                      "dataVencimento": "2026-04-05",
                      "devedor": { "id": "dev-1", "cpfCnpjEnc": "123.456.789-00" },
                      "contrato": { "id": "ctr-201", "titulo": "Contrato 201" },
                      "credorCriador": { "id": "cred-1", "nome": "Minha Empresa SA", "cnpj": "12.345.678/0001-90" },
                      "totais": {
                        "totalDevidoBruto": 350.00,
                        "diasEmAtraso": 0,
                        "emAtraso": false,
                        "totalPago": 0.0,
                        "totalDevidoLiquido": 350.00
                      }
                    }
                  ],
                  "page": {
                    "size": 10,
                    "number": 2,
                    "totalElements": 31,
                    "totalPages": 4
                  }
                }
                """
            )
        }

        let service = PortalDataService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let page = try await service.fetchReceivableDebtPage(page: 2, size: 10)

        #expect(page.pageNumber == 2)
        #expect(page.pageSize == 10)
        #expect(page.totalElements == 31)
        #expect(page.totalPages == 4)
        #expect(page.isLastPage == false)
        #expect(page.debts.count == 1)
    }

    @Test("PortalDataService remote creditor snapshot consumes the receivable debts route")
    func remoteCreditorSnapshotUsesReceivableDebtsRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/dividas/receber" {
                #expect(url.query?.contains("page=0") == true)
                #expect(url.query?.contains("size=20") == true)
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "content": [
                        {
                          "id": "div-1",
                          "descricao": "Empréstimo Pessoal",
                          "valorPrincipal": 500.00,
                          "status": "NAO_PAGO",
                          "dataVencimento": "2026-02-17T10:00:00Z",
                          "devedor": { "id": "dev-1", "cpfCnpjEnc": "123.456.789-00" },
                          "contrato": { "id": "ctr-1", "titulo": "Contrato 1" },
                          "credorCriador": { "id": "cred-1", "nome": "Minha Empresa SA", "cnpj": "12.345.678/0001-90" },
                          "totais": {
                            "totalDevidoBruto": 560.00,
                            "diasEmAtraso": 12,
                            "emAtraso": true,
                            "totalPago": 0.0,
                            "totalDevidoLiquido": 560.00
                          }
                        },
                        {
                          "id": "div-2",
                          "descricao": "Notebook Dell",
                          "valorPrincipal": 1000.50,
                          "status": "PAGO",
                          "dataVencimento": "2026-03-06",
                          "devedor": { "id": "dev-2", "cpfCnpjEnc": null },
                          "contrato": { "id": "ctr-2", "titulo": "Contrato 2" },
                          "credorCriador": { "id": "cred-1", "nome": "Minha Empresa SA", "cnpj": "12.345.678/0001-90" },
                          "totais": {
                            "totalDevidoBruto": 1000.50,
                            "diasEmAtraso": 0,
                            "emAtraso": false,
                            "totalPago": 1000.50,
                            "totalDevidoLiquido": 0.0
                          }
                        }
                      ],
                      "page": {
                        "size": 20,
                        "number": 0,
                        "totalElements": 2,
                        "totalPages": 1
                      }
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = PortalDataService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let snapshot = try await service.fetchCreditorSnapshot()

        #expect(snapshot.totalReceivable == Decimal(string: "500.00"))
        #expect(snapshot.totalRecovered == Decimal(string: "1000.50"))
        #expect(snapshot.debts.count == 2)
        #expect(snapshot.debts.first?.status == .vencida)
        #expect(snapshot.debts.first?.devedorNome == "Contrato 1")
        #expect(snapshot.debts.last?.status == .paga)
    }

    @Test("PortalDataService remote debtor snapshot consumes the payable debts route")
    func remoteDebtorSnapshotUsesPayableDebtsRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/dividas/pagar" {
                #expect(url.query?.contains("page=0") == true)
                #expect(url.query?.contains("size=20") == true)
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "content": [
                        {
                          "id": "div-pay-1",
                          "descricao": "Parcela 1/12 - Contrato Fornecedor ABC",
                          "valorPrincipal": 1500.00,
                          "status": "NAO_PAGO",
                          "dataVencimento": "2026-03-15",
                          "devedor": { "id": "dev-1", "cpfCnpjEnc": null },
                          "contrato": { "id": "ctr-10", "titulo": "Contrato Fornecedor ABC", "descricao": "Fornecimento" },
                          "credorCriador": { "id": "cred-9", "nome": "Fornecedor ABC Ltda", "cnpj": "12.345.678/0001-90" },
                          "totais": {
                            "totalDevidoBruto": 1620.00,
                            "diasEmAtraso": 16,
                            "emAtraso": true,
                            "totalPago": 0.0,
                            "totalDevidoLiquido": 1620.00
                          }
                        },
                        {
                          "id": "div-pay-2",
                          "descricao": "Parcela 2/12 - Contrato Fornecedor ABC",
                          "valorPrincipal": 700.00,
                          "status": "PAGO",
                          "dataVencimento": "2026-04-15",
                          "devedor": { "id": "dev-1", "cpfCnpjEnc": null },
                          "contrato": { "id": "ctr-10", "titulo": "Contrato Fornecedor ABC", "descricao": "Fornecimento" },
                          "credorCriador": { "id": "cred-9", "nome": "Fornecedor ABC Ltda", "cnpj": "12.345.678/0001-90" },
                          "totais": {
                            "totalDevidoBruto": 700.00,
                            "diasEmAtraso": 0,
                            "emAtraso": false,
                            "totalPago": 700.00,
                            "totalDevidoLiquido": 0.0
                          }
                        }
                      ],
                      "page": {
                        "size": 20,
                        "number": 0,
                        "totalElements": 2,
                        "totalPages": 1
                      }
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = PortalDataService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let snapshot = try await service.fetchDebtorSnapshot()

        #expect(snapshot.totalPayable == Decimal(string: "1500.00"))
        #expect(snapshot.totalPaid == Decimal(string: "700.00"))
        #expect(snapshot.debts.count == 2)
        #expect(snapshot.debts.first?.status == .vencida)
        #expect(snapshot.debts.first?.devedorNome == "Fornecedor ABC Ltda")
        #expect(snapshot.debts.last?.status == .paga)
    }

    @Test("PortalDataService remote profile merges session and user detail routes")
    func remoteProfileMergesSessionAndUserDetails() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/session/me" {
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "status": "ATIVO",
                      "mfaHabilitado": true,
                      "emailVerificado": true,
                      "tipoUsuario": "ADMIN_CREDOR"
                    }
                    """
                )
            }

            if url.path == "/api/usuarios/usr-123", request.httpMethod == "GET" {
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "cpfCnpjEnc": "123.456.789-00",
                      "status": "ATIVO"
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = PortalDataService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let profile = try await service.fetchProfile()

        #expect(profile.userID == "usr-123")
        #expect(profile.fullName == "Samuel Jammes")
        #expect(profile.email == "samuel@billeasy.ai")
        #expect(profile.phone == "(11) 99999-0000")
        #expect(profile.document == "123.456.789-00")
        #expect(profile.userType == "ADMIN_CREDOR")
        #expect(profile.emailVerified == true)
        #expect(profile.mfaEnabled == true)
    }

    @Test("PortalDataService saves expanded remote profile when backend accepts extra fields")
    func saveProfileUsesExpandedPayloadWhenBackendSupportsIt() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/usuarios/usr-123", request.httpMethod == "PUT" {
                let body = try bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
                #expect(json?["nome"] == "Samuel Jammes")
                #expect(json?["telefone"] == "(11) 99999-0000")
                #expect(json?["email"] == "samuel@billeasy.ai")
                #expect(json?["cpfCnpjEnc"] == "123.456.789-00")
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "cpfCnpjEnc": "123.456.789-00",
                      "status": "ATIVO"
                    }
                    """
                )
            }

            if url.path == "/api/session/me" {
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "status": "ATIVO",
                      "mfaHabilitado": false,
                      "emailVerificado": true,
                      "tipoUsuario": "USUARIO"
                    }
                    """
                )
            }

            if url.path == "/api/usuarios/usr-123", request.httpMethod == "GET" {
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "cpfCnpjEnc": "123.456.789-00",
                      "status": "ATIVO"
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = PortalDataService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let result = try await service.saveProfile(
            userID: "usr-123",
            payload: PortalProfileUpdatePayload(
                fullName: "Samuel Jammes",
                email: "samuel@billeasy.ai",
                phone: "(11) 99999-0000",
                document: "123.456.789-00"
            )
        )

        #expect(result.syncMode == .expanded)
        #expect(result.profile.email == "samuel@billeasy.ai")
        #expect(result.profile.document == "123.456.789-00")
    }

    @Test("PortalDataService falls back to legacy profile update when backend rejects extra fields")
    func saveProfileFallsBackToLegacyUpdate() async throws {
        final class RequestTracker: @unchecked Sendable {
            var sawExpandedAttempt = false
            var sawLegacyFallback = false
        }

        let tracker = RequestTracker()
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/usuarios/usr-123", request.httpMethod == "PUT" {
                let body = try bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: String]

                if json?["email"] != nil || json?["cpfCnpjEnc"] != nil {
                    tracker.sawExpandedAttempt = true
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 400,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    let data = Data(#"{"message":"Unrecognized field \"email\""}"#.utf8)
                    return (response, data)
                }

                tracker.sawLegacyFallback = true
                #expect(json?["nome"] == "Samuel Jammes")
                #expect(json?["telefone"] == "(11) 99999-0000")
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "status": "ATIVO"
                    }
                    """
                )
            }

            if url.path == "/api/session/me" {
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "status": "ATIVO",
                      "mfaHabilitado": false,
                      "emailVerificado": true,
                      "tipoUsuario": "USUARIO"
                    }
                    """
                )
            }

            if url.path == "/api/usuarios/usr-123", request.httpMethod == "GET" {
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "usr-123",
                      "nome": "Samuel Jammes",
                      "email": "samuel@billeasy.ai",
                      "telefone": "(11) 99999-0000",
                      "cpfCnpjEnc": "",
                      "status": "ATIVO"
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = PortalDataService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let result = try await service.saveProfile(
            userID: "usr-123",
            payload: PortalProfileUpdatePayload(
                fullName: "Samuel Jammes",
                email: "samuel@billeasy.ai",
                phone: "(11) 99999-0000",
                document: "123.456.789-00"
            )
        )

        #expect(result.syncMode == .legacy)
        #expect(tracker.sawExpandedAttempt == true)
        #expect(tracker.sawLegacyFallback == true)
    }

    @Test("PortalDataService fetches the newest user attachment for profile photo sync")
    func fetchLatestUserAttachmentReturnsMostRecentItem() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/usuarios/usr-123/anexos")
            return jsonResponse(
                url: url,
                json: """
                [
                  {
                    "id": "att-older",
                    "nomeArquivo": "perfil-antigo.jpg",
                    "urlDownload": "/api/anexos/att-older/download",
                    "criadoEm": "2026-03-16T10:00:00Z"
                  },
                  {
                    "id": "att-newer",
                    "nomeArquivo": "perfil-novo.jpg",
                    "urlDownload": "/api/anexos/att-newer/download",
                    "criadoEm": "2026-03-17T10:00:00Z"
                  }
                ]
                """
            )
        }

        let service = PortalDataService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let attachment = try await service.fetchLatestUserAttachment(userID: "usr-123")

        #expect(attachment?.id == "att-newer")
        #expect(attachment?.fileName == "perfil-novo.jpg")
        #expect(attachment?.downloadPath == "/api/anexos/att-newer/download")
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func jsonResponse(url: URL, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = Data(json.utf8)
        return (response, data)
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let bodyStream = request.httpBodyStream else {
            throw URLError(.badServerResponse)
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
