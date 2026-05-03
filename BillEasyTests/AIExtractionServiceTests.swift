import Foundation
import Testing
@testable import BillEasy

struct AIExtractionServiceTests {

    @Test("AIExtractionService mantém a rota auxiliar de classificação disponível quando chamada explicitamente")
    func classifyContractTextUsesBackendClassificationRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/contratos/classificar")
            #expect(request.httpMethod == "POST")

            let body = try bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
            #expect(json?["texto"] == "Contrato de prestação de serviços de desenvolvimento.")

            return jsonResponse(
                url: url,
                json: """
                {
                  "sucesso": true,
                  "dados": {
                    "dominioContrato": "PRESTACAO_SERVICOS"
                  }
                }
                """
            )
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let result = try await service.classifyContractText(
            "Contrato de prestação de serviços de desenvolvimento."
        )

        #expect(result == "PRESTACAO_SERVICOS")
    }

    @Test("AIExtractionService uses /api/contratos/fluxo-ia com o mesmo contrato semântico do web atual")
    func createContractViaFlowUsesNewBackendContractRoute() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/contratos/fluxo-ia" {
                #expect(request.httpMethod == "POST")

                let body = try bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                #expect(json?["empresaId"] as? String == "emp-123")
                #expect(json?["assunto"] as? String == "Venda de Equipamento")
                #expect(json?["tipoNegocio"] as? String == "OUTRO_ACORDO_GERAL")
                #expect(json?["frequenciaPagamento"] as? String == "UNICO_A_VISTA")
                #expect(json?["descricaoAcordo"] as? String == "Venda parcelada de equipamento industrial.")
                #expect(json?["credorTipoPessoa"] as? String == "PESSOA_JURIDICA")
                #expect(json?["credorChavePix"] as? String == "12345678000190")
                #expect(json?["credorTipoChavePix"] as? String == "CPF_CNPJ")
                #expect(json?["credorCep"] as? String == "01310100")
                #expect(json?["credorNumero"] as? String == "123")
                #expect(json?["credorComplemento"] as? String == "Conjunto 7")
                #expect(json?["devedorCpfCnpj"] as? String == "06427166174")
                #expect(json?["devedorTelefone"] as? String == "61993011072")
                #expect(json?["devedorCep"] as? String == "01310100")
                #expect(json?["devedorNumero"] as? String == "1578")
                #expect(json?["devedorComplemento"] as? String == "Sala 12")
                #expect(json?["dataPrimeiroVencimento"] as? String == "2026-04-10")
                let numeroParcelas = json?["numeroParcelas"]
                #expect(numeroParcelas == nil || numeroParcelas is NSNull)
                #expect((json?["meiosPagamentoAceitos"] as? [String])?.sorted() == ["BOLETO", "PIX"])

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let data = Data(
                    """
                    {
                      "sucesso": true,
                      "contratoId": "ctr-123",
                      "statusFluxo": "CONTRATO_CRIADO",
                      "dadosFaltantes": [],
                      "devedorCriado": true,
                      "devedorId": "dev-123"
                    }
                    """.utf8
                )
                return (response, data)
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let dueDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let result = try await service.createContractViaFlow(
            AIContractConfirmationInput(
                title: "Outro / Acordo Geral - Venda de Equipamento",
                subject: "Venda de Equipamento",
                description: "Venda parcelada de equipamento industrial.",
                totalValueText: "R$ 2.500,00",
                dueDate: dueDate,
                installmentCount: nil,
                businessType: "OUTRO_ACORDO_GERAL",
                paymentFrequency: "UNICO_A_VISTA",
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
                creditorAddressComplement: "Conjunto 7",
                creditorAddress: "Rua Um, 123",
                debtorName: "Samuel Jammes",
                debtorDocument: "064.271.661-74",
                debtorEmail: "s.jammes3@gmail.com",
                debtorPhone: "(61) 99301-1072",
                debtorCEP: "01310-100",
                debtorAddressNumber: "1578",
                debtorAddressComplement: "Sala 12",
                debtorAddress: "Brasília - DF"
            ),
            session: AuthSession(
                userID: "usr-1",
                displayName: "Samuel Jammes",
                email: "s.jammes3@gmail.com",
                provider: .email,
                empresaID: "emp-123",
                phone: nil,
                roles: ["USUARIO"],
                hasDebtorProfile: false
            )
        )

        #expect(result.contractID == "ctr-123")
        #expect(result.debtorID == "dev-123")
    }

    @Test("AIExtractionService preserva parcela unica explicita quando ela veio da extração")
    func createContractViaFlowPreservesExplicitSingleInstallmentWhenProvided() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/contratos/fluxo-ia" {
                let body = try bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                #expect(json?["frequenciaPagamento"] as? String == "UNICO_A_VISTA")
                #expect(json?["numeroParcelas"] as? Int == 1)

                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "sucesso": true,
                      "contratoId": "ctr-125",
                      "statusFluxo": "CONTRATO_CRIADO",
                      "dadosFaltantes": [],
                      "devedorCriado": false,
                      "devedorId": "dev-125"
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let dueDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let result = try await service.createContractViaFlow(
            AIContractConfirmationInput(
                title: "Contrato à vista",
                subject: "Contrato à vista",
                description: "Contrato com parcela unica extraida do documento.",
                totalValueText: "R$ 1.250,00",
                dueDate: dueDate,
                installmentCount: 1,
                businessType: "OUTRO_ACORDO_GERAL",
                paymentFrequency: "UNICO_A_VISTA",
                paymentMethods: [.pix],
                creditorName: "BillEasy Credora",
                creditorDocument: "12.345.678/0001-90",
                creditorEmail: "credora@billeasy.ai",
                creditorPhone: "(11) 98888-0000",
                creditorPersonType: "PESSOA_JURIDICA",
                creditorPixKey: "12.345.678/0001-90",
                creditorPixKeyType: "CPF_CNPJ",
                creditorCEP: "01310-100",
                creditorAddressNumber: "123",
                creditorAddressComplement: "Conjunto 7",
                creditorAddress: "Rua Um, 123",
                debtorName: "Samuel Jammes",
                debtorDocument: "064.271.661-74",
                debtorEmail: "s.jammes3@gmail.com",
                debtorPhone: "(61) 99301-1072",
                debtorCEP: "01310-100",
                debtorAddressNumber: "1578",
                debtorAddressComplement: "Sala 12",
                debtorAddress: "Brasília - DF"
            ),
            session: AuthSession(
                userID: "usr-1",
                displayName: "Samuel Jammes",
                email: "s.jammes3@gmail.com",
                provider: .email,
                empresaID: "emp-123",
                phone: nil,
                roles: ["USUARIO"],
                hasDebtorProfile: false
            )
        )

        #expect(result.contractID == "ctr-125")
        #expect(result.debtorID == "dev-125")
    }

    @Test("AIExtractionService não força parcela única quando a frequência não é à vista")
    func createContractViaFlowDoesNotForceSingleInstallmentForInstallmentFrequency() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/contratos/fluxo-ia" {
                let body = try bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                #expect(json?["frequenciaPagamento"] as? String == "PARCELADO")
                #expect(json?["numeroParcelas"] as? Int == 4)
                #expect(json?["credorTipoPessoa"] as? String == "PESSOA_JURIDICA")
                #expect(json?["credorTipoChavePix"] as? String == "EMAIL")

                return jsonResponse(
                    url: url,
                    json: """
                    {
                      "sucesso": true,
                      "contratoId": "ctr-124",
                      "statusFluxo": "CONTRATO_CRIADO",
                      "dadosFaltantes": [],
                      "devedorCriado": false,
                      "devedorId": "dev-124"
                    }
                    """
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let dueDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let result = try await service.createContractViaFlow(
            AIContractConfirmationInput(
                title: "Acordo de Pagamento - Contrato Parcelado",
                subject: "Contrato Parcelado",
                description: "Contrato parcelado em várias parcelas.",
                totalValueText: "R$ 9.900,00",
                dueDate: dueDate,
                installmentCount: 4,
                businessType: "ACORDO_PAGAMENTO",
                paymentFrequency: "PARCELADO",
                paymentMethods: [.pix],
                creditorName: "BillEasy Credora",
                creditorDocument: "12.345.678/0001-90",
                creditorEmail: "credora@billeasy.ai",
                creditorPhone: "(11) 98888-0000",
                creditorPersonType: "PESSOA_JURIDICA",
                creditorPixKey: "credora@billeasy.ai",
                creditorPixKeyType: "EMAIL",
                creditorCEP: "01310-100",
                creditorAddressNumber: "123",
                creditorAddressComplement: nil,
                creditorAddress: "Rua Um, 123",
                debtorName: "Cliente Parcelado",
                debtorDocument: "123.456.789-00",
                debtorEmail: "cliente@exemplo.com",
                debtorPhone: "(61) 98888-1111",
                debtorCEP: "70040-010",
                debtorAddressNumber: "100",
                debtorAddressComplement: nil,
                debtorAddress: "Brasília - DF"
            ),
            session: AuthSession(
                userID: "usr-1",
                displayName: "Samuel Jammes",
                email: "s.jammes3@gmail.com",
                provider: .email,
                empresaID: "emp-123",
                phone: nil,
                roles: ["USUARIO"],
                hasDebtorProfile: false
            )
        )

        #expect(result.contractID == "ctr-124")
        #expect(result.debtorID == "dev-124")
    }

    @Test("AIExtractionService uses web audio proxy routes and waits for the async transcription job")
    func audioTranscriptionUsesWebProxyRoutes() async throws {
        let pollState = AudioJobPollState()
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/ia/audio/transcribe" {
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let data = Data(
                    """
                    {
                      "sucesso": true,
                      "dados": {
                        "jobId": "job-123",
                        "status": "processing"
                      }
                    }
                    """.utf8
                )
                return (response, data)
            }

            if url.path == "/api/ia/audio/job/job-123" {
                pollState.pollCount += 1
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!

                if pollState.pollCount == 1 {
                    return (
                        response,
                        Data(#"{"sucesso":true,"dados":{"jobId":"job-123","status":"processing"}}"#.utf8)
                    )
                }

                return (
                    response,
                    Data(
                        """
                        {
                          "sucesso": true,
                          "dados": {
                            "jobId": "job-123",
                            "status": "done",
                            "texto": "Prestação de serviço para site institucional",
                            "confidence": 0.97,
                            "audioDuration": 11.5,
                            "language": "pt"
                          }
                        }
                        """.utf8
                    )
                )
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let jobID = try await service.submitAudioForTranscription(
            audioData: Data("fake-audio".utf8),
            filename: "audio.m4a",
            mimeType: "audio/m4a"
        )
        #expect(jobID == "job-123")

        let transcription = try await service.waitForAudioTranscription(
            jobID: jobID,
            pollIntervalNanoseconds: 1_000_000,
            timeoutNanoseconds: 5_000_000_000
        )

        #expect(transcription.text == "Prestação de serviço para site institucional")
        #expect(transcription.language == "pt")
        #expect(transcription.confidence == 0.97)
    }

    @Test("AIExtractionService renova a sessão e repete a transcrição de áudio após um 401 do backend")
    func audioTranscriptionRefreshesSessionAfterUnauthorized() async throws {
        let state = AudioRefreshState()
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/api/ia/audio/transcribe" {
                state.audioSubmitCount += 1

                if state.audioSubmitCount == 1 {
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    let data = Data(#"{"status":401,"message":"Sessão expirada"}"#.utf8)
                    return (response, data)
                }

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let data = Data(
                    """
                    {
                      "sucesso": true,
                      "dados": {
                        "jobId": "job-401",
                        "status": "processing"
                      }
                    }
                    """.utf8
                )
                return (response, data)
            }

            if url.path == "/auth/refresh" {
                state.refreshCount += 1
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data())
            }

            if url.path == "/api/ia/audio/job/job-401" {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let data = Data(
                    """
                    {
                      "sucesso": true,
                      "dados": {
                        "jobId": "job-401",
                        "status": "done",
                        "texto": "Contrato de aluguel residencial",
                        "confidence": 0.99,
                        "audioDuration": 8.4,
                        "language": "pt"
                      }
                    }
                    """.utf8
                )
                return (response, data)
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let jobID = try await service.submitAudioForTranscription(
            audioData: Data("fake-audio".utf8),
            filename: "audio.m4a",
            mimeType: "audio/m4a"
        )

        #expect(jobID == "job-401")
        #expect(state.audioSubmitCount == 2)
        #expect(state.refreshCount == 1)
    }

    @Test("AIExtractionService maps text extraction from the current web proxy to a richer contract draft")
    func textExtractionMapsCurrentWebProxyPayload() async throws {
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/api/ia/extrair-texto")
            let body = try bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect((json?["texto"] as? String)?.contains("website institucional") == true)

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                """
                {
                  "sucesso": true,
                  "dados": {
                    "dividas": [
                      {
                        "nomeDevedor": { "valor": "Tech Solutions Ltda", "confianca": 0.91 },
                        "cpfCnpj": { "valor": "12.345.678/0001-99", "confianca": 0.89 },
                        "email": { "valor": "financeiro@techsolutions.com", "confianca": 0.80 },
                        "telefone": { "valor": "(11) 98888-0000", "confianca": 0.79 },
                        "valorPrincipal": { "valor": "4500.00", "confianca": 0.94 },
                        "descricao": { "valor": "Contrato para desenvolvimento de website institucional responsivo.", "confianca": 0.96 },
                        "tipoDebito": { "valor": "Prestação de Serviço", "confianca": 0.87 },
                        "dataVencimento": { "valor": "2025-08-15", "confianca": 0.90 },
                        "nomeCredor": { "valor": "BillEasy Studio", "confianca": 0.73 }
                      }
                    ]
                  }
                }
                """.utf8
            )
            return (response, data)
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let draft = try await service.extractContractDraft(
            fromText: "Quero um contrato para website institucional com valor total de R$ 4.500,00."
        )

        #expect(draft.suggestedBusinessType == "Prestação de Serviços")
        #expect(draft.suggestedDescription.contains("website institucional"))
        #expect(draft.totalValueText == "4500.00")
        #expect(draft.creditorName == "BillEasy Studio")
        #expect(draft.debtorName == "Tech Solutions Ltda")
        #expect(draft.debtorDocument == "12.345.678/0001-99")
    }

    @Test("AIExtractionService uses /api/ia/extrair-de-imagem como fluxo principal de arquivo no padrão Kotlin/web atual")
    func imageExtractionUsesCurrentVisionRoute() async throws {
        let requestLog = LockedRequestLog()
        let session = makeMockSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            requestLog.append(url.path)

            if url.path == "/api/ia/extrair-de-imagem" {
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
                let body = try bodyData(from: request)
                let bodyString = String(decoding: body, as: UTF8.self)
                #expect(bodyString.contains("name=\"file\"; filename=\"contrato.pdf\""))

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let data = Data(
                    """
                    {
                      "sucesso": true,
                      "dados": {
                        "campos": {
                          "devedor_razao_social": { "valor": "Tech Solutions Ltda", "confianca": 0.91 },
                          "devedor_cnpj": { "valor": "12.345.678/0001-99", "confianca": 0.89 },
                          "devedor_email": { "valor": "financeiro@techsolutions.com", "confianca": 0.80 },
                          "devedor_telefone": { "valor": "(11) 98888-0000", "confianca": 0.79 },
                          "credor_nome": { "valor": "BillEasy Studio", "confianca": 0.98 },
                          "credor_cnpj": { "valor": "98.765.432/0001-11", "confianca": 0.97 },
                          "credor_telefone": { "valor": "(61) 99999-0000", "confianca": 0.82 },
                          "valor_total": { "valor": "4500.00", "confianca": 0.94 },
                          "numero_parcelas": { "valor": "6", "confianca": 0.88 },
                          "data_primeiro_vencimento": { "valor": "2026-05-10", "confianca": 0.90 },
                          "descricao_divida": { "valor": "Prestação de serviço de website institucional.", "confianca": 0.96 },
                          "tipo_documento": { "valor": "CONTRATO_PRESTACAO_SERVICOS", "confianca": 0.91 }
                        },
                        "textoExtraido": "Contrato de prestação de serviço com valor total de R$ 4.500,00 para Tech Solutions Ltda.",
                        "confiancaGeral": 0.93,
                        "paginasProcessadas": 2
                      }
                    }
                    """.utf8
                )
                return (response, data)
            }

            Issue.record("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }

        let service = AIExtractionService(
            apiClient: RemoteAPIClient(
                session: session,
                environment: APIEnvironment(backendBaseURL: URL(string: "https://api.example.com")!)
            ),
            mode: .remote
        )

        let draft = try await service.extractContractDraft(
            from: Data("fake-image".utf8),
            filename: "contrato.pdf",
            mimeType: "application/pdf"
        )

        #expect(requestLog.paths == ["/api/ia/extrair-de-imagem"])
        #expect(draft.suggestedBusinessType == "Prestação de Serviços")
        #expect(draft.suggestedSubject == "Contrato Prestacao Servicos")
        #expect(draft.creditorName == "BillEasy Studio")
        #expect(draft.creditorDocument == "98.765.432/0001-11")
        #expect(draft.creditorPhone == "(61) 99999-0000")
        #expect(draft.debtorName == "Tech Solutions Ltda")
        #expect(draft.debtorDocument == "12.345.678/0001-99")
        #expect(draft.debtorEmail == "financeiro@techsolutions.com")
        #expect(draft.debtorPhone == "(11) 98888-0000")
        #expect(draft.totalValueText == "4500.00")
        #expect(draft.installmentCount == 6)
        #expect(draft.dueDateText == "2026-05-10")
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        AIExtractionMockURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIExtractionMockURLProtocol.self]
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

private final class AudioJobPollState: @unchecked Sendable {
    var pollCount = 0
}

private final class AudioRefreshState: @unchecked Sendable {
    var audioSubmitCount = 0
    var refreshCount = 0
}

private final class LockedRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var paths: [String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class AIExtractionMockURLProtocol: URLProtocol, @unchecked Sendable {
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
