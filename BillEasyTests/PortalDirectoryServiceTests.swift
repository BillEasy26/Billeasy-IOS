import Foundation
import Testing
@testable import BillEasy

struct PortalDirectoryServiceTests {

    @Test("PortalDirectoryService lista empresas pela rota paginada do backend")
    func listCompaniesUsesExpectedRemoteRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/empresas")
            #expect(url.query?.contains("page=0") == true)
            #expect(url.query?.contains("size=60") == true)
            #expect(url.query?.contains("nome=Bill") == true)

            return jsonResponse(
                url: url,
                json: """
                {
                  "content": [
                    {
                      "id": "emp-1",
                      "nome": "BillEasy Serviços",
                      "cpfCnpj": "12.345.678/0001-90",
                      "telefone": "61993011072",
                      "tipo": "PESSOA_JURIDICA",
                      "status": "ATIVA",
                      "responsavel": { "id": "usr-1", "nome": "Samuel" },
                      "endereco": {
                        "cep": "01310100",
                        "logradouro": "Avenida Paulista",
                        "numero": "1578",
                        "complemento": "Sala 12",
                        "bairro": "Bela Vista",
                        "cidade": "São Paulo",
                        "estado": "SP"
                      }
                    }
                  ]
                }
                """
            )
        }

        let helper = TestDefaultsHelper(prefix: "PortalDirectoryServiceTests")
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Samuel", email: "samuel@teste.com", telefone: "", cpfCnpj: "", senha: "123")
        let dataStore = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let service = PortalDirectoryService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote,
            dataStore: dataStore
        )

        let records = try await service.listCompanies(
            session: AuthSession(userID: "usr-1", displayName: "Samuel", email: "samuel@teste.com", provider: .email),
            searchName: "Bill"
        )

        #expect(records.count == 1)
        #expect(records.first?.name == "BillEasy Serviços")
        #expect(records.first?.addressSummary?.contains("Avenida Paulista") == true)
    }

    @Test("PortalDirectoryService cria devedor pela rota da empresa com payload alinhado ao backend")
    func createDebtorUsesCompanyScopedRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/empresas/emp-1/devedores")
            #expect(request.httpMethod == "POST")

            let body = try bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(json?["nome"] as? String == "Cliente Teste")
            #expect(json?["cpfCnpjEnc"] as? String == "06427166174")
            #expect(json?["email"] as? String == "cliente@teste.com")
            #expect(json?["telefone"] as? String == "61993011072")

            let address = json?["endereco"] as? [String: Any]
            #expect(address?["cep"] as? String == "01310100")
            #expect(address?["numero"] as? String == "1578")
            #expect(address?["complemento"] as? String == "Sala 12")

            return jsonResponse(
                url: url,
                json: """
                {
                  "id": "dev-1",
                  "nome": "Cliente Teste",
                  "cpfCnpjEnc": "06427166174",
                  "email": "cliente@teste.com",
                  "telefone": "61993011072",
                  "status": "ATIVO",
                  "empresa": { "id": "emp-1", "nome": "BillEasy Serviços" },
                  "endereco": {
                    "cep": "01310100",
                    "logradouro": "Avenida Paulista",
                    "numero": "1578",
                    "complemento": "Sala 12",
                    "bairro": "Bela Vista",
                    "cidade": "São Paulo",
                    "estado": "SP"
                  }
                }
                """
            )
        }

        let helper = TestDefaultsHelper(prefix: "PortalDirectoryServiceTests")
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Samuel", email: "samuel@teste.com", telefone: "", cpfCnpj: "", senha: "123")
        let dataStore = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let service = PortalDirectoryService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote,
            dataStore: dataStore
        )

        let record = try await service.createDebtor(
            session: AuthSession(userID: "usr-1", displayName: "Samuel", email: "samuel@teste.com", provider: .email, empresaID: "emp-1"),
            input: PortalDebtorFormInput(
                companyID: nil,
                name: "Cliente Teste",
                document: "064.271.661-74",
                email: "cliente@teste.com",
                phone: "(61) 99301-1072",
                cep: "01310-100",
                number: "1578",
                complement: "Sala 12"
            )
        )

        #expect(record.id == "dev-1")
        #expect(record.companyName == "BillEasy Serviços")
        #expect(record.addressSummary?.contains("Avenida Paulista") == true)
    }

    @Test("PortalDirectoryService usa a rota global de devedores para admin sem empresa vinculada")
    func listDebtorsUsesGlobalRouteForAdminWithoutCompany() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/devedores")
            #expect(url.query?.contains("page=0") == true)
            #expect(url.query?.contains("size=60") == true)
            #expect(url.query?.contains("nome=Maria") == true)

            return jsonResponse(
                url: url,
                json: """
                {
                  "content": [
                    {
                      "id": "dev-2",
                      "nome": "Maria Oliveira",
                      "cpfCnpjEnc": "12345678900",
                      "email": "maria@teste.com",
                      "telefone": "61981234567",
                      "status": "ATIVO",
                      "empresa": { "id": "emp-9", "nome": "Empresa Global" }
                    }
                  ]
                }
                """
            )
        }

        let helper = TestDefaultsHelper(prefix: "PortalDirectoryServiceTests")
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Admin", email: "admin@teste.com", telefone: "", cpfCnpj: "", senha: "123")
        let dataStore = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let service = PortalDirectoryService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote,
            dataStore: dataStore
        )

        let records = try await service.listDebtors(
            session: AuthSession(
                userID: "admin-1",
                displayName: "Admin",
                email: "admin@teste.com",
                provider: .email,
                roles: ["SUPER_ADMIN"]
            ),
            searchName: "Maria"
        )

        #expect(records.count == 1)
        #expect(records.first?.name == "Maria Oliveira")
        #expect(records.first?.companyName == "Empresa Global")
    }

    @Test("PortalDirectoryService inativa empresa usando DELETE /api/empresas/{id}/suspender e depois reidrata o detalhe")
    func suspendCompanyUsesExpectedLifecycleRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/empresas/emp-1/suspender" {
                #expect(url.path == "/api/empresas/emp-1/suspender")
                #expect(request.httpMethod == "DELETE")
                return (
                    HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            #expect(url.path == "/api/empresas/emp-1")
            #expect(request.httpMethod == "GET")
            return jsonResponse(
                url: url,
                json: """
                {
                  "id": "emp-1",
                  "nome": "BillEasy Serviços",
                  "cpfCnpj": "12.345.678/0001-90",
                  "telefone": "61993011072",
                  "tipo": "PESSOA_JURIDICA",
                  "status": "SUSPENSO"
                }
                """
            )
        }

        let helper = TestDefaultsHelper(prefix: "PortalDirectoryServiceTests")
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Samuel", email: "samuel@teste.com", telefone: "", cpfCnpj: "", senha: "123")
        let dataStore = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let service = PortalDirectoryService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote,
            dataStore: dataStore
        )

        let company = try await service.updateCompanyLifecycle(companyID: "emp-1", action: .suspend)

        #expect(company.status == "SUSPENSO")
        #expect(company.isActive == false)
    }

    @Test("PortalDirectoryService ativa devedor usando a rota escopada da empresa e reidrata o detalhe global")
    func activateDebtorUsesScopedLifecycleRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/empresas/emp-1/devedores/dev-1/ativar" {
                #expect(url.path == "/api/empresas/emp-1/devedores/dev-1/ativar")
                #expect(request.httpMethod == "PUT")
                return (
                    HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            #expect(url.path == "/api/devedores/dev-1")
            #expect(request.httpMethod == "GET")
            return jsonResponse(
                url: url,
                json: """
                {
                  "id": "dev-1",
                  "nome": "Cliente Teste",
                  "cpfCnpjEnc": "06427166174",
                  "email": "cliente@teste.com",
                  "telefone": "61993011072",
                  "status": "ATIVO",
                  "empresa": { "id": "emp-1", "nome": "BillEasy Serviços" }
                }
                """
            )
        }

        let helper = TestDefaultsHelper(prefix: "PortalDirectoryServiceTests")
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Samuel", email: "samuel@teste.com", telefone: "", cpfCnpj: "", senha: "123")
        let dataStore = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let service = PortalDirectoryService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote,
            dataStore: dataStore
        )

        let debtor = try await service.updateDebtorLifecycle(
            session: AuthSession(userID: "usr-1", displayName: "Samuel", email: "samuel@teste.com", provider: .email, empresaID: "emp-1"),
            debtorID: "dev-1",
            companyID: nil,
            action: .activate
        )

        #expect(debtor.status == "ATIVO")
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
        return (response, Data(json.utf8))
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
