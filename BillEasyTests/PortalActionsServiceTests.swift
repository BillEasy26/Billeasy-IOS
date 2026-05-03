import Foundation
import Testing
@testable import BillEasy

struct PortalActionsServiceTests {

    @Test("PortalActionsService lê o catálogo de formas de pagamento pela rota /api/formasDePagamentos")
    func fetchPaymentMethodsUsesCatalogRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/formasDePagamentos")
            #expect(request.httpMethod == "GET")

            return jsonResponse(
                url: url,
                json: """
                [
                  { "id": "fp-1", "tipoPagamento": "PIX" },
                  { "id": "fp-2", "tipoPagamento": "BOLETO", "descricao": "Pode levar até 3 dias" },
                  { "id": "fp-3", "tipoPagamento": "CARTAO_DE_CREDITO" },
                  { "id": "fp-4", "tipoPagamento": "CARTAO_DEBITO", "ativo": false }
                ]
                """
            )
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let methods = try await service.fetchPaymentMethods()

        #expect(methods.map(\.method) == [.pix, .boleto, .creditCard])
        #expect(methods[0].title == "Pagar com Pix")
        #expect(methods[1].subtitle == "Pode levar até 3 dias")
    }

    @Test("PortalActionsService preserva a ordem do backend e remove formas duplicadas do catálogo")
    func fetchPaymentMethodsPreservesBackendOrderAndDeduplicates() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/formasDePagamentos")

            return jsonResponse(
                url: url,
                json: """
                [
                  { "tipoPagamento": "BOLETO", "nome": "Boleto parcelado", "descricao": "Compensação em até 3 dias", "icone": "barcode" },
                  { "tipoPagamento": "PIX", "nome": "Pix instantâneo", "descricao": "Aprovação imediata", "icone": "qrcode" },
                  { "tipoPagamento": "BOLETO", "nome": "Boleto duplicado", "descricao": "Não deve aparecer" }
                ]
                """
            )
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let methods = try await service.fetchPaymentMethods()

        #expect(methods.map(\.method) == [.boleto, .pix])
        #expect(methods[0].title == "Boleto parcelado")
        #expect(methods[0].subtitle == "Compensação em até 3 dias")
        #expect(methods[0].iconSystemName == "barcode")
        #expect(methods[1].title == "Pix instantâneo")
        #expect(methods[1].iconSystemName == "qrcode")
    }

    @Test("PortalActionsService abre o contrato pela rota /api/contratos/{id}/documento.pdf")
    func downloadContractDocumentUsesExpectedPDFRoute() async throws {
        let expectedData = Data("%PDF-1.4 fake".utf8)

        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/contratos/ctr-123/documento.pdf")
            #expect(request.httpMethod == "GET")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/pdf"]
            )!
            return (response, expectedData)
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let fileURL = try await service.downloadContractDocument(contractID: "ctr-123")
        let storedData = try Data(contentsOf: fileURL)

        #expect(storedData == expectedData)
        #expect(fileURL.pathExtension == "pdf")
    }

    @Test("PortalActionsService lê o detalhe real da dívida pela rota /api/dividas/{id}")
    func fetchDebtDetailUsesExpectedRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/dividas/div-123")
            #expect(request.httpMethod == "GET")

            return jsonResponse(
                url: url,
                json: """
                {
                  "id": "div-123",
                  "descricao": "Cobrança teste",
                  "valorPrincipal": 500.00,
                  "status": "NAO_PAGO",
                  "dataVencimento": "2026-04-20T10:00:00Z",
                  "credorCriador": {
                    "id": "cred-1",
                    "nome": "BillEasy Credora",
                    "cnpj": "12.345.678/0001-90"
                  },
                  "devedor": {
                    "id": "dev-1",
                    "cpfCnpjEnc": "123.456.789-00"
                  },
                  "contrato": {
                    "id": "ctr-123",
                    "titulo": "Contrato de Cobrança",
                    "descricao": "Descrição remota"
                  },
                  "totais": {
                    "totalDevidoBruto": 560.00,
                    "diasEmAtraso": 5,
                    "emAtraso": true
                  },
                  "numeroParcela": 2,
                  "totalParcelas": 6
                }
                """
            )
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let detail = try await service.fetchDebtDetail(debtID: "div-123")

        #expect(detail.debtID == "div-123")
        #expect(detail.contractID == "ctr-123")
        #expect(detail.updatedAmount == Decimal(string: "560.00"))
        #expect(detail.overdueDays == 5)
        #expect(detail.debtorDocument == "123.456.789-00")
        #expect(detail.installmentNumber == 2)
        #expect(detail.installmentTotal == 6)
        #expect(detail.installmentSummary == "Parcela 2 de 6")
    }

    @Test("PortalActionsService uses PUT /usuarios/{id}/senha with the expected payload")
    func updatePasswordUsesExpectedRouteAndPayload() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/usuarios/usr-123/senha")
            #expect(request.httpMethod == "PUT")

            let body = try bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
            #expect(json?["senhaAtual"] == "SenhaAtual#1")
            #expect(json?["senhaNova"] == "NovaSenha#2")

            let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        try await service.updatePassword(
            userID: "usr-123",
            currentPassword: "SenhaAtual#1",
            newPassword: "NovaSenha#2"
        )
    }

    @Test("PortalActionsService resolves the first payable installment before creating payment")
    func createPaymentUsesFirstOpenInstallmentWhenDebtListHasNoInstallmentID() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/dividas/div-1/parcelas" {
                return jsonResponse(
                    url: url,
                    json: """
                    [
                      {
                        "id": "parc-1",
                        "numeroParcela": 1,
                        "status": "PAGA"
                      },
                      {
                        "id": "parc-2",
                        "numeroParcela": 2,
                        "status": "EM_ABERTO"
                      }
                    ]
                    """
                )
            }

            if url.path == "/api/dividas/div-1/parcelas/parc-2/pagamentos" {
                #expect(request.httpMethod == "POST")
                let body = try bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
                #expect(json?["metodo"] == "PIX")
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "pay-1",
                      "metodo": "PIX",
                      "status": "PENDENTE",
                      "qrCodePix": "pix-code-123"
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let receipt = try await service.createPayment(
            debtID: "div-1",
            preferredInstallmentID: nil,
            method: .pix
        )

        #expect(receipt.paymentID == "pay-1")
        #expect(receipt.method == .pix)
        #expect(receipt.pixQRCode == "pix-code-123")
    }

    @Test("PortalActionsService envia o enum de cartão alinhado ao backend atual")
    func createPaymentUsesCurrentCreditCardEnum() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/dividas/div-2/parcelas/parc-9/pagamentos" {
                let body = try bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
                #expect(json?["metodo"] == "CARTAO_DE_CREDITO")
                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "id": "pay-2",
                      "metodo": "CARTAO_DE_CREDITO",
                      "status": "PENDENTE"
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let receipt = try await service.createPayment(
            debtID: "div-2",
            preferredInstallmentID: "parc-9",
            method: .creditCard
        )

        #expect(receipt.paymentID == "pay-2")
        #expect(receipt.method == .creditCard)
    }

    @Test("PortalActionsService cria contrato manual com o mesmo payload estrutural do web atual")
    func createManualContractUsesCurrentBackendPayload() async throws {
        let dueDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 15))!

        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/contratos")
            #expect(request.httpMethod == "POST")

            let body = try bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(json?["titulo"] as? String == "Prestação de Serviços - Website Institucional")
            #expect(json?["assunto"] as? String == "Website Institucional")
            #expect(json?["tipoNegocio"] as? String == "PRESTACAO_SERVICOS")
            #expect(json?["frequenciaPagamento"] as? String == "PARCELADO")
            #expect(json?["quantidadeParcelas"] as? Int == 3)
            #expect((json?["meiosPagamentoAceitos"] as? [String])?.sorted() == ["BOLETO", "PIX"])

            let creditor = json?["credorCriador"] as? [String: Any]
            #expect(creditor?["id"] as? String == "emp-1")

            let debtor = json?["novoDevedor"] as? [String: Any]
            #expect(debtor?["nome"] as? String == "Cliente Teste")
            #expect(debtor?["cpfCnpjEnc"] as? String == "06427166174")
            #expect(debtor?["telefone"] as? String == "61993011072")

            let address = debtor?["endereco"] as? [String: Any]
            #expect(address?["cep"] as? String == "01310100")
            #expect(address?["numero"] as? String == "1578")
            #expect(address?["complemento"] as? String == "Sala 12")

            return jsonResponse(
                url: url,
                json: """
                {
                  "id": "ctr-manual-1",
                  "titulo": "Prestação de Serviços - Website Institucional",
                  "assunto": "Website Institucional",
                  "status": "RASCUNHO",
                  "descricaoDetalhada": "Contrato remoto criado pelo endpoint manual.",
                  "assinadoPorCredor": false,
                  "assinadoPorDevedor": false
                }
                """
            )
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let detail = try await service.createManualContract(
            input: AIContractConfirmationInput(
                title: "Prestação de Serviços - Website Institucional",
                subject: "Website Institucional",
                description: "Contrato para desenvolvimento do website institucional.",
                totalValueText: "R$ 4.500,00",
                dueDate: dueDate,
                installmentCount: 3,
                businessType: "PRESTACAO_SERVICOS",
                paymentFrequency: "PARCELADO",
                paymentMethods: [.pix, .boleto],
                creditorName: "BillEasy Credora",
                creditorDocument: "12.345.678/0001-90",
                creditorEmail: "credora@billeasy.ai",
                creditorPhone: "(11) 98888-0000",
                creditorPersonType: "PESSOA_JURIDICA",
                creditorPixKey: "12.345.678/0001-90",
                creditorPixKeyType: "CPF_CNPJ",
                creditorCEP: "01310-100",
                creditorAddressNumber: "123",
                creditorAddressComplement: nil,
                creditorAddress: "Rua Um, 123",
                debtorName: "Cliente Teste",
                debtorDocument: "064.271.661-74",
                debtorEmail: "cliente@teste.com",
                debtorPhone: "(61) 99301-1072",
                debtorCEP: "01310-100",
                debtorAddressNumber: "1578",
                debtorAddressComplement: "Sala 12",
                debtorAddress: "Avenida Paulista, Bela Vista, São Paulo, São Paulo • Número: 1578 • Complemento: Sala 12"
            ),
            companyID: "emp-1"
        )

        #expect(detail.contractID == "ctr-manual-1")
        #expect(detail.title == "Website Institucional")
    }

    @Test("PortalActionsService consulta preview de CEP pela rota atual do backend")
    func fetchAddressPreviewUsesCurrentCEPEndpoint() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/enderecos/cep/01310100")
            #expect(request.httpMethod == "GET")

            return jsonResponse(
                url: url,
                json: """
                {
                  "cep": "01310-100",
                  "logradouro": "Avenida Paulista",
                  "bairro": "Bela Vista",
                  "cidade": "São Paulo",
                  "estado": "São Paulo"
                }
                """
            )
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let preview = try await service.fetchAddressPreview(cep: "01310-100")
        #expect(preview.cep == "01310-100")
        #expect(preview.formattedLine == "Avenida Paulista, Bela Vista, São Paulo, São Paulo")
    }

    @Test("PortalActionsService maps remote contract detail for the modals")
    func fetchContractDetailReturnsDetailedTextAndFlags() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/contratos/ctr-9")
            return jsonResponse(
                url: url,
                json: """
                {
                  "id": "ctr-9",
                  "titulo": "Contrato Notebook",
                  "assunto": "Notebook Dell",
                  "status": "AGUARDANDO_ASSINATURA_DEVEDOR",
                  "descricaoDetalhada": "Texto detalhado vindo do backend.",
                  "assinadoPorCredor": true,
                  "assinadoPorDevedor": false
                }
                """
            )
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let detail = try await service.fetchContractDetail(contractID: "ctr-9")

        #expect(detail.contractID == "ctr-9")
        #expect(detail.title == "Notebook Dell")
        #expect(detail.status == "AGUARDANDO_ASSINATURA_DEVEDOR")
        #expect(detail.contractText == "Texto detalhado vindo do backend.")
        #expect(detail.creditorSigned == true)
        #expect(detail.debtorSigned == false)
    }

    @Test("PortalActionsService uploads profile photo to the user attachments route")
    func uploadUserProfilePhotoUsesUserAttachmentEndpoint() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])

        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/usuarios/usr-123/anexos")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)

            let body = try bodyData(from: request)
            let bodyText = String(decoding: body, as: UTF8.self)
            #expect(bodyText.contains("name=\"arquivo\""))
            #expect(bodyText.contains("filename=\"perfil.jpg\""))

            return jsonResponse(
                url: url,
                json: """
                {
                  "id": "att-1",
                  "nomeArquivo": "perfil.jpg",
                  "urlDownload": "/api/anexos/att-1/download",
                  "criadoEm": "2026-03-17T12:00:00Z"
                }
                """
            )
        }

        let service = PortalActionsService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let attachment = try await service.uploadUserProfilePhoto(
            userID: "usr-123",
            imageData: imageData,
            filename: "perfil.jpg",
            mimeType: "image/jpeg"
        )

        #expect(attachment.id == "att-1")
        #expect(attachment.fileName == "perfil.jpg")
        #expect(attachment.downloadPath == "/api/anexos/att-1/download")
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        PortalActionsMockURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortalActionsMockURLProtocol.self]
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

private final class PortalActionsMockURLProtocol: URLProtocol, @unchecked Sendable {
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
