//
//  NotificacoesService.swift
//  BillEasy
//

import Foundation

// MARK: - Domain model

struct Notificacao {
    let id: String
    let titulo: String
    let mensagem: String?
    let tipo: String
    let lida: Bool
    let criadoEm: Date

    var criadoEmDisplay: String {
        Formatters.dateTime.string(from: criadoEm)
    }

    var tipoDisplay: String {
        switch tipo.uppercased() {
        case "CONTRATO": return "Contrato"
        case "DIVIDA": return "Dívida"
        case "PROMISSORIA": return "Promissória"
        case "VERIFICACAO": return "Verificação"
        case "PAGAMENTO": return "Pagamento"
        case "SISTEMA": return "Sistema"
        case "KYC": return "KYC"
        default: return tipo.capitalized
        }
    }
}

struct NotificacoesPage {
    let items: [Notificacao]
    let totalElements: Int
    let totalPages: Int
    let pageNumber: Int

    var isLast: Bool { totalPages <= 1 || pageNumber >= totalPages - 1 }
}

// MARK: - Service

final class NotificacoesService {

    private struct NotificacaoResponse: Decodable {
        let id: String
        let titulo: String
        let mensagem: String?
        let tipo: String
        let lida: Bool
        let criadoEm: String
    }

    private struct PageMetaResponse: Decodable {
        let number: Int?
        let totalElements: Int?
        let totalPages: Int?
    }

    private struct PaginatedResponse: Decodable {
        let content: [NotificacaoResponse]
        let page: PageMetaResponse?
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

    var isRemoteMode: Bool { mode == .remote }

    func fetchPage(page: Int = 0, size: Int = 20, apenasNaoLidas: Bool = false) async throws -> NotificacoesPage {
        var path = "\(APIRoutes.Notificacoes.base)?page=\(page)&size=\(size)&sort=criadoEm,desc"
        if apenasNaoLidas { path += "&lida=false" }
        let response: PaginatedResponse = try await apiClient.request(target: .backend, path: path)
        let items = response.content.compactMap { mapNotificacao($0) }
        let meta = response.page
        return NotificacoesPage(
            items: items,
            totalElements: meta?.totalElements ?? items.count,
            totalPages: meta?.totalPages ?? 1,
            pageNumber: meta?.number ?? page
        )
    }

    func fetchContagem() async throws -> Int {
        let count: Int = try await apiClient.request(target: .backend, path: APIRoutes.Notificacoes.contagem)
        return count
    }

    func marcarLida(id: String) async throws {
        try await apiClient.sendVoid(target: .backend, path: APIRoutes.Notificacoes.marcarLida(id), method: "PATCH")
    }

    func marcarNaoLida(id: String) async throws {
        try await apiClient.sendVoid(target: .backend, path: APIRoutes.Notificacoes.marcarNaoLida(id), method: "PATCH")
    }

    func marcarTodasLidas() async throws {
        try await apiClient.sendVoid(target: .backend, path: APIRoutes.Notificacoes.todasLidas, method: "PATCH")
    }

    func deletar(id: String) async throws {
        try await apiClient.sendVoid(target: .backend, path: APIRoutes.Notificacoes.byID(id), method: "DELETE")
    }

    // MARK: - Private

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoLocal: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private func parseDate(_ raw: String) -> Date? {
        Self.isoWithFraction.date(from: raw)
            ?? Self.iso.date(from: raw)
            ?? Self.isoLocal.date(from: raw)
    }

    private func mapNotificacao(_ raw: NotificacaoResponse) -> Notificacao? {
        guard let date = parseDate(raw.criadoEm) else { return nil }
        return Notificacao(
            id: raw.id,
            titulo: raw.titulo,
            mensagem: raw.mensagem,
            tipo: raw.tipo,
            lida: raw.lida,
            criadoEm: date
        )
    }
}
