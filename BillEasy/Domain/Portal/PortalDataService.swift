//
//  PortalDataService.swift
//  BillEasy
//

import Foundation

/// Aqui eu entrego para as telas "Quero Receber" os dados já prontos vindos do portal remoto.
struct PortalCreditorSnapshot {
    let totalReceivable: Decimal
    let totalRecovered: Decimal
    let debts: [DebtItem]
}

/// Aqui eu entrego para as telas "Quero Pagar" o recorte útil do dashboard do devedor.
struct PortalDebtorSnapshot {
    let totalPayable: Decimal
    let totalPaid: Decimal
    let debts: [DebtItem]
}

/// Aqui eu exponho o resultado paginado das dívidas para as telas controlarem infinite scroll sem conhecer o payload cru.
struct PortalDebtPage {
    let debts: [DebtItem]
    let pageNumber: Int
    let pageSize: Int
    let totalElements: Int
    let totalPages: Int

    var isLastPage: Bool {
        totalPages <= 1 || pageNumber >= totalPages - 1
    }
}

/// Aqui eu mantenho um contrato único para a tela de perfil, misturando sessão e detalhes do usuário.
struct PortalUserProfile {
    let userID: String
    let fullName: String
    let email: String
    let phone: String
    let document: String
    let status: String
    let userType: String
    let emailVerified: Bool
    let mfaEnabled: Bool
}

/// Aqui eu represento o anexo de usuário que o mobile reaproveita como foto de perfil remota.
struct PortalUserAttachment {
    let id: String
    let fileName: String
    let downloadPath: String
    let createdAt: Date?
}

/// Aqui eu descrevo o payload completo de perfil que a UI quer persistir localmente e, quando possível, remotamente.
struct PortalProfileUpdatePayload {
    let fullName: String
    let email: String
    let phone: String
    let document: String
}

/// Aqui eu deixo explícito se o backend aceitou o payload expandido ou se precisei cair no contrato legado.
enum PortalProfileRemoteSyncMode {
    case legacy
    case expanded
}

/// Aqui eu devolvo para a UI o perfil consolidado junto do modo de sincronização realmente aplicado no servidor.
struct PortalProfileSaveResult {
    let profile: PortalUserProfile
    let syncMode: PortalProfileRemoteSyncMode
}

/// Aqui eu concentro os erros remotos mais específicos do módulo portal.
enum PortalDataServiceError: LocalizedError {
    case integrationUnavailable
    case invalidUserContext

    var errorDescription: String? {
        switch self {
        case .integrationUnavailable:
            return "As rotas do portal remoto estão disponíveis apenas no modo autenticado."
        case .invalidUserContext:
            return "A sessão atual não trouxe um identificador de usuário válido."
        }
    }
}

/// Aqui eu centralizo as leituras do portal web para que controllers não precisem conhecer rotas,
/// paginação, parse de datas ou mapeamento de status do backend Java.
final class PortalDataService {
    private enum DebtFeed {
        case payable
        case receivable
    }

    private struct PageMetaResponse: Decodable {
        let size: Int?
        let number: Int?
        let totalElements: Int?
        let totalPages: Int?
    }

    private struct PaginatedResponse<Item: Decodable>: Decodable {
        let content: [Item]
        let page: PageMetaResponse?
    }

    private struct DebtResponse: Decodable {
        struct DebtorPayload: Decodable {
            let id: String?
            let cpfCnpjEnc: String?
        }

        struct ContractPayload: Decodable {
            let id: String?
            let titulo: String?
            let descricao: String?
        }

        struct CreditorPayload: Decodable {
            let id: String?
            let nome: String?
            let cnpj: String?
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
        let devedor: DebtorPayload?
        let contrato: ContractPayload?
        let credorCriador: CreditorPayload?
        let totais: TotalsPayload?
        let contratoId: String?
        let primeiraParcelaId: String?
        let nomeDevedor: String?
        let cpfCnpjDevedor: String?
    }

    private struct SessionProfileResponse: Decodable {
        let id: String
        let nome: String?
        let email: String?
        let telefone: String?
        let status: String?
        let mfaHabilitado: Bool?
        let emailVerificado: Bool?
        let tipoUsuario: String?
    }

    private struct UserDetailsResponse: Decodable {
        let id: String
        let nome: String?
        let email: String?
        let telefone: String?
        let cpfCnpjEnc: String?
        let status: String?
    }

    private struct UserAttachmentResponse: Decodable {
        let id: String
        let nomeArquivo: String?
        let urlDownload: String?
        let criadoEm: String?
        let createdAt: String?
    }

    private struct LegacyUpdateUserRequest: Encodable {
        let nome: String
        let telefone: String
    }

    private struct ExpandedUpdateUserRequest: Encodable {
        let nome: String
        let telefone: String
        let email: String?
        let cpfCnpjEnc: String?
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

    /// Aqui eu deixo a UI decidir rápido se vale tentar o fluxo remoto ou manter o local.
    var isRemoteMode: Bool {
        mode == .remote
    }

    /// Aqui eu junto dashboard do credor e lista de dívidas em um único snapshot para o iOS.
    func fetchCreditorSnapshot(limit: Int = 20) async throws -> PortalCreditorSnapshot {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        let response = try await fetchReceivableDebtPage(page: 0, size: limit)

        return PortalCreditorSnapshot(
            totalReceivable: response.debts.filter { $0.status != .paga }.reduce(.zero) { $0 + $1.valor },
            totalRecovered: response.debts.filter { $0.status == .paga }.reduce(.zero) { $0 + $1.valor },
            debts: response.debts
        )
    }

    /// Aqui eu junto dashboard do devedor e lista de dívidas para manter a tela em uma única leitura.
    func fetchDebtorSnapshot(limit: Int = 20) async throws -> PortalDebtorSnapshot {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        let response = try await fetchPayableDebtPage(page: 0, size: limit)

        return PortalDebtorSnapshot(
            totalPayable: response.debts.filter { $0.status != .paga }.reduce(.zero) { $0 + $1.valor },
            totalPaid: response.debts.filter { $0.status == .paga }.reduce(.zero) { $0 + $1.valor },
            debts: response.debts
        )
    }

    /// Aqui eu exponho explicitamente a leitura de dívidas a receber, porque o backend separou esse feed.
    func fetchReceivableDebts(limit: Int = 20) async throws -> [DebtItem] {
        try await fetchReceivableDebtPage(page: 0, size: limit).debts
    }

    /// Aqui eu entrego a página completa de "quero receber" para as telas controlarem paginação incremental.
    func fetchReceivableDebtPage(page: Int = 0, size: Int = 20) async throws -> PortalDebtPage {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        let response = try await fetchDebtPage(feed: .receivable, page: page, size: size)
        return makePortalDebtPage(from: response, feed: .receivable, page: page, size: size)
    }

    /// Aqui eu exponho explicitamente a leitura de dívidas a pagar, porque a doc nova não usa mais o feed genérico.
    func fetchPayableDebts(limit: Int = 20) async throws -> [DebtItem] {
        try await fetchPayableDebtPage(page: 0, size: limit).debts
    }

    /// Aqui eu entrego a página completa de "quero pagar" para as telas controlarem o carregamento por scroll.
    func fetchPayableDebtPage(page: Int = 0, size: Int = 20) async throws -> PortalDebtPage {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        let response = try await fetchDebtPage(feed: .payable, page: page, size: size)
        return makePortalDebtPage(from: response, feed: .payable, page: page, size: size)
    }

    /// Aqui eu monto o perfil remoto combinando `/session/me` com o detalhe de usuário quando disponível.
    func fetchProfile() async throws -> PortalUserProfile {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        let sessionPayload: SessionProfileResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Session.me
        )

        let userDetails: UserDetailsResponse?
        if let userID = sessionPayload.id.nilIfEmpty {
            userDetails = try? await apiClient.request(
                target: .backend,
                path: APIRoutes.Usuarios.byID(userID)
            )
        } else {
            userDetails = nil
        }

        return PortalUserProfile(
            userID: sessionPayload.id,
            fullName: userDetails?.nome?.nilIfEmpty ?? sessionPayload.nome?.nilIfEmpty ?? "",
            email: userDetails?.email?.nilIfEmpty ?? sessionPayload.email?.nilIfEmpty ?? "",
            phone: userDetails?.telefone?.nilIfEmpty ?? sessionPayload.telefone?.nilIfEmpty ?? "",
            document: userDetails?.cpfCnpjEnc?.nilIfEmpty ?? "",
            status: userDetails?.status?.nilIfEmpty ?? sessionPayload.status?.nilIfEmpty ?? "ATIVO",
            userType: sessionPayload.tipoUsuario?.nilIfEmpty ?? "USUARIO",
            emailVerified: sessionPayload.emailVerificado ?? false,
            mfaEnabled: sessionPayload.mfaHabilitado ?? false
        )
    }

    /// Aqui eu leio o anexo mais recente do usuário para o app tratar como foto de perfil.
    func fetchLatestUserAttachment(userID: String) async throws -> PortalUserAttachment? {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        guard let normalizedUserID = userID.nilIfEmpty else {
            throw PortalDataServiceError.invalidUserContext
        }

        let response: [UserAttachmentResponse] = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Anexos.porUsuario(normalizedUserID)
        )

        let attachments = response.compactMap(makeUserAttachment(from:))
        return attachments.sorted { left, right in
            switch (left.createdAt, right.createdAt) {
            case let (lhs?, rhs?):
                return lhs > rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.id > right.id
            }
        }.first
    }

    /// Aqui eu baixo o anexo em memória para a tela de perfil reaproveitar a imagem sem expor HTTP na view.
    func downloadAttachment(_ attachment: PortalUserAttachment) async throws -> Data {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        return try await apiClient.download(
            target: .backend,
            path: attachment.downloadPath
        )
    }

    /// Aqui eu tento sincronizar o perfil completo e, se o backend ainda estiver no contrato antigo,
    /// faço fallback transparente para salvar ao menos nome e telefone.
    func saveProfile(userID: String, payload: PortalProfileUpdatePayload) async throws -> PortalProfileSaveResult {
        guard isRemoteMode else {
            throw PortalDataServiceError.integrationUnavailable
        }

        guard let normalizedUserID = userID.nilIfEmpty else {
            throw PortalDataServiceError.invalidUserContext
        }

        let normalizedPayload = normalizeProfilePayload(payload)

        if normalizedPayload.hasExpandedFields {
            do {
                try await performProfileUpdate(
                    userID: normalizedUserID,
                    body: ExpandedUpdateUserRequest(
                        nome: normalizedPayload.fullName,
                        telefone: normalizedPayload.phone,
                        email: normalizedPayload.email,
                        cpfCnpjEnc: normalizedPayload.document
                    )
                )

                return PortalProfileSaveResult(
                    profile: try await fetchProfile(),
                    syncMode: .expanded
                )
            } catch {
                guard shouldFallbackToLegacyProfileUpdate(for: error) else {
                    throw error
                }
            }
        }

        try await performProfileUpdate(
            userID: normalizedUserID,
            body: LegacyUpdateUserRequest(
                nome: normalizedPayload.fullName,
                telefone: normalizedPayload.phone
            )
        )

        return PortalProfileSaveResult(
            profile: try await fetchProfile(),
            syncMode: .legacy
        )
    }

    /// Aqui eu serializo a paginação dos feeds "quero pagar" e "quero receber" sem espalhar query string pela UI.
    private func makeDebtFeedPath(feed: DebtFeed, page: Int, size: Int) -> String {
        var components = URLComponents()
        components.path = switch feed {
        case .payable:
            APIRoutes.Dividas.pagar
        case .receivable:
            APIRoutes.Dividas.receber
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: String(max(0, page))),
            URLQueryItem(name: "size", value: String(max(1, size)))
        ]

        return components.string ?? components.path
    }

    /// Aqui eu centralizo a chamada paginada dos novos feeds de dívidas para evitar divergência entre as telas.
    private func fetchDebtPage(feed: DebtFeed, page: Int, size: Int) async throws -> PaginatedResponse<DebtResponse> {
        try await apiClient.request(
            target: .backend,
            path: makeDebtFeedPath(feed: feed, page: page, size: size)
        )
    }

    /// Aqui eu converto o payload paginado do backend em uma estrutura que a UI consegue usar diretamente.
    private func makePortalDebtPage(
        from response: PaginatedResponse<DebtResponse>,
        feed: DebtFeed,
        page: Int,
        size: Int
    ) -> PortalDebtPage {
        PortalDebtPage(
            debts: response.content.map { makeDebtItem(from: $0, feed: feed) },
            pageNumber: response.page?.number ?? page,
            pageSize: response.page?.size ?? size,
            totalElements: response.page?.totalElements ?? response.content.count,
            totalPages: max(response.page?.totalPages ?? 1, 1)
        )
    }

    /// Aqui eu sigo a mesma regra da doc: o total em aberto soma tudo que ainda não foi quitado.
    private func sumOpenAmount(for debts: [DebtResponse]) -> Decimal {
        debts.reduce(into: Decimal.zero) { partialResult, debt in
            guard mapDebtStatus(debt) != .paga else { return }
            partialResult += debt.valorPrincipal ?? .zero
        }
    }

    /// Aqui eu derivou o total pago a partir do payload financeiro e caio no valor principal quando o backend já marcou como pago.
    private func sumPaidAmount(for debts: [DebtResponse]) -> Decimal {
        debts.reduce(into: Decimal.zero) { partialResult, debt in
            if let totalPago = debt.totais?.totalPago {
                partialResult += totalPago
            } else if normalizedStatus(debt.status) == "PAGO" {
                partialResult += debt.valorPrincipal ?? .zero
            }
        }
    }

    /// Aqui eu centralizo a chamada PUT do usuário para manter a lógica de fallback pequena e previsível.
    private func performProfileUpdate<Body: Encodable>(userID: String, body: Body) async throws {
        let _: UserDetailsResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Usuarios.byID(userID),
            method: "PUT",
            body: body
        )
    }

    /// Aqui eu normalizo o perfil antes do envio para evitar string vazia indo como dado sem significado para o backend.
    private func normalizeProfilePayload(_ payload: PortalProfileUpdatePayload) -> (
        fullName: String,
        email: String?,
        phone: String,
        document: String?,
        hasExpandedFields: Bool
    ) {
        let fullName = payload.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = payload.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = payload.email.nilIfEmpty
        let document = payload.document.nilIfEmpty
        let hasExpandedFields = email != nil || document != nil
        return (fullName, email, phone, document, hasExpandedFields)
    }

    /// Aqui eu só volto para o contrato legado quando o erro tiver cara de incompatibilidade de payload.
    private func shouldFallbackToLegacyProfileUpdate(for error: Error) -> Bool {
        guard case let RemoteAPIClientError.server(statusCode, message) = error else {
            return false
        }

        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let compatibilityHints = [
            "unrecognized field",
            "unknown property",
            "json parse error",
            "cannot deserialize",
            "not marked as ignorable",
            "falha ao ler",
            "falha ao processar",
            "campos inválidos",
            "campo inválido"
        ]

        if compatibilityHints.contains(where: normalizedMessage.contains) {
            return true
        }

        return [400, 415, 422].contains(statusCode)
    }

    /// Aqui eu converto o payload remoto da dívida no mesmo modelo de domínio local já usado pela UI.
    private func makeDebtItem(from response: DebtResponse, feed: DebtFeed) -> DebtItem {
        let dueDate = parseRemoteDate(response.dataVencimento)
        let title = response.descricao?.nilIfEmpty
            ?? response.contrato?.titulo?.nilIfEmpty
            ?? "Dívida sem descrição"
        let secondaryName: String
        switch feed {
        case .receivable:
            secondaryName = response.contrato?.titulo?.nilIfEmpty
                ?? response.nomeDevedor?.nilIfEmpty
                ?? "Parte não identificada"
        case .payable:
            secondaryName = response.credorCriador?.nome?.nilIfEmpty
                ?? response.contrato?.titulo?.nilIfEmpty
                ?? "Parte não identificada"
        }

        return DebtItem(
            id: response.id,
            titulo: title,
            devedorNome: secondaryName,
            valor: response.valorPrincipal ?? .zero,
            vencimento: dueDate,
            status: mapDebtStatus(response),
            contractID: response.contratoId?.nilIfEmpty ?? response.contrato?.id?.nilIfEmpty,
            firstInstallmentID: response.primeiraParcelaId?.nilIfEmpty,
            debtorDocument: response.cpfCnpjDevedor?.nilIfEmpty ?? response.devedor?.cpfCnpjEnc?.nilIfEmpty
        )
    }

    /// Aqui eu trato datas ISO completas e datas simples para cobrir o backend Java inteiro.
    private func parseRemoteDate(_ rawValue: String?) -> Date {
        guard let rawValue = rawValue?.nilIfEmpty else {
            return Date()
        }

        if let date = Self.offsetDateTimeFormatterWithFraction.date(from: rawValue) {
            return date
        }

        if let date = Self.offsetDateTimeFormatter.date(from: rawValue) {
            return date
        }

        if let date = Self.localDateFormatter.date(from: rawValue) {
            return date
        }

        return Date()
    }

    /// Aqui eu traduzo o contrato novo de status do backend para o enum local que as telas já entendem.
    private func mapDebtStatus(_ response: DebtResponse) -> DebtStatus {
        switch normalizedStatus(response.status) {
        case "PAGO":
            return .paga
        case "CANCELADO":
            return .cancelada
        case "NAO_PAGO":
            return isDebtOverdue(response) ? .vencida : .pendente
        default:
            return .pendente
        }
    }

    /// Aqui eu reaproveito o indicador do backend e, quando ele não vier, recalculo o atraso pela data de vencimento.
    private func isDebtOverdue(_ response: DebtResponse) -> Bool {
        if let emAtraso = response.totais?.emAtraso {
            return emAtraso
        }

        return parseRemoteDate(response.dataVencimento) < Date()
    }

    /// Aqui eu normalizo o status textual do backend em um único lugar para evitar if espalhado.
    private func normalizedStatus(_ rawStatus: String?) -> String {
        rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    /// Aqui eu normalizo o DTO de anexo do backend em um modelo pequeno e estável para o iOS.
    private func makeUserAttachment(from response: UserAttachmentResponse) -> PortalUserAttachment? {
        guard
            let id = response.id.nilIfEmpty,
            let downloadPath = response.urlDownload?.nilIfEmpty
        else {
            return nil
        }

        return PortalUserAttachment(
            id: id,
            fileName: response.nomeArquivo?.nilIfEmpty ?? "arquivo",
            downloadPath: downloadPath,
            createdAt: parseAttachmentDate(response.criadoEm ?? response.createdAt)
        )
    }

    /// Aqui eu cubro tanto `criadoEm` do backend Java quanto variações já vistas em outros payloads.
    private func parseAttachmentDate(_ rawValue: String?) -> Date? {
        guard let rawValue = rawValue?.nilIfEmpty else {
            return nil
        }

        if let date = Self.offsetDateTimeFormatterWithFraction.date(from: rawValue) {
            return date
        }

        if let date = Self.offsetDateTimeFormatter.date(from: rawValue) {
            return date
        }

        return Self.localDateFormatter.date(from: rawValue)
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
