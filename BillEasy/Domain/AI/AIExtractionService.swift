//
//  AIExtractionService.swift
//  BillEasy
//

import Foundation

/// Aqui eu entrego para a UI um rascunho simples já traduzido do payload bruto da IA.
struct AIContractDraft {
    let suggestedBusinessType: String?
    let suggestedSubject: String?
    let suggestedDescription: String
    let totalValueText: String?
    let installmentCount: Int?
    let dueDateText: String?
    let creditorName: String?
    let creditorDocument: String?
    let creditorPhone: String?
    let debtorName: String?
    let debtorDocument: String?
    let debtorEmail: String?
    let debtorPhone: String?
}

/// Aqui eu entrego para a UI o resultado tipado do mesmo job de áudio usado pela versão web.
struct AIAudioTranscriptionResult {
    let text: String
    let confidence: Double?
    let audioDuration: Double?
    let language: String?
}

/// Aqui eu represento o formulário confirmado pelo usuário antes de sincronizar uma dívida remota.
struct AIContractConfirmationInput {
    let title: String
    let subject: String
    let description: String
    let totalValueText: String
    let dueDate: Date
    let installmentCount: Int?
    let businessType: String?
    let paymentFrequency: String?
    let paymentMethods: [AIContractPaymentMethodCode]
    let creditorName: String?
    let creditorDocument: String?
    let creditorEmail: String?
    let creditorPhone: String?
    let creditorPersonType: String?
    let creditorPixKey: String?
    let creditorPixKeyType: String?
    let creditorCEP: String?
    let creditorAddressNumber: String?
    let creditorAddressComplement: String?
    let creditorAddress: String?
    let debtorName: String
    let debtorDocument: String?
    let debtorEmail: String?
    let debtorPhone: String?
    let debtorCEP: String?
    let debtorAddressNumber: String?
    let debtorAddressComplement: String?
    let debtorAddress: String?
}

/// Aqui eu represento os meios de pagamento em um contrato que precisa conversar com o backend.
enum AIContractPaymentMethodCode: String, CaseIterable {
    case pix
    case boleto
    case card

    var backendType: String {
        switch self {
        case .pix:
            return "PIX"
        case .boleto:
            return "BOLETO"
        case .card:
            return "CARTAO_DE_CREDITO"
        }
    }

    var displayName: String {
        switch self {
        case .pix:
            return "PIX"
        case .boleto:
            return "Boleto"
        case .card:
            return "Cartão"
        }
    }
}

/// Aqui eu exponho o recorte útil da busca remota de devedores por empresa.
struct AICompanyDebtorResult {
    let id: String
    let name: String
    let email: String?
    let phone: String?
    let debtCount: Int
}

/// Aqui eu devolvo para a UI os IDs remotos gerados quando a dívida é confirmada no serviço de IA.
struct AIConfirmedDebtResult {
    let debtID: String
    let debtorID: String
}

/// Aqui eu devolvo os IDs úteis quando o backend conclui o fluxo moderno de contrato via IA.
struct AIConfirmedContractResult {
    let contractID: String
    let debtorID: String
}

/// Aqui eu deixo explícito quando a IA segura via backend ou as rotas privilegiadas ainda não podem ser usadas.
enum AIExtractionServiceError: LocalizedError {
    case integrationUnavailable
    case privilegedIntegrationUnavailable
    case missingCompanyContext
    case invalidImage
    case emptyExtraction
    case invalidOCR
    case missingRequiredFields([String])
    case remoteRejected(String)

    var errorDescription: String? {
        switch self {
        case .integrationUnavailable:
            return "A IA remota está disponível apenas no modo autenticado."
        case .privilegedIntegrationUnavailable:
            return "As rotas avançadas da IA precisam de um token service-to-service configurado fora do app."
        case .missingCompanyContext:
            return "A sessão atual não trouxe o empresaId necessário para esta ação."
        case .invalidImage:
            return "Não foi possível preparar a imagem selecionada."
        case .emptyExtraction:
            return "A IA não encontrou dados suficientes para continuar."
        case .invalidOCR:
            return "O OCR não retornou texto utilizável para extração."
        case let .missingRequiredFields(fields):
            let readableFields = fields.isEmpty ? "dados obrigatórios adicionais" : fields.joined(separator: ", ")
            return "O backend ainda precisa destes campos para concluir o contrato: \(readableFields)."
        case let .remoteRejected(message):
            return message
        }
    }
}

/// Aqui eu concentro os fluxos de OCR, extração e confirmação de dívida.
/// O app usa o proxy seguro do backend Java para OCR/extração e só toca o Node
/// diretamente nas rotas privilegiadas quando um token explícito é injetado no build.
final class AIExtractionService {
    private struct OCRProxyEnvelope: Decodable {
        let sucesso: Bool
        let dados: OCRProxyPayload?
        let erro: String?
    }

    private struct OCRProxyPayload: Decodable {
        let texto: String
        let confidence: Double?
    }

    private struct ImageExtractionEnvelope: Decodable {
        let sucesso: Bool
        let dados: ImageExtractionPayload?
        let erro: String?
    }

    private struct ImageExtractionPayload: Decodable {
        let campos: [String: ImageExtractionField]
        let textoExtraido: String?
        let confiancaGeral: Double?
        let paginasProcessadas: Int?
    }

    private struct ImageExtractionField: Decodable {
        let valor: String
        let confianca: Double?
    }

    private struct ExtractTextRequest: Encodable {
        let texto: String
        let contexto: String?
    }

    private struct ExtractTextEnvelope: Decodable {
        let sucesso: Bool
        let dados: ExtractTextPayload?
        let erro: String?
    }

    private struct AudioTranscriptionSubmitEnvelope: Decodable {
        let sucesso: Bool
        let dados: AudioTranscriptionSubmitPayload?
        let erro: String?
    }

    private struct AudioTranscriptionSubmitPayload: Decodable {
        let jobId: String?
        let status: String?
    }

    private struct AudioTranscriptionJobEnvelope: Decodable {
        let sucesso: Bool
        let dados: AudioTranscriptionJobPayload?
        let erro: String?
    }

    private struct AudioTranscriptionJobPayload: Decodable {
        let jobId: String?
        let status: String?
        let texto: String?
        let confidence: Double?
        let audioDuration: Double?
        let language: String?
    }

    private struct ExtractTextPayload: Decodable {
        let dividas: [ExtractedDebt]
        let observacoes: String?
    }

    private struct ClassificationRequest: Encodable {
        let texto: String
    }

    private struct ClassificationEnvelope: Decodable {
        let sucesso: Bool
        let dados: ClassificationPayload?
        let erro: String?
    }

    private struct ClassificationPayload: Decodable {
        let tipoDocumento: String?
        let tipoRelacao: String?
        let dominioContrato: String?
        let confianca: Double?
        let dadosFaltantes: [String]?
    }

    private struct ConfirmDebtRequest: Encodable {
        let divida: ConfirmableDebt
        let empresaId: String
        let usuarioId: String?
    }

    private struct ConfirmDebtEnvelope: Decodable {
        let sucesso: Bool
        let dados: ConfirmDebtPayload?
        let erro: String?
    }

    private struct ConfirmDebtPayload: Decodable {
        let dividaId: String
        let devedorId: String
    }

    private struct FlowContractRequest: Encodable {
        let empresaId: String
        let devedorId: String?
        let tipoNegocio: String
        let assunto: String
        let descricaoAcordo: String
        let frequenciaPagamento: String
        let dataPrimeiroVencimento: String
        let numeroParcelas: Int?
        let valorTotal: Decimal
        let meiosPagamentoAceitos: [String]
        let credorNome: String
        let credorCpfCnpj: String
        let credorTelefone: String
        let credorTipoPessoa: String
        let credorChavePix: String
        let credorTipoChavePix: String
        let credorCep: String
        let credorNumero: String
        let credorComplemento: String?
        let devedorNome: String
        let devedorCpfCnpj: String
        let devedorTelefone: String
        let devedorEmail: String
        let devedorCep: String
        let devedorNumero: String
        let devedorComplemento: String?
    }

    private struct FlowValidatedInput {
        let tipoNegocio: String
        let assunto: String
        let descricaoAcordo: String
        let frequenciaPagamento: String
        let dataPrimeiroVencimento: String
        let numeroParcelas: Int?
        let valorTotal: Decimal?
        let meiosPagamentoAceitos: [String]
        let credorNome: String
        let credorCpfCnpj: String
        let credorTelefone: String
        let credorTipoPessoa: String
        let credorChavePix: String
        let credorTipoChavePix: String
        let credorCep: String
        let credorNumero: String
        let credorComplemento: String?
        let devedorNome: String
        let devedorCpfCnpj: String
        let devedorTelefone: String
        let devedorEmail: String
        let devedorCep: String
        let devedorNumero: String
        let devedorComplemento: String?
    }

    private struct FlowContractEnvelope: Decodable {
        let sucesso: Bool
        let contratoId: String?
        let statusFluxo: String
        let dadosFaltantes: [String]?
        let devedorCriado: Bool
        let devedorId: String?
        let erro: String?
    }

    private struct BackendDebtorsPageEnvelope: Decodable {
        let content: [BackendDebtorPayload]
    }

    private struct BackendDebtorPayload: Decodable {
        let id: String
        let nome: String?
        let email: String?
        let telefone: String?
    }

    private struct BackendQuickDebtorRequest: Encodable {
        let nome: String
        let cpfCnpjEnc: String?
        let email: String?
        let telefone: String?
    }

    private struct BackendQuickDebtorResponse: Decodable {
        let id: String
    }

    private struct BackendQuickDebtRequest: Encodable {
        let descricao: String
        let valorPrincipal: Decimal
        let devedorId: String
        let empresaId: String
        let dataVencimento: String?
        let multaPercentual: Decimal?
        let jurosMensalPercentual: Decimal?
    }

    private struct BackendQuickDebtResponse: Decodable {
        let id: String
    }

    private struct RemoteDebtorsEnvelope: Decodable {
        let sucesso: Bool
        let dados: [RemoteDebtorPayload]
        let erro: String?
    }

    private struct RemoteDebtorPayload: Decodable {
        struct CounterPayload: Decodable {
            let dividas: Int
        }

        let id: String
        let nome: String
        let email: String?
        let telefone: String?
        let _count: CounterPayload?
    }

    private struct ConfirmableDebt: Encodable {
        let nomeDevedor: ConfirmableField
        let cpfCnpj: ConfirmableField?
        let email: ConfirmableField?
        let telefone: ConfirmableField?
        let valorPrincipal: ConfirmableField
        let descricao: ConfirmableField
        let tipoDebito: ConfirmableField?
        let dataVencimento: ConfirmableField?
    }

    private struct ConfirmableField: Encodable {
        let valor: String
        let confianca: Double
    }

    private struct ExtractedDebt: Decodable {
        let nomeDevedor: ExtractedField<String>
        let cpfCnpj: ExtractedField<String>?
        let email: ExtractedField<String>?
        let telefone: ExtractedField<String>?
        let valorPrincipal: ExtractedField<String>
        let descricao: ExtractedField<String>
        let tipoDebito: ExtractedField<String>?
        let dataVencimento: ExtractedField<String>?
        let nomeCredor: ExtractedField<String>?
    }

    private struct ExtractedField<Value: Decodable>: Decodable {
        let valor: Value
        let confianca: Double?
    }

    private let apiClient: RemoteAPIClient
    private let mode: AppAuthMode

    init(
        apiClient: RemoteAPIClient = RemoteAPIClient(),
        mode: AppAuthMode = AppRuntimeConfiguration.authMode
    ) {
        self.apiClient = apiClient
        self.mode = mode
    }

    /// Aqui eu deixo a UI saber se a IA segura via backend já pode ser usada.
    var isConfigured: Bool {
        mode == .remote && apiClient.currentEnvironment.hasAIProxyConfigured
    }

    /// Aqui eu separo as rotas privilegiadas, que só podem existir com base + token válidos.
    var hasPrivilegedRoutesConfigured: Bool {
        mode == .remote && apiClient.currentEnvironment.hasPrivilegedAIServiceConfigured
    }

    /// Aqui eu exponho se o app já tem o contexto mínimo para operar com dados remotos da empresa.
    func canUseCompanyScopedIntegration(with session: AuthSession) -> Bool {
        mode == .remote && session.empresaID?.nilIfEmpty != nil
    }

    /// Aqui eu ainda diferencio as rotas realmente privilegiadas do caminho seguro via backend.
    func canUsePrivilegedRoutes(with session: AuthSession) -> Bool {
        canUseCompanyScopedIntegration(with: session) && hasPrivilegedRoutesConfigured
    }

    /// Aqui eu sigo o fluxo novo do Kotlin/web: envio imagem ou PDF para `/api/ia/extrair-de-imagem`
    /// e recebo os campos estruturados já prontos para pré-preencher o formulário.
    func extractContractDraft(
        from imageData: Data,
        filename: String = "contract-upload.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> AIContractDraft {
        guard isConfigured else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        guard !imageData.isEmpty else {
            throw AIExtractionServiceError.invalidImage
        }

        let extractionResponse: ImageExtractionEnvelope = try await apiClient.upload(
            target: .backend,
            path: APIRoutes.AIProxy.extractFromImage,
            fileFieldName: "file",
            fileData: imageData,
            filename: filename,
            mimeType: mimeType,
            timeoutInterval: 120
        )

        guard extractionResponse.sucesso else {
            throw AIExtractionServiceError.remoteRejected(
                extractionResponse.erro ?? AIExtractionServiceError.invalidOCR.localizedDescription
            )
        }

        if let draft = makeDraft(from: extractionResponse) {
            return draft
        }

        guard let extractedText = extractionResponse.dados?.textoExtraido?.nilIfEmpty else {
            throw AIExtractionServiceError.invalidOCR
        }

        return fallbackDraft(from: extractedText)
    }

    /// Aqui eu exponho a extração textual para a IA digitada, para o OCR e para a revisão do áudio.
    func extractContractDraft(
        fromText text: String,
        context: String? = "Extraia dados de dívida e acordo a partir do texto para pré-preencher o formulário do app iOS."
    ) async throws -> AIContractDraft {
        guard isConfigured else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        guard let normalizedText = text.nilIfEmpty else {
            throw AIExtractionServiceError.emptyExtraction
        }

        let extractionResponse: ExtractTextEnvelope = try await apiClient.request(
            target: .backend,
            path: APIRoutes.AIProxy.extractFromText,
            method: "POST",
            body: ExtractTextRequest(
                texto: normalizedText,
                contexto: context
            )
        )

        if let draft = makeDraft(from: extractionResponse, fallbackText: normalizedText) {
            return draft
        }

        return fallbackDraft(from: normalizedText)
    }

    /// Aqui eu reaproveito a mesma rota de classificação do app Kotlin para enriquecer uploads de arquivo no iOS.
    func classifyContractText(_ text: String) async throws -> String? {
        guard mode == .remote else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        guard let normalizedText = text.nilIfEmpty else {
            throw AIExtractionServiceError.emptyExtraction
        }

        let response: ClassificationEnvelope = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Contratos.classificarIA,
            method: "POST",
            body: ClassificationRequest(texto: normalizedText)
        )

        guard response.sucesso else {
            throw AIExtractionServiceError.remoteRejected(
                response.erro ?? "Não consegui classificar o arquivo enviado."
            )
        }

        return response.dados?.dominioContrato?.nilIfEmpty
    }

    /// Aqui eu submeto áudio para o mesmo proxy web autenticado usado no frontend.
    func submitAudioForTranscription(
        audioData: Data,
        filename: String = "audio-recording.m4a",
        mimeType: String = "audio/m4a",
        language: String = "pt"
    ) async throws -> String {
        guard isConfigured else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        guard !audioData.isEmpty else {
            throw AIExtractionServiceError.invalidImage
        }

        let response: AudioTranscriptionSubmitEnvelope = try await apiClient.upload(
            target: .backend,
            path: APIRoutes.AIProxy.transcribeAudio,
            fileFieldName: "audio",
            fileData: audioData,
            filename: filename,
            mimeType: mimeType,
            additionalFormFields: ["language": language]
        )

        guard
            response.sucesso,
            let jobID = response.dados?.jobId?.nilIfEmpty
        else {
            throw AIExtractionServiceError.remoteRejected(
                response.erro ?? "A IA não aceitou o áudio enviado."
            )
        }

        return jobID
    }

    /// Aqui eu faço o polling assíncrono exatamente como a web faz para concluir a transcrição.
    func waitForAudioTranscription(
        jobID: String,
        pollIntervalNanoseconds: UInt64 = 2_000_000_000,
        timeoutNanoseconds: UInt64 = 120_000_000_000
    ) async throws -> AIAudioTranscriptionResult {
        guard isConfigured else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds

        while DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNanoseconds {
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)

            let response: AudioTranscriptionJobEnvelope = try await apiClient.request(
                target: .backend,
                path: APIRoutes.AIProxy.transcribeJob(jobID)
            )

            guard response.sucesso else {
                throw AIExtractionServiceError.remoteRejected(
                    response.erro ?? "Falha na transcrição do áudio."
                )
            }

            let status = response.dados?.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if status == "done" {
                guard let text = response.dados?.texto?.nilIfEmpty else {
                    throw AIExtractionServiceError.invalidOCR
                }

                return AIAudioTranscriptionResult(
                    text: text,
                    confidence: response.dados?.confidence,
                    audioDuration: response.dados?.audioDuration,
                    language: response.dados?.language
                )
            }

            if status == "failed" {
                throw AIExtractionServiceError.remoteRejected(
                    response.erro ?? "Falha na transcrição do áudio."
                )
            }
        }

        throw AIExtractionServiceError.remoteRejected("Tempo limite de transcrição excedido (120s).")
    }

    /// Aqui eu sincronizo uma dívida confirmada pelo usuário usando o `empresaId` da sessão remota.
    func confirmDebt(
        _ input: AIContractConfirmationInput,
        session: AuthSession
    ) async throws -> AIConfirmedDebtResult {
        guard mode == .remote else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        guard let empresaId = session.empresaID?.nilIfEmpty else {
            throw AIExtractionServiceError.missingCompanyContext
        }

        if !apiClient.currentEnvironment.hasPrivilegedAIServiceConfigured {
            return try await confirmDebtViaBackend(input, empresaId: empresaId)
        }

        let response: ConfirmDebtEnvelope = try await apiClient.request(
            target: .ai,
            path: APIRoutes.AIService.confirmExtract,
            method: "POST",
            body: ConfirmDebtRequest(
                divida: makeConfirmableDebt(from: input),
                empresaId: empresaId,
                usuarioId: session.userID.nilIfEmpty
            )
        )

        guard response.sucesso, let payload = response.dados else {
            throw AIExtractionServiceError.remoteRejected(
                response.erro ?? "A IA não confirmou a dívida remota."
            )
        }

        return AIConfirmedDebtResult(
            debtID: payload.dividaId,
            debtorID: payload.devedorId
        )
    }

    /// Aqui eu uso o fluxo novo do backend web para criar contrato e devedor de forma orquestrada.
    func createContractViaFlow(
        _ input: AIContractConfirmationInput,
        session: AuthSession
    ) async throws -> AIConfirmedContractResult {
        guard mode == .remote else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        guard let empresaId = session.empresaID?.nilIfEmpty else {
            throw AIExtractionServiceError.missingCompanyContext
        }

        let validatedInput = try validatedFlowInput(from: input)

        let response: FlowContractEnvelope = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Contratos.fluxoIA,
            method: "POST",
            body: FlowContractRequest(
                empresaId: empresaId,
                devedorId: nil,
                tipoNegocio: validatedInput.tipoNegocio,
                assunto: validatedInput.assunto,
                descricaoAcordo: validatedInput.descricaoAcordo,
                frequenciaPagamento: validatedInput.frequenciaPagamento,
                dataPrimeiroVencimento: validatedInput.dataPrimeiroVencimento,
                numeroParcelas: validatedInput.numeroParcelas,
                valorTotal: validatedInput.valorTotal ?? .zero,
                meiosPagamentoAceitos: validatedInput.meiosPagamentoAceitos,
                credorNome: validatedInput.credorNome,
                credorCpfCnpj: validatedInput.credorCpfCnpj,
                credorTelefone: validatedInput.credorTelefone,
                credorTipoPessoa: validatedInput.credorTipoPessoa,
                credorChavePix: validatedInput.credorChavePix,
                credorTipoChavePix: validatedInput.credorTipoChavePix,
                credorCep: validatedInput.credorCep,
                credorNumero: validatedInput.credorNumero,
                credorComplemento: validatedInput.credorComplemento,
                devedorNome: validatedInput.devedorNome,
                devedorCpfCnpj: validatedInput.devedorCpfCnpj,
                devedorTelefone: validatedInput.devedorTelefone,
                devedorEmail: validatedInput.devedorEmail,
                devedorCep: validatedInput.devedorCep,
                devedorNumero: validatedInput.devedorNumero,
                devedorComplemento: validatedInput.devedorComplemento
            )
        )

        switch response.statusFluxo.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "CONTRATO_CRIADO":
            guard
                let contractID = response.contratoId?.nilIfEmpty,
                let debtorID = response.devedorId?.nilIfEmpty
            else {
                throw AIExtractionServiceError.remoteRejected(
                    "O backend confirmou o fluxo, mas não devolveu os identificadores do contrato."
                )
            }

            return AIConfirmedContractResult(contractID: contractID, debtorID: debtorID)
        case "DADOS_FALTANTES":
            throw AIExtractionServiceError.missingRequiredFields(response.dadosFaltantes ?? [])
        default:
            throw AIExtractionServiceError.remoteRejected(
                response.erro ?? "O backend não conseguiu concluir o fluxo de contrato por IA."
            )
        }
    }

    /// Aqui eu valido o mínimo exigido pelo backend novo antes de enviar o fluxo-ia e devolvo uma lista legível de faltantes.
    private func validatedFlowInput(from input: AIContractConfirmationInput) throws -> FlowValidatedInput {
        var missingFields: [String] = []

        let tipoNegocio = input.businessType?.nilIfEmpty ?? "OUTRO_ACORDO_GERAL"
        let assunto = input.subject.nilIfEmpty ?? input.title
        let descricaoAcordo = input.description.nilIfEmpty ?? input.subject
        let frequenciaPagamento = input.paymentFrequency?.nilIfEmpty ?? "UNICO_A_VISTA"
        let dataPrimeiroVencimento = Self.webFlowDueDateString(from: input.dueDate)
        let numeroParcelas = resolvedInstallmentCount(for: input)
        let valorTotal = normalizedDecimal(from: input.totalValueText)
        let meiosPagamentoAceitos = normalizedPaymentMethods(from: input.paymentMethods) ?? []

        let credorNome = requiredFlowField(input.creditorName, label: "credorNome", missingFields: &missingFields)
        let credorCpfCnpj = requiredDocumentField(input.creditorDocument, label: "credorCpfCnpj", missingFields: &missingFields)
        let credorTelefone = requiredPhoneField(input.creditorPhone, label: "credorTelefone", missingFields: &missingFields)
        let credorTipoPessoa = requiredFlowField(input.creditorPersonType, label: "credorTipoPessoa", missingFields: &missingFields)
        let credorTipoChavePix = requiredFlowField(input.creditorPixKeyType, label: "credorTipoChavePix", missingFields: &missingFields)
        let credorChavePix = requiredPixKeyField(
            input.creditorPixKey,
            pixKeyType: credorTipoChavePix,
            label: "credorChavePix",
            missingFields: &missingFields
        )
        let credorCep = requiredDigitsField(input.creditorCEP, digits: 8, label: "credorCep", missingFields: &missingFields)
        let credorNumero = requiredFlowField(input.creditorAddressNumber, label: "credorNumero", missingFields: &missingFields)

        let devedorNome = requiredFlowField(input.debtorName, label: "devedorNome", missingFields: &missingFields)
        let devedorCpfCnpj = requiredDocumentField(input.debtorDocument, label: "devedorCpfCnpj", missingFields: &missingFields)
        let devedorTelefone = requiredPhoneField(input.debtorPhone, label: "devedorTelefone", missingFields: &missingFields)
        let devedorEmail = requiredFlowField(input.debtorEmail, label: "devedorEmail", missingFields: &missingFields)
        let devedorCep = requiredDigitsField(input.debtorCEP, digits: 8, label: "devedorCep", missingFields: &missingFields)
        let devedorNumero = requiredFlowField(input.debtorAddressNumber, label: "devedorNumero", missingFields: &missingFields)

        if valorTotal <= .zero {
            missingFields.append("valorTotal")
        }

        if meiosPagamentoAceitos.isEmpty {
            missingFields.append("meiosPagamentoAceitos")
        }

        if descricaoAcordo.count < 10 {
            missingFields.append("descricaoAcordo")
        }

        if missingFields.isEmpty == false {
            throw AIExtractionServiceError.missingRequiredFields(missingFields)
        }

        return FlowValidatedInput(
            tipoNegocio: tipoNegocio,
            assunto: assunto,
            descricaoAcordo: descricaoAcordo,
            frequenciaPagamento: frequenciaPagamento,
            dataPrimeiroVencimento: dataPrimeiroVencimento,
            numeroParcelas: numeroParcelas,
            valorTotal: valorTotal,
            meiosPagamentoAceitos: meiosPagamentoAceitos,
            credorNome: credorNome ?? "",
            credorCpfCnpj: credorCpfCnpj ?? "",
            credorTelefone: credorTelefone ?? "",
            credorTipoPessoa: credorTipoPessoa ?? "",
            credorChavePix: credorChavePix ?? "",
            credorTipoChavePix: credorTipoChavePix ?? "",
            credorCep: credorCep ?? "",
            credorNumero: credorNumero ?? "",
            credorComplemento: input.creditorAddressComplement?.nilIfEmpty,
            devedorNome: devedorNome ?? "",
            devedorCpfCnpj: devedorCpfCnpj ?? "",
            devedorTelefone: devedorTelefone ?? "",
            devedorEmail: devedorEmail ?? "",
            devedorCep: devedorCep ?? "",
            devedorNumero: devedorNumero ?? "",
            devedorComplemento: input.debtorAddressComplement?.nilIfEmpty
        )
    }

    /// Aqui eu busco devedores já ativos da empresa logada para aproveitar o cadastro remoto no app iOS.
    func searchDebtors(
        session: AuthSession,
        query: String,
        limit: Int = 20
    ) async throws -> [AICompanyDebtorResult] {
        guard mode == .remote else {
            throw AIExtractionServiceError.integrationUnavailable
        }

        guard let empresaId = session.empresaID?.nilIfEmpty else {
            throw AIExtractionServiceError.missingCompanyContext
        }

        if !apiClient.currentEnvironment.hasPrivilegedAIServiceConfigured {
            return try await searchDebtorsViaBackend(
                empresaId: empresaId,
                query: query,
                limit: limit
            )
        }

        let response: RemoteDebtorsEnvelope = try await apiClient.request(
            target: .ai,
            path: makeRemoteDebtorsPath(
                empresaId: empresaId,
                search: query.nilIfEmpty,
                limit: limit
            )
        )

        guard response.sucesso else {
            throw AIExtractionServiceError.remoteRejected(
                response.erro ?? "A IA não retornou os devedores da empresa."
            )
        }

        return response.dados.map { debtor in
            AICompanyDebtorResult(
                id: debtor.id,
                name: debtor.nome,
                email: debtor.email?.nilIfEmpty,
                phone: debtor.telefone?.nilIfEmpty,
                debtCount: debtor._count?.dividas ?? 0
            )
        }
    }

    /// Aqui eu reproduzo no backend Java o mesmo efeito do `extract/confirm`, sem colocar o token do Node dentro do app.
    private func confirmDebtViaBackend(
        _ input: AIContractConfirmationInput,
        empresaId: String
    ) async throws -> AIConfirmedDebtResult {
        let debtor: BackendQuickDebtorResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Empresas.devedoresIA(empresaId),
            method: "POST",
            body: BackendQuickDebtorRequest(
                nome: input.debtorName,
                cpfCnpjEnc: input.debtorDocument?.nilIfEmpty,
                email: input.debtorEmail?.nilIfEmpty,
                telefone: input.debtorPhone?.nilIfEmpty
            )
        )

        let normalizedAmount = normalizedDecimal(from: input.totalValueText)
        let debt: BackendQuickDebtResponse = try await apiClient.request(
            target: .backend,
            path: "\(APIRoutes.Dividas.base)/ia",
            method: "POST",
            body: BackendQuickDebtRequest(
                descricao: input.description.nilIfEmpty ?? input.subject,
                valorPrincipal: normalizedAmount,
                devedorId: debtor.id,
                empresaId: empresaId,
                dataVencimento: Self.apiDateFormatter.string(from: input.dueDate),
                multaPercentual: nil,
                jurosMensalPercentual: nil
            )
        )

        return AIConfirmedDebtResult(debtID: debt.id, debtorID: debtor.id)
    }

    /// Aqui eu consulto a base de devedores da própria empresa pelo backend autenticado, sem depender do serviço Node.
    private func searchDebtorsViaBackend(
        empresaId: String,
        query: String,
        limit: Int
    ) async throws -> [AICompanyDebtorResult] {
        var components = URLComponents()
        components.path = APIRoutes.Empresas.devedores(empresaId)
        components.queryItems = [
            URLQueryItem(name: "nome", value: query),
            URLQueryItem(name: "size", value: String(limit))
        ]

        let response: BackendDebtorsPageEnvelope = try await apiClient.request(
            target: .backend,
            path: components.string ?? APIRoutes.Empresas.devedores(empresaId)
        )

        return response.content.map { debtor in
            AICompanyDebtorResult(
                id: debtor.id,
                name: debtor.nome?.nilIfEmpty ?? "Devedor sem nome",
                email: debtor.email?.nilIfEmpty,
                phone: debtor.telefone?.nilIfEmpty,
                debtCount: 0
            )
        }
    }

    /// Aqui eu transformo a extração de texto no mesmo rascunho simples consumido pela tela de contrato.
    private func makeDraft(from response: ExtractTextEnvelope, fallbackText: String) -> AIContractDraft? {
        guard
            response.sucesso,
            let debt = response.dados?.dividas.first
        else {
            return nil
        }

        return AIContractDraft(
            suggestedBusinessType: inferBusinessType(from: debt.tipoDebito?.valor.nilIfEmpty ?? fallbackText),
            suggestedSubject: inferSubject(from: debt.descricao.valor.nilIfEmpty ?? fallbackText),
            suggestedDescription: debt.descricao.valor.nilIfEmpty ?? fallbackText,
            totalValueText: debt.valorPrincipal.valor.nilIfEmpty,
            installmentCount: nil,
            dueDateText: debt.dataVencimento?.valor.nilIfEmpty,
            creditorName: debt.nomeCredor?.valor.nilIfEmpty,
            creditorDocument: nil,
            creditorPhone: nil,
            debtorName: debt.nomeDevedor.valor.nilIfEmpty,
            debtorDocument: debt.cpfCnpj?.valor.nilIfEmpty,
            debtorEmail: debt.email?.valor.nilIfEmpty,
            debtorPhone: debt.telefone?.valor.nilIfEmpty
        )
    }

    /// Aqui eu mapeio a resposta estruturada de imagem/PDF exatamente como o web novo pré-preenche o formulário.
    private func makeDraft(from response: ImageExtractionEnvelope) -> AIContractDraft? {
        guard
            response.sucesso,
            let data = response.dados
        else {
            return nil
        }

        let fields = data.campos
        let fallbackText = data.textoExtraido?.nilIfEmpty

        let documentType = firstImageFieldValue(
            fields,
            keys: ["tipo_documento"]
        )
        let description = firstImageFieldValue(
            fields,
            keys: ["descricao_divida"]
        ) ?? fallbackText

        let debtorName = firstImageFieldValue(
            fields,
            keys: ["devedor_nome", "devedor_razao_social"]
        )
        let debtorDocument = firstImageFieldValue(
            fields,
            keys: ["devedor_cpf", "devedor_cnpj"]
        )
        let creditorName = firstImageFieldValue(
            fields,
            keys: ["credor_nome", "credor_razao_social"]
        )
        let creditorDocument = firstImageFieldValue(
            fields,
            keys: ["credor_cpf", "credor_cnpj"]
        )

        let suggestedDescription = description ?? fallbackText
        let suggestedBusinessType = businessType(fromDocumentType: documentType) ?? inferBusinessType(from: description ?? fallbackText)
        let suggestedSubject = subject(fromDocumentType: documentType) ?? inferSubject(from: description ?? fallbackText)
        let installmentCount = firstImageFieldValue(fields, keys: ["numero_parcelas"]).flatMap(parseInstallmentCount)

        guard
            suggestedDescription?.nilIfEmpty != nil ||
            debtorName?.nilIfEmpty != nil ||
            creditorName?.nilIfEmpty != nil ||
            firstImageFieldValue(fields, keys: ["valor_total"])?.nilIfEmpty != nil
        else {
            return nil
        }

        return AIContractDraft(
            suggestedBusinessType: suggestedBusinessType,
            suggestedSubject: suggestedSubject,
            suggestedDescription: suggestedDescription ?? "Documento analisado pela IA.",
            totalValueText: firstImageFieldValue(fields, keys: ["valor_total"]),
            installmentCount: installmentCount,
            dueDateText: firstImageFieldValue(fields, keys: ["data_primeiro_vencimento", "data_acordo"]),
            creditorName: creditorName,
            creditorDocument: creditorDocument,
            creditorPhone: firstImageFieldValue(fields, keys: ["credor_telefone"]),
            debtorName: debtorName,
            debtorDocument: debtorDocument,
            debtorEmail: firstImageFieldValue(fields, keys: ["devedor_email"]),
            debtorPhone: firstImageFieldValue(fields, keys: ["devedor_telefone"])
        )
    }

    /// Aqui eu ainda aproveito o texto puro do OCR quando a extração estruturada vier pobre.
    private func fallbackDraft(from extractedText: String) -> AIContractDraft {
        AIContractDraft(
            suggestedBusinessType: inferBusinessType(from: extractedText),
            suggestedSubject: inferSubject(from: extractedText),
            suggestedDescription: extractedText,
            totalValueText: nil,
            installmentCount: nil,
            dueDateText: nil,
            creditorName: nil,
            creditorDocument: nil,
            creditorPhone: nil,
            debtorName: nil,
            debtorDocument: nil,
            debtorEmail: nil,
            debtorPhone: nil
        )
    }

    /// Aqui eu monto o payload esperado pelo Node a partir do formulário já revisado pelo usuário.
    private func makeConfirmableDebt(from input: AIContractConfirmationInput) -> ConfirmableDebt {
        ConfirmableDebt(
            nomeDevedor: ConfirmableField(valor: input.debtorName, confianca: 1),
            cpfCnpj: input.debtorDocument?.nilIfEmpty.map { ConfirmableField(valor: $0, confianca: 1) },
            email: input.debtorEmail?.nilIfEmpty.map { ConfirmableField(valor: $0, confianca: 1) },
            telefone: input.debtorPhone?.nilIfEmpty.map { ConfirmableField(valor: $0, confianca: 1) },
            valorPrincipal: ConfirmableField(valor: input.totalValueText, confianca: 1),
            descricao: ConfirmableField(valor: input.description.nilIfEmpty ?? input.subject, confianca: 1),
            tipoDebito: input.subject.nilIfEmpty.map { ConfirmableField(valor: $0, confianca: 0.95) },
            dataVencimento: ConfirmableField(
                valor: Self.apiDateFormatter.string(from: input.dueDate),
                confianca: 1
            )
        )
    }

    /// Aqui eu transformo o formulário do iOS em texto rico para a nova orquestração do backend.
    private func makeFlowText(from input: AIContractConfirmationInput) -> String {
        var sections: [String] = []

        if let businessType = input.businessType?.nilIfEmpty {
            sections.append("Tipo do negócio: \(humanReadableBusinessType(from: businessType))")
        }

        sections.append("Assunto: \(input.subject)")
        sections.append("Descrição do acordo: \(input.description.nilIfEmpty ?? input.subject)")

        if let paymentFrequency = input.paymentFrequency?.nilIfEmpty {
            sections.append("Frequência: \(humanReadableFrequency(from: paymentFrequency))")
        }
        if let installmentCount = input.installmentCount, installmentCount > 1 {
            sections.append("Parcelas: \(installmentCount)")
        }

        if !input.paymentMethods.isEmpty {
            let methods = input.paymentMethods.map(\.displayName).joined(separator: ", ")
            sections.append("Meios de pagamento aceitos: \(methods)")
        }

        sections.append("Valor total: \(input.totalValueText)")
        sections.append("Primeiro vencimento: \(Self.apiDateFormatter.string(from: input.dueDate))")

        if let creditorName = input.creditorName?.nilIfEmpty {
            var creditorSummary = "Credor: \(creditorName)"
            if let document = input.creditorDocument?.nilIfEmpty {
                creditorSummary += ", documento: \(document)"
            }
            if let email = input.creditorEmail?.nilIfEmpty {
                creditorSummary += ", email: \(email)"
            }
            if let phone = input.creditorPhone?.nilIfEmpty {
                creditorSummary += ", telefone: \(phone)"
            }
            if let address = input.creditorAddress?.nilIfEmpty {
                creditorSummary += ", endereço: \(address)"
            }
            sections.append(creditorSummary)
        }

        var debtorSummary = "Devedor: \(input.debtorName)"
        if let document = input.debtorDocument?.nilIfEmpty {
            debtorSummary += ", documento: \(document)"
        }
        if let email = input.debtorEmail?.nilIfEmpty {
            debtorSummary += ", email: \(email)"
        }
        if let phone = input.debtorPhone?.nilIfEmpty {
            debtorSummary += ", telefone: \(phone)"
        }
        if let address = input.debtorAddress?.nilIfEmpty {
            debtorSummary += ", endereço: \(address)"
        }
        sections.append(debtorSummary)

        return sections.joined(separator: "\n")
    }

    /// Aqui eu alinho o número de parcelas com o fluxo atual do web:
    /// 1 quando o contrato é à vista; no parcelado eu envio a quantidade digitada pelo usuário.
    private func resolvedInstallmentCount(for input: AIContractConfirmationInput) -> Int? {
        guard let frequency = input.paymentFrequency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return nil
        }

        if frequency == "UNICO_A_VISTA" {
            return input.installmentCount == 1 ? 1 : nil
        }

        guard let installmentCount = input.installmentCount else {
            return nil
        }

        return installmentCount > 1 ? installmentCount : nil
    }

    /// Aqui eu serializo a query string da busca sem espalhar concatenação manual de URL.
    private func makeRemoteDebtorsPath(empresaId: String, search: String?, limit: Int) -> String {
        var components = URLComponents()
        components.path = APIRoutes.AIService.searchDebtors(empresaId)
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let search {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }

        return components.string ?? APIRoutes.AIService.searchDebtors(empresaId)
    }

    /// Aqui eu converto o valor monetário digitado para `Decimal` antes de enviar ao backend Java.
    private func normalizedDecimal(from currencyText: String) -> Decimal {
        Formatters.decimalFromCurrencyString(currencyText) ?? .zero
    }

    private func firstImageFieldValue(
        _ fields: [String: ImageExtractionField],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = fields[key]?.valor.nilIfEmpty {
                return value
            }
        }
        return nil
    }

    private func parseInstallmentCount(from value: String) -> Int? {
        let digits = Formatters.digitsOnly(value)
        guard
            let numericValue = Int(digits),
            numericValue >= 1,
            numericValue <= 60
        else {
            return nil
        }
        return numericValue
    }

    /// Aqui eu envio os enums de pagamento exatamente como o backend web espera hoje.
    private func normalizedPaymentMethods(from methods: [AIContractPaymentMethodCode]) -> [String]? {
        var values: [String] = []
        for method in methods {
            let backendType = method.backendType
            if values.contains(backendType) == false {
                values.append(backendType)
            }
        }
        return values.isEmpty ? nil : values
    }

    /// Aqui eu removo máscara de CPF/CNPJ antes de mandar o fallback do devedor, igual ao web.
    private func sanitizedDocument(from value: String?) -> String? {
        guard let value = value?.nilIfEmpty else { return nil }
        let digits = Formatters.digitsOnly(value)
        return digits.isEmpty ? nil : digits
    }

    /// Aqui eu removo máscara de telefone antes do payload remoto para reduzir divergência com o frontend web.
    private func sanitizedPhone(from value: String?) -> String? {
        guard let value = value?.nilIfEmpty else { return nil }
        let digits = Formatters.digitsOnly(value)
        return digits.isEmpty ? nil : digits
    }

    private func requiredFlowField(_ value: String?, label: String, missingFields: inout [String]) -> String? {
        guard let normalized = value?.nilIfEmpty else {
            missingFields.append(label)
            return nil
        }
        return normalized
    }

    private func requiredDocumentField(_ value: String?, label: String, missingFields: inout [String]) -> String? {
        guard let normalized = sanitizedDocument(from: value) else {
            missingFields.append(label)
            return nil
        }
        return normalized
    }

    private func requiredPhoneField(_ value: String?, label: String, missingFields: inout [String]) -> String? {
        guard let normalized = sanitizedPhone(from: value) else {
            missingFields.append(label)
            return nil
        }
        return normalized
    }

    /// Aqui eu normalizo a chave Pix com a mesma intenção do backend: documento e telefone sem máscara, e-mail em minúsculas.
    private func requiredPixKeyField(
        _ value: String?,
        pixKeyType: String?,
        label: String,
        missingFields: inout [String]
    ) -> String? {
        guard let normalized = value?.nilIfEmpty else {
            missingFields.append(label)
            return nil
        }

        switch pixKeyType?.uppercased() {
        case "CPF_CNPJ":
            let digits = Formatters.digitsOnly(normalized)
            guard digits.isEmpty == false else {
                missingFields.append(label)
                return nil
            }
            return digits
        case "TELEFONE":
            let digits = Formatters.digitsOnly(normalized)
            guard digits.isEmpty == false else {
                missingFields.append(label)
                return nil
            }
            return digits
        case "EMAIL":
            return normalized.lowercased()
        default:
            return normalized
        }
    }

    private func requiredDigitsField(_ value: String?, digits: Int, label: String, missingFields: inout [String]) -> String? {
        guard let normalized = sanitizedDocument(from: value), normalized.count == digits else {
            missingFields.append(label)
            return nil
        }
        return normalized
    }

    /// Aqui eu volto os enums para rótulos legíveis só no texto livre enviado ao fluxo.
    private func humanReadableBusinessType(from value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PRESTACAO_SERVICOS":
            return "Prestação de Serviços"
        case "COMPRA_VENDA":
            return "Compra e Venda"
        case "EMPRESTIMO":
            return "Empréstimo"
        case "LOCACAO":
            return "Locação"
        case "ACORDO_PAGAMENTO":
            return "Acordo de Pagamento"
        default:
            return "Outro / Acordo Geral"
        }
    }

    /// Aqui eu mantenho o texto do prompt humano enquanto o campo estruturado segue em enum para o backend.
    private func humanReadableFrequency(from value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PARCELADO":
            return "Parcelado"
        default:
            return "Único / À Vista"
        }
    }

    /// Aqui eu gero um assunto amigável quando a IA só devolve texto corrido.
    private func inferSubject(from text: String?) -> String? {
        guard let text = text?.nilIfEmpty else { return nil }

        if text.localizedCaseInsensitiveContains("aluguel") {
            return "Acordo de Aluguel"
        }
        if text.localizedCaseInsensitiveContains("veículo") || text.localizedCaseInsensitiveContains("carro") {
            return "Acordo de Veículo"
        }
        if text.localizedCaseInsensitiveContains("empréstimo") || text.localizedCaseInsensitiveContains("emprestimo") {
            return "Empréstimo Pessoal"
        }

        return "Acordo via Foto"
    }

    private func subject(fromDocumentType value: String?) -> String? {
        guard let value = value?.nilIfEmpty else { return nil }
        let normalized = value
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        return normalized
            .split(separator: " ")
            .map { token in
                guard let firstCharacter = token.first else { return "" }
                return firstCharacter.uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }

    private func businessType(fromDocumentType value: String?) -> String? {
        guard let normalized = value?.nilIfEmpty?.uppercased() else { return nil }

        if normalized.contains("PRESTACAO") || normalized.contains("SERVICO") {
            return "Prestação de Serviços"
        }
        if normalized.contains("ACORDO") || normalized.contains("PARCELAMENTO") {
            return "Acordo de Pagamento"
        }
        return nil
    }

    private func inferBusinessType(from text: String?) -> String? {
        guard let text = text?.nilIfEmpty else { return nil }

        if text.localizedCaseInsensitiveContains("aluguel") || text.localizedCaseInsensitiveContains("locação") {
            return "Locação"
        }
        if text.localizedCaseInsensitiveContains("serviço") || text.localizedCaseInsensitiveContains("servico") {
            return "Prestação de Serviços"
        }
        if text.localizedCaseInsensitiveContains("empréstimo") || text.localizedCaseInsensitiveContains("emprestimo") {
            return "Empréstimo"
        }
        if text.localizedCaseInsensitiveContains("venda") || text.localizedCaseInsensitiveContains("compra") || text.localizedCaseInsensitiveContains("veículo") || text.localizedCaseInsensitiveContains("veiculo") || text.localizedCaseInsensitiveContains("carro") {
            return "Compra e Venda"
        }

        return "Outro / Acordo Geral"
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Aqui eu replico o payload de vencimento que o frontend web envia hoje ao `fluxo-ia`.
    /// O backend aceita `OffsetDateTime`, mas o web/Kotlin ativo hoje envia `yyyy-MM-dd`.
    private static func webFlowDueDateString(from date: Date) -> String {
        apiDateFormatter.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
