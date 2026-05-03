import Foundation
import Testing
@testable import BillEasy

struct PortalSubscriptionServiceTests {

    @Test("PortalSubscriptionService carrega assinatura, cotas e planos pelas rotas do app Kotlin")
    @MainActor
    func fetchDashboardUsesCurrentSubscriptionRoutes() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            switch url.path {
            case "/api/planos":
                return jsonResponse(
                    url: url,
                    json: """
                    [
                      {
                        "id": "plan-free",
                        "nome": "Free",
                        "slug": "free",
                        "tipo": "FREE",
                        "precoMensal": 0,
                        "maxContratos": 3,
                        "maxConsultasDevedor": 1,
                        "trialDias": 0,
                        "permiteAddons": false
                      },
                      {
                        "id": "plan-standard",
                        "nome": "Standard",
                        "slug": "standard",
                        "tipo": "STANDARD",
                        "precoMensal": 19.90,
                        "maxContratos": 10,
                        "maxConsultasDevedor": 2,
                        "trialDias": 7,
                        "permiteAddons": true
                      }
                    ]
                    """
                )
            case "/api/assinaturas/minha":
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "sub-1",
                      "plano": {
                        "id": "plan-standard",
                        "nome": "Standard",
                        "slug": "standard",
                        "tipo": "STANDARD",
                        "precoMensal": 19.90,
                        "maxContratos": 10,
                        "maxConsultasDevedor": 2,
                        "trialDias": 7,
                        "permiteAddons": true
                      },
                      "status": "TRIAL",
                      "billingProvider": "APP_STORE",
                      "trialFimEm": "2026-04-09T12:00:00Z",
                      "contratosUtilizados": 2,
                      "consultasUtilizadasCiclo": 1,
                      "limiteContratosEfetivo": 10,
                      "limiteConsultasEfetivo": 2,
                      "addons": [
                        {
                          "id": "addon-1",
                          "tipoAddon": "ADDON_CONTRACT",
                          "quantidade": 1,
                          "precoUnitario": 5.90,
                          "ativo": true,
                          "statusPagamento": "PAGO",
                          "quantidadeDisponivel": 1,
                          "quantidadeConsumida": 0
                        }
                      ]
                    }
                    """
                )
            case "/api/assinaturas/minha/cotas":
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "limiteContratos": 10,
                      "contratosUtilizados": 2,
                      "creditosContratoAddon": 1,
                      "limiteConsultas": 2,
                      "consultasUtilizadas": 1,
                      "creditosConsultaAddon": 0,
                      "tipoPlano": "STANDARD",
                      "statusAssinatura": "TRIAL"
                    }
                    """
                )
            default:
                Issue.record("Unexpected request: \(url.absoluteString)")
                throw URLError(.unsupportedURL)
            }
        }

        let helper = TestDefaultsHelper(prefix: "PortalSubscriptionServiceTests")
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Samuel", email: "samuel@teste.com", telefone: "", cpfCnpj: "", senha: "123456")
        let dataStore = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let service = PortalSubscriptionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote,
            dataStore: dataStore
        )

        let dashboard = try await service.fetchDashboard()

        #expect(dashboard.current.id == "sub-1")
        #expect(dashboard.current.plan.name == "Standard")
        #expect(dashboard.current.status == "TRIAL")
        #expect(dashboard.current.billingProvider == "APP_STORE")
        #expect(dashboard.current.contractLimit == 11)
        #expect(dashboard.current.debtorQueryLimit == 2)
        #expect(dashboard.current.addons.first?.unitPrice == Decimal(string: "5.90"))
        #expect(dashboard.availablePlans.count == 2)
        #expect(dashboard.standardPlan?.id == "plan-standard")
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = handler
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
        if let body = request.httpBody {
            return body
        }
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            var data = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read < 0 {
                    throw stream.streamError ?? URLError(.cannotParseResponse)
                }
                if read == 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
        return Data()
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
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
