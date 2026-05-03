//
//  PortalActionsService.swift
//  BillEasy
//

import Foundation

/// Aqui eu exponho apenas os detalhes contratuais que os modais realmente precisam para renderizar e agir.
struct PortalContractDetail {
    let contractID: String
    let title: String
    let status: String
    let contractText: String
    let creditorSigned: Bool
    let debtorSigned: Bool
}

/// Aqui eu exponho o detalhe real da dívida para que os modais reflitam valor, vencimento e atraso do backend.
struct PortalDebtDetail {
    let debtID: String
    let title: String
    let status: String
    let principalAmount: Decimal
    let updatedAmount: Decimal
    let dueDate: Date
    let dueDateDisplay: String
    let overdueDays: Int
    let isOverdue: Bool
    let contractID: String?
    let contractTitle: String
    let contractDescription: String?
    let creditorName: String
    let creditorDocument: String?
    let debtorDocument: String?
    let installmentNumber: Int?
    let installmentTotal: Int?

    var overdueText: String {
        "\(max(overdueDays, 0)) dias"
    }

    var updatedAmountText: String {
        Formatters.normalizeCurrencyDisplay(updatedAmount.asCurrency)
    }

    var principalAmountText: String {
        Formatters.normalizeCurrencyDisplay(principalAmount.asCurrency)
    }

    var installmentSummary: String? {
        guard let installmentTotal, installmentTotal > 1 else { return nil }

        if let installmentNumber, installmentNumber > 0 {
            return "Parcela \(installmentNumber) de \(installmentTotal)"
        }

        return "\(installmentTotal)x parcelas"
    }

    var fallbackContractText: String {
        let description = contractDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        INSTRUMENTO PARTICULAR DE CONFISSÃO DE DÍVIDA E OUTRAS AVENÇAS

        Pelo presente instrumento, as partes reconhecem a dívida "\(title)" vinculada ao contrato "\(contractTitle)".

        VALOR PRINCIPAL
        \(principalAmountText)

        VALOR ATUALIZADO
        \(updatedAmountText)

        VENCIMENTO
        \(dueDateDisplay)

        CREDOR
        \(creditorName)

        CONDIÇÕES GERAIS
        \(description?.isEmpty == false ? description! : "O pagamento deverá seguir as condições cadastradas no BillEasy. Em caso de atraso, podem incidir multa e juros conforme o contrato e a legislação aplicável.")
        """
    }
}

/// Aqui eu padronizo os métodos de pagamento que o app pode enviar ao backend.
enum PortalPaymentMethod: String, CaseIterable {
    case pix = "PIX"
    case creditCard = "CARTAO_DE_CREDITO"
    case debitCard = "CARTAO_DEBITO"
    case boleto = "BOLETO"

    var displayName: String {
        switch self {
        case .pix:
            return "Pix"
        case .creditCard:
            return "Cartão de Crédito"
        case .debitCard:
            return "Cartão de Débito"
        case .boleto:
            return "Boleto"
        }
    }
}

/// Aqui eu descrevo o recibo mínimo necessário para feedback após criar um pagamento remoto.
struct PortalPaymentReceipt {
    let paymentID: String
    let status: String
    let method: PortalPaymentMethod
    let pixQRCode: String?
    let digitableLine: String?
}

/// Aqui eu represento uma opção de pagamento já normalizada para a UI, sem expor o contrato cru do backend.
struct PortalPaymentMethodOption: Equatable {
    let method: PortalPaymentMethod
    let title: String
    let subtitle: String
    let iconSystemName: String

    static let fallbackOptions: [PortalPaymentMethodOption] = [
        PortalPaymentMethodOption(
            method: .pix,
            title: "Pagar com Pix",
            subtitle: "Aprova na hora • Mais rápido",
            iconSystemName: "qrcode"
        ),
        PortalPaymentMethodOption(
            method: .creditCard,
            title: "Cartão de Crédito",
            subtitle: "Parcele em até 12x no cartão",
            iconSystemName: "creditcard"
        ),
        PortalPaymentMethodOption(
            method: .boleto,
            title: "Boleto Bancário",
            subtitle: "Pode levar até 3 dias",
            iconSystemName: "barcode"
        )
    ]
}

/// Aqui eu exponho o preview de CEP exatamente como o backend web devolve para os formulários.
struct PortalAddressPreview {
    let cep: String
    let logradouro: String
    let bairro: String
    let cidade: String
    let estado: String

    var formattedLine: String {
        [logradouro, bairro, cidade, estado]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: ", ")
    }
}

/// Aqui eu explico os erros de ação remota com mensagens próprias para a UI.
enum PortalActionsServiceError: LocalizedError {
    case integrationUnavailable
    case invalidContext(String)
    case installmentUnavailable

    var errorDescription: String? {
        switch self {
        case .integrationUnavailable:
            return "Essa ação remota está disponível apenas para contas autenticadas no backend."
        case let .invalidContext(message):
            return message
        case .installmentUnavailable:
            return "Não encontrei nenhuma parcela disponível para registrar o pagamento."
        }
    }
}

/// Aqui eu concentro as ações remotas do portal para que a UI não conheça payloads nem detalhes de rota.
final class PortalActionsService {
    private struct UUIDReference: Encodable {
        let id: String
    }

    private struct PasswordUpdateRequest: Encodable {
        let senhaAtual: String
        let senhaNova: String
    }

    private struct ContractSignatureRequest: Encodable {
        let assinaturaTipo: String
        let assinaturaReferencia: String?
    }

    private struct PaymentCreateRequest: Encodable {
        let metodo: String
    }

    private struct PaymentMethodCatalogResponse: Decodable {
        let rawValue: String?
        let name: String?
        let description: String?
        let icon: String?
        let isActive: Bool

        init(from decoder: Decoder) throws {
            if let singleValue = try? decoder.singleValueContainer() {
                if let rawString = try? singleValue.decode(String.self) {
                    rawValue = rawString
                    name = nil
                    description = nil
                    icon = nil
                    isActive = true
                    return
                }
            }

            let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
            rawValue = Self.firstNonEmptyValue(
                in: container,
                forKeys: ["tipoPagamento", "meioPagamento", "metodoPagamento", "codigo", "valor", "name", "nome"]
            )
            name = Self.firstNonEmptyValue(
                in: container,
                forKeys: ["nome", "label", "titulo", "displayName"]
            )
            description = Self.firstNonEmptyValue(
                in: container,
                forKeys: ["descricao", "subtitle", "subtitulo", "hint"]
            )
            icon = Self.firstNonEmptyValue(
                in: container,
                forKeys: ["icone", "icon", "iconeSistema", "iconName"]
            )
            isActive = Self.firstBoolValue(
                in: container,
                forKeys: ["ativo", "habilitado", "enabled", "active"]
            ) ?? true
        }

        private static func firstNonEmptyValue(
            in container: KeyedDecodingContainer<DynamicCodingKeys>,
            forKeys keys: [String]
        ) -> String? {
            for key in keys {
                guard let codingKey = DynamicCodingKeys(stringValue: key) else { continue }
                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey), let normalized = value.nilIfEmpty {
                    return normalized
                }
            }
            return nil
        }

        private static func firstBoolValue(
            in container: KeyedDecodingContainer<DynamicCodingKeys>,
            forKeys keys: [String]
        ) -> Bool? {
            for key in keys {
                guard let codingKey = DynamicCodingKeys(stringValue: key) else { continue }
                if let value = try? container.decodeIfPresent(Bool.self, forKey: codingKey) {
                    return value
                }
            }
            return nil
        }
    }

    private struct DynamicCodingKeys: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    private struct ManualAddressRequest: Encodable {
        let cep: String
        let numero: String
        let complemento: String?
    }

    private struct ManualDebtorRequest: Encodable {
        let nome: String
        let cpfCnpjEnc: String
        let email: String
        let telefone: String
        let endereco: ManualAddressRequest
    }

    private struct ManualContractCreateRequest: Encodable {
        let titulo: String
        let descricao: String?
        let valorTotal: Decimal
        let credorCriador: UUIDReference
        let devedor: UUIDReference?
        let novoDevedor: ManualDebtorRequest?
        let tipoNegocio: String
        let assunto: String
        let descricaoDetalhada: String?
        let frequenciaPagamento: String
        let quantidadeParcelas: Int?
        let dataPrimeiroVencimento: String
        let meiosPagamentoAceitos: [String]
    }

    private struct AddressPreviewResponse: Decodable {
        let cep: String?
        let logradouro: String?
        let bairro: String?
        let cidade: String?
        let estado: String?
    }

    private struct ContractResponse: Decodable {
        struct PartySnapshot: Decodable {
            let nome: String?
            let email: String?
            let telefone: String?
            let cpfCnpj: String?
            let cpfCnpjEnc: String?
            let enderecoCompleto: String?
        }

        let id: String
        let titulo: String?
        let descricao: String?
        let valorTotal: Decimal?
        let status: String?
        let tipoNegocio: String?
        let assunto: String?
        let descricaoDetalhada: String?
        let frequenciaPagamento: String?
        let quantidadeParcelas: Int?
        let dataPrimeiroVencimento: String?
        let credorSnapshot: PartySnapshot?
        let devedorSnapshot: PartySnapshot?
        let assinadoPorCredor: Bool?
        let assinadoPorDevedor: Bool?
        let completamenteAssinado: Bool?
    }

    private struct DebtDetailResponse: Decodable {
        struct CreditorPayload: Decodable {
            let id: String?
            let nome: String?
            let cnpj: String?
        }

        struct DebtorPayload: Decodable {
            let id: String?
            let cpfCnpjEnc: String?
        }

        struct ContractPayload: Decodable {
            let id: String?
            let titulo: String?
            let descricao: String?
        }

        struct TotalsPayload: Decodable {
            let totalDevidoBruto: Decimal?
            let diasEmAtraso: Int?
            let emAtraso: Bool?
            let totalPago: Decimal?
            let totalDevidoLiquido: Decimal?
        }

        let id: String
        let descricao: String?
        let valorPrincipal: Decimal?
        let status: String?
        let dataVencimento: String?
        let credorCriador: CreditorPayload?
        let devedor: DebtorPayload?
        let contrato: ContractPayload?
        let totais: TotalsPayload?
        let multaPercentual: Decimal?
        let jurosMensalPercentual: Decimal?
        let numeroParcela: Int?
        let totalParcelas: Int?
    }

    private struct InstallmentResponse: Decodable {
        let id: String
        let numeroParcela: Int?
        let valorParcela: Decimal?
        let dataVencimento: String?
        let status: String?

        /// Aqui eu marco os estados finais para eu não tentar pagar o que já foi concluído ou cancelado.
        var isFinalized: Bool {
            switch status?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            case "PAGA", "CANCELADA":
                return true
            default:
                return false
            }
        }
    }

    private struct PaymentResponse: Decodable {
        let id: String
        let metodo: String?
        let status: String?
        let qrCodePix: String?
        let linhaDigitavel: String?
    }

    private struct UserAttachmentResponse: Decodable {
        let id: String
        let nomeArquivo: String?
        let urlDownload: String?
        let criadoEm: String?
        let createdAt: String?
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

    /// Aqui eu deixo a UI decidir rapidamente se usa backend real ou mantém o fallback local.
    var isRemoteMode: Bool {
        mode == .remote
    }

    /// Aqui eu envio a troca de senha exatamente no contrato aceito pelo backend Java.
    func updatePassword(userID: String, currentPassword: String, newPassword: String) async throws {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedUserID = userID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("Não encontrei o identificador do usuário autenticado para trocar a senha.")
        }

        try await apiClient.sendVoid(
            target: .backend,
            path: APIRoutes.Usuarios.atualizarSenha(normalizedUserID),
            method: "PUT",
            body: PasswordUpdateRequest(
                senhaAtual: currentPassword.trimmingCharacters(in: .whitespacesAndNewlines),
                senhaNova: newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    /// Aqui eu crio o contrato manual pelo mesmo endpoint do web quando o usuário não escolhe o fluxo de IA.
    func createManualContract(
        input: AIContractConfirmationInput,
        companyID: String
    ) async throws -> PortalContractDetail {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedCompanyID = companyID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("Não encontrei a empresa credora da sessão para criar o contrato manual.")
        }

        guard
            let debtorName = input.debtorName.nilIfEmpty,
            let debtorDocument = sanitizedDigits(from: input.debtorDocument),
            let debtorEmail = input.debtorEmail?.nilIfEmpty,
            let debtorPhone = sanitizedDigits(from: input.debtorPhone),
            let debtorCEP = sanitizedDigits(from: input.debtorCEP),
            let debtorNumber = input.debtorAddressNumber?.nilIfEmpty
        else {
            throw PortalActionsServiceError.invalidContext("O backend manual exige nome, CPF/CNPJ, e-mail, telefone, CEP e número do devedor.")
        }

        let response: ContractResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Contratos.base,
            method: "POST",
            body: ManualContractCreateRequest(
                titulo: input.title,
                descricao: input.description.nilIfEmpty,
                valorTotal: Formatters.decimalFromCurrencyString(input.totalValueText) ?? .zero,
                credorCriador: UUIDReference(id: normalizedCompanyID),
                devedor: nil,
                novoDevedor: ManualDebtorRequest(
                    nome: debtorName,
                    cpfCnpjEnc: debtorDocument,
                    email: debtorEmail,
                    telefone: debtorPhone,
                    endereco: ManualAddressRequest(
                        cep: debtorCEP,
                        numero: debtorNumber,
                        complemento: input.debtorAddressComplement?.nilIfEmpty
                    )
                ),
                tipoNegocio: input.businessType?.nilIfEmpty ?? "OUTRO_ACORDO_GERAL",
                assunto: input.subject,
                descricaoDetalhada: input.description.nilIfEmpty,
                frequenciaPagamento: input.paymentFrequency?.nilIfEmpty ?? "UNICO_A_VISTA",
                quantidadeParcelas: (input.installmentCount ?? 0) > 0 ? input.installmentCount ?? 1 : 1,
                dataPrimeiroVencimento: Self.webDateString(from: input.dueDate),
                meiosPagamentoAceitos: normalizedPaymentMethods(from: input.paymentMethods)
            )
        )

        return makeContractDetail(from: response)
    }

    /// Aqui eu consulto o preview do CEP para o formulário manual espelhar o comportamento da web.
    func fetchAddressPreview(cep: String) async throws -> PortalAddressPreview {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        let normalizedCEP = Formatters.digitsOnly(cep)
        guard normalizedCEP.count == 8 else {
            throw PortalActionsServiceError.invalidContext("Informe um CEP válido com 8 dígitos.")
        }

        let response: AddressPreviewResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.CEP.consultar(normalizedCEP)
        )

        return PortalAddressPreview(
            cep: response.cep?.nilIfEmpty ?? Formatters.formatCEP(normalizedCEP),
            logradouro: response.logradouro?.nilIfEmpty ?? "",
            bairro: response.bairro?.nilIfEmpty ?? "",
            cidade: response.cidade?.nilIfEmpty ?? "",
            estado: response.estado?.nilIfEmpty ?? ""
        )
    }

    /// Aqui eu busco o contrato remoto completo para o modal exibir o texto mais fiel ao backend.
    func fetchContractDetail(contractID: String) async throws -> PortalContractDetail {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedContractID = contractID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("O contrato selecionado não possui um identificador válido.")
        }

        let response: ContractResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Contratos.byID(normalizedContractID)
        )

        return makeContractDetail(from: response)
    }

    /// Aqui eu leio o detalhe real da dívida para os modais consumirem o mesmo endpoint do web.
    func fetchDebtDetail(debtID: String) async throws -> PortalDebtDetail {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedDebtID = debtID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("A dívida selecionada não possui um identificador válido.")
        }

        let response: DebtDetailResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Dividas.byID(normalizedDebtID)
        )

        return makeDebtDetail(from: response)
    }

    /// Aqui eu carrego o catálogo de métodos de pagamento do backend para o modal ficar alinhado com o app web/Kotlin.
    func fetchPaymentMethods() async throws -> [PortalPaymentMethodOption] {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        let response: [PaymentMethodCatalogResponse] = try await apiClient.request(
            target: .backend,
            path: APIRoutes.FormasDePagamentos.base
        )

        var seenMethods = Set<PortalPaymentMethod>()
        let options = response.compactMap(makePaymentMethodOption(from:)).filter { option in
            seenMethods.insert(option.method).inserted
        }
        return options.isEmpty ? PortalPaymentMethodOption.fallbackOptions : options
    }

    /// Aqui eu registro a assinatura do credor com o tipo escolhido na UI nativa.
    func signContractAsCreditor(
        contractID: String,
        signatureType: PortalContractSignatureType
    ) async throws -> PortalContractDetail {
        try await signContract(
            contractID: contractID,
            pathBuilder: APIRoutes.Contratos.assinarCredor,
            signatureType: signatureType,
            referencePrefix: "credor"
        )
    }

    /// Aqui eu registro a assinatura do devedor quando ele conclui a etapa no modal.
    func signContractAsDebtor(
        contractID: String,
        signatureType: PortalContractSignatureType
    ) async throws -> PortalContractDetail {
        try await signContract(
            contractID: contractID,
            pathBuilder: APIRoutes.Contratos.assinarDevedor,
            signatureType: signatureType,
            referencePrefix: "devedor"
        )
    }

    /// Aqui eu obtenho o arquivo real do contrato e devolvo uma URL temporária para a visualização interna do app.
    func downloadContractDocument(contractID: String) async throws -> URL {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedContractID = contractID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("O contrato selecionado não possui um identificador válido.")
        }

        let data = try await apiClient.download(
            target: .backend,
            path: APIRoutes.Contratos.documentoPDF(normalizedContractID)
        )

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("contrato-\(normalizedContractID)")
            .appendingPathExtension("pdf")

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Aqui eu crio um pagamento remoto usando a primeira parcela elegível quando a lista não trouxer o ID direto.
    func createPayment(
        debtID: String,
        preferredInstallmentID: String?,
        method: PortalPaymentMethod
    ) async throws -> PortalPaymentReceipt {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedDebtID = debtID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("A dívida selecionada não possui um identificador válido.")
        }

        let installmentID = try await resolveInstallmentID(
            debtID: normalizedDebtID,
            preferredInstallmentID: preferredInstallmentID
        )

        let response: PaymentResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Pagamentos.porParcela(dividaId: normalizedDebtID, parcelaId: installmentID),
            method: "POST",
            body: PaymentCreateRequest(metodo: method.rawValue)
        )

        return PortalPaymentReceipt(
            paymentID: response.id,
            status: response.status?.nilIfEmpty ?? "CRIADO",
            method: method,
            pixQRCode: response.qrCodePix?.nilIfEmpty,
            digitableLine: response.linhaDigitavel?.nilIfEmpty
        )
    }

    /// Aqui eu envio a foto de perfil para o endpoint de anexos do usuário sem espalhar multipart pela UI.
    func uploadUserProfilePhoto(
        userID: String,
        imageData: Data,
        filename: String = "perfil.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> PortalUserAttachment {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedUserID = userID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("Não encontrei o usuário autenticado para enviar a foto de perfil.")
        }

        let response: UserAttachmentResponse = try await apiClient.upload(
            target: .backend,
            path: APIRoutes.Anexos.porUsuario(normalizedUserID),
            fileFieldName: "arquivo",
            fileData: imageData,
            filename: filename,
            mimeType: mimeType
        )

        guard
            let attachmentID = response.id.nilIfEmpty,
            let downloadPath = response.urlDownload?.nilIfEmpty
        else {
            throw PortalActionsServiceError.invalidContext("O backend recebeu a foto, mas não devolveu um anexo válido.")
        }

        return PortalUserAttachment(
            id: attachmentID,
            fileName: response.nomeArquivo?.nilIfEmpty ?? filename,
            downloadPath: downloadPath,
            createdAt: parseAttachmentDate(response.criadoEm ?? response.createdAt)
        )
    }

    /// Aqui eu pego a lista de parcelas e escolho a primeira que ainda faz sentido pagar.
    private func resolveInstallmentID(debtID: String, preferredInstallmentID: String?) async throws -> String {
        if let preferredInstallmentID = preferredInstallmentID?.nilIfEmpty {
            return preferredInstallmentID
        }

        let installments: [InstallmentResponse] = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Parcelas.base(dividaId: debtID)
        )

        if let firstOpenInstallment = installments.first(where: { !$0.isFinalized }) {
            return firstOpenInstallment.id
        }

        if let firstInstallment = installments.first {
            return firstInstallment.id
        }

        throw PortalActionsServiceError.installmentUnavailable
    }

    /// Aqui eu centralizo a assinatura para não repetir o mesmo request em credor e devedor.
    private func signContract(
        contractID: String,
        pathBuilder: (String) -> String,
        signatureType: PortalContractSignatureType,
        referencePrefix: String
    ) async throws -> PortalContractDetail {
        guard isRemoteMode else {
            throw PortalActionsServiceError.integrationUnavailable
        }

        guard let normalizedContractID = contractID.nilIfEmpty else {
            throw PortalActionsServiceError.invalidContext("O contrato selecionado não possui um identificador válido.")
        }

        let response: ContractResponse = try await apiClient.request(
            target: .backend,
            path: pathBuilder(normalizedContractID),
            method: "POST",
            body: ContractSignatureRequest(
                assinaturaTipo: signatureType.rawValue,
                assinaturaReferencia: "\(referencePrefix)-\(Int(Date().timeIntervalSince1970))"
            )
        )

        return makeContractDetail(from: response)
    }

    /// Aqui eu traduzo o payload do backend para um modelo nativo mais estável para os modais.
    private func makeContractDetail(from response: ContractResponse) -> PortalContractDetail {
        PortalContractDetail(
            contractID: response.id,
            title: response.assunto?.nilIfEmpty ?? response.titulo?.nilIfEmpty ?? "Contrato Digital",
            status: response.status?.nilIfEmpty ?? "DESCONHECIDO",
            contractText: contractText(from: response),
            creditorSigned: response.assinadoPorCredor ?? false,
            debtorSigned: response.assinadoPorDevedor ?? false
        )
    }

    /// Aqui eu traduzo o detalhe da dívida em um modelo enxuto que os modais conseguem reaproveitar.
    private func makeDebtDetail(from response: DebtDetailResponse) -> PortalDebtDetail {
        let dueDate = response.dataVencimento.flatMap { Self.parseRemoteDate($0) } ?? Date()
        let updatedAmount = response.totais?.totalDevidoLiquido
            ?? response.totais?.totalDevidoBruto
            ?? response.valorPrincipal
            ?? .zero

        return PortalDebtDetail(
            debtID: response.id,
            title: response.descricao?.nilIfEmpty ?? response.contrato?.titulo?.nilIfEmpty ?? "Dívida sem descrição",
            status: response.status?.nilIfEmpty ?? "NAO_PAGO",
            principalAmount: response.valorPrincipal ?? .zero,
            updatedAmount: updatedAmount,
            dueDate: dueDate,
            dueDateDisplay: Formatters.shortDate.string(from: dueDate),
            overdueDays: response.totais?.diasEmAtraso ?? 0,
            isOverdue: response.totais?.emAtraso ?? (dueDate < Date()),
            contractID: response.contrato?.id?.nilIfEmpty,
            contractTitle: response.contrato?.titulo?.nilIfEmpty ?? "Contrato sem título",
            contractDescription: response.contrato?.descricao?.nilIfEmpty,
            creditorName: response.credorCriador?.nome?.nilIfEmpty ?? "Credor não identificado",
            creditorDocument: response.credorCriador?.cnpj?.nilIfEmpty,
            debtorDocument: response.devedor?.cpfCnpjEnc?.nilIfEmpty,
            installmentNumber: response.numeroParcela,
            installmentTotal: response.totalParcelas
        )
    }

    /// Aqui eu removo máscara numérica do formulário antes do payload manual para manter o mesmo contrato do web.
    private func sanitizedDigits(from value: String?) -> String? {
        guard let value = value?.nilIfEmpty else { return nil }
        let digits = Formatters.digitsOnly(value)
        return digits.isEmpty ? nil : digits
    }

    /// Aqui eu converto o array do app para os enums exatos que o backend atual espera.
    private func normalizedPaymentMethods(from methods: [AIContractPaymentMethodCode]) -> [String] {
        let values = methods.map(\.backendType)
        return Array(NSOrderedSet(array: values)) as? [String] ?? values
    }

    /// Aqui eu converto o catálogo remoto para as mesmas opções visuais que o app já entende.
    private func makePaymentMethodOption(from response: PaymentMethodCatalogResponse) -> PortalPaymentMethodOption? {
        guard response.isActive else { return nil }
        guard let method = paymentMethod(from: response.rawValue) else { return nil }

        let fallback = fallbackOption(for: method)
        let title = resolvedPaymentMethodTitle(
            rawName: response.name,
            rawValue: response.rawValue,
            fallback: fallback.title
        )

        return PortalPaymentMethodOption(
            method: method,
            title: title,
            subtitle: response.description?.nilIfEmpty ?? fallback.subtitle,
            iconSystemName: resolvedPaymentMethodIcon(rawIcon: response.icon, fallback: fallback.iconSystemName)
        )
    }

    /// Aqui eu traduzo o catálogo textual do backend para o enum interno usado no fluxo de pagamento.
    private func paymentMethod(from rawValue: String?) -> PortalPaymentMethod? {
        guard let rawValue = rawValue?.nilIfEmpty else { return nil }

        let normalized = rawValue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "PIX":
            return .pix
        case "BOLETO", "BOLETO_BANCARIO":
            return .boleto
        case "CARTAO", "CARTAO_CREDITO", "CARTAO_DE_CREDITO", "CREDIT_CARD":
            return .creditCard
        case "CARTAO_DEBITO", "CARTAO_DE_DEBITO", "DEBIT_CARD":
            return .debitCard
        default:
            return nil
        }
    }

    /// Aqui eu centralizo a cópia visual padrão de cada método para não duplicar texto entre serviço e modal.
    private func fallbackOption(for method: PortalPaymentMethod) -> PortalPaymentMethodOption {
        switch method {
        case .pix:
            return PortalPaymentMethodOption(
                method: .pix,
                title: "Pagar com Pix",
                subtitle: "Aprova na hora • Mais rápido",
                iconSystemName: "qrcode"
            )
        case .creditCard:
            return PortalPaymentMethodOption(
                method: .creditCard,
                title: "Cartão de Crédito",
                subtitle: "Parcele em até 12x no cartão",
                iconSystemName: "creditcard"
            )
        case .debitCard:
            return PortalPaymentMethodOption(
                method: .debitCard,
                title: "Cartão de Débito",
                subtitle: "Débito em conta na hora",
                iconSystemName: "creditcard.and.123"
            )
        case .boleto:
            return PortalPaymentMethodOption(
                method: .boleto,
                title: "Boleto Bancário",
                subtitle: "Pode levar até 3 dias",
                iconSystemName: "barcode"
            )
        }
    }

    /// Aqui eu evito mostrar um nome cru de enum quando o backend devolver a opção em formato técnico.
    private func resolvedPaymentMethodTitle(rawName: String?, rawValue: String?, fallback: String) -> String {
        guard let candidate = rawName?.nilIfEmpty ?? rawValue?.nilIfEmpty else {
            return fallback
        }

        let normalized = candidate
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .uppercased()

        switch normalized {
        case "PIX", "BOLETO", "BOLETO BANCARIO", "BOLETO_BANCARIO", "CARTAO", "CARTAO CREDITO",
             "CARTAO_CREDITO", "CARTAO DE CREDITO", "CARTAO_DE_CREDITO", "CARTAO DEBITO",
             "CARTAO_DEBITO", "CARTAO DE DEBITO", "CARTAO_DE_DEBITO":
            return fallback
        default:
            return candidate
        }
    }

    /// Aqui eu aceito uma pista de ícone do backend sem deixar a UI quebrar quando o catálogo vier incompleto.
    private func resolvedPaymentMethodIcon(rawIcon: String?, fallback: String) -> String {
        guard let rawIcon = rawIcon?.nilIfEmpty else { return fallback }

        let normalized = rawIcon
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "pix", "qrcode", "qr_code":
            return "qrcode"
        case "boleto", "barcode", "codigo_de_barras":
            return "barcode"
        case "cartao", "cartao_credito", "cartao_de_credito", "credit_card", "creditcard":
            return "creditcard"
        case "cartao_debito", "cartao_de_debito", "debit_card":
            return "creditcard.and.123"
        default:
            return fallback
        }
    }

    /// Aqui eu replico a serialização de data usada pelo frontend web para o POST manual de contratos.
    private static func webDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: -3 * 3600)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    /// Aqui eu priorizo o texto detalhado do backend e só monto um fallback quando ele não vier preenchido.
    private func contractText(from response: ContractResponse) -> String {
        if let detailedText = response.descricaoDetalhada?.nilIfEmpty {
            return detailedText
        }

        let title = response.assunto?.nilIfEmpty ?? response.titulo?.nilIfEmpty ?? "Acordo BillEasy"
        let amountText = normalizedCurrency(response.valorTotal ?? .zero)
        let dueDate = response.dataPrimeiroVencimento.flatMap { Self.parseRemoteDate($0) }.map {
            Formatters.shortDate.string(from: $0)
        } ?? "a definir"
        let creditorName = response.credorSnapshot?.nome?.nilIfEmpty ?? "Credor não informado"
        let debtorName = response.devedorSnapshot?.nome?.nilIfEmpty ?? "Devedor não informado"
        let description = response.descricao?.nilIfEmpty
            ?? response.descricaoDetalhada?.nilIfEmpty
            ?? "As partes concordam com as condições registradas na plataforma BillEasy."
        let frequency = response.frequenciaPagamento?.nilIfEmpty ?? "Conforme negociação entre as partes"
        let installments = response.quantidadeParcelas.map(String.init) ?? "1"

        return """
        CONTRATO DIGITAL BILL EASY

        ASSUNTO
        \(title)

        CREDOR
        \(creditorName)

        DEVEDOR
        \(debtorName)

        OBJETO
        \(description)

        VALOR TOTAL
        \(amountText)

        PRIMEIRO VENCIMENTO
        \(dueDate)

        FREQUÊNCIA
        \(frequency)

        QUANTIDADE DE PARCELAS
        \(installments)

        STATUS ATUAL
        \(response.status?.nilIfEmpty ?? "Não informado")
        """
    }

    /// Aqui eu padronizo a moeda do fallback com o mesmo formatter usado no restante do app.
    private func normalizedCurrency(_ amount: Decimal) -> String {
        Formatters.currencyText(from: amount)
    }

    /// Aqui eu reaproveito o parser de datas para anexos de usuário e outras respostas leves.
    private func parseAttachmentDate(_ rawValue: String?) -> Date? {
        guard let rawValue = rawValue?.nilIfEmpty else {
            return nil
        }

        return Self.parseRemoteDate(rawValue)
    }

    /// Aqui eu interpreto a mesma variedade de datas ISO que o backend Java pode devolver.
    private static func parseRemoteDate(_ rawValue: String) -> Date? {
        if let date = offsetDateTimeFormatterWithFraction.date(from: rawValue) {
            return date
        }

        if let date = offsetDateTimeFormatter.date(from: rawValue) {
            return date
        }

        return localDateFormatter.date(from: rawValue)
    }

    private static let offsetDateTimeFormatterWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let offsetDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

/// Aqui eu mantenho os tipos de assinatura alinhados com o enum real do backend Java.
enum PortalContractSignatureType: String {
    case govBr = "GOV_BR"
    case token = "TOKEN"
    case electronic = "ELETRONICA"
    case physical = "FISICA"
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
