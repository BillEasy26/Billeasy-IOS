//
//  VerificacoesService.swift
//  BillEasy
//

import Foundation

// MARK: - Domain models

enum SituacaoVerificacao: String {
    case pendente          = "PENDENTE"
    case aguardandoSelfie  = "AGUARDANDO_SELFIE"
    case processando       = "PROCESSANDO"
    case aprovado          = "APROVADO"
    case reprovado         = "REPROVADO"
    case cancelado         = "CANCELADO"
    case unknown

    var displayTitle: String {
        switch self {
        case .pendente:         return "Pendente"
        case .aguardandoSelfie: return "Aguardando Selfie"
        case .processando:      return "Processando"
        case .aprovado:         return "Aprovado"
        case .reprovado:        return "Reprovado"
        case .cancelado:        return "Cancelado"
        case .unknown:          return "Desconhecida"
        }
    }

    var badgeColor: (background: String, text: String) {
        switch self {
        case .pendente:         return ("#E9EEF5", "#5A7291")
        case .aguardandoSelfie: return ("#FEF3C7", "#92400E")
        case .processando:      return ("#DBEAFE", "#1D4ED8")
        case .aprovado:         return ("#D1FAE5", "#065F46")
        case .reprovado:        return ("#FEE2E2", "#991B1B")
        case .cancelado:        return ("#F1F5F9", "#475569")
        case .unknown:          return ("#F1F5F9", "#475569")
        }
    }

    var needsSelfie: Bool {
        self == .aguardandoSelfie || self == .pendente
    }

    var isTerminal: Bool {
        self == .aprovado || self == .reprovado || self == .cancelado
    }
}

struct Verificacao {
    let id: String
    let nome: String?
    let documentoNumero: String?
    let documentoTipo: String?
    let situacao: SituacaoVerificacao
    let selfieCapturadoEm: Date?
    let solicitadoEm: Date?
    let resolvidoEm: Date?
    let resultadoScore: String?
    let resultadoScoreMinimo: String?
    let resultadoMatchDocumento: Bool?
    let resultadoMotivo: String?

    var nomeDisplay: String { nome ?? "Sem identificação" }

    var documentoDisplay: String? {
        guard let numero = documentoNumero, let tipo = documentoTipo else { return nil }
        switch tipo.uppercased() {
        case "CPF":  return Formatters.formatCPF(numero)
        case "CNPJ": return Formatters.formatCNPJ(numero)
        default:     return numero
        }
    }

    var solicitadoEmDisplay: String? {
        solicitadoEm.map { Formatters.shortDate.string(from: $0) }
    }

    var resolvidoEmDisplay: String? {
        resolvidoEm.map { Formatters.shortDate.string(from: $0) }
    }

    var scoreFormatado: String? {
        guard let score = resultadoScore, !score.isEmpty else { return nil }
        if let minimo = resultadoScoreMinimo, !minimo.isEmpty {
            return "\(score) / \(minimo)"
        }
        return score
    }
}

// MARK: - Service

final class VerificacoesService {

    private struct VerificacaoResponse: Decodable {
        let id: String
        let nome: String?
        let documentoNumero: String?
        let documentoTipo: String?
        let situacao: String
        let selfieCapturadoEm: String?
        let solicitadoEm: String?
        let resolvidoEm: String?
        let resultadoScore: String?
        let resultadoScoreMinimo: String?
        let resultadoMatchDocumento: Bool?
        let resultadoMotivo: String?
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

    func fetchMinhas() async throws -> [Verificacao] {
        let raw: [VerificacaoResponse] = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Verificacoes.me
        )
        return raw.map(mapVerificacao)
    }

    func fetchDetalhe(id: String) async throws -> Verificacao {
        let raw: VerificacaoResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Verificacoes.byID(id)
        )
        return mapVerificacao(raw)
    }

    func enviarSelfie(id: String, imageData: Data, filename: String = "selfie.jpg") async throws {
        struct EmptyResponse: Decodable {}
        let _: EmptyResponse = try await apiClient.upload(
            target: .backend,
            path: APIRoutes.Verificacoes.selfie(id),
            fileFieldName: "arquivo",
            fileData: imageData,
            filename: filename,
            mimeType: "image/jpeg",
            timeoutInterval: 60
        )
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

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return Self.isoWithFraction.date(from: raw)
            ?? Self.iso.date(from: raw)
            ?? Self.isoLocal.date(from: raw)
    }

    private func mapVerificacao(_ raw: VerificacaoResponse) -> Verificacao {
        Verificacao(
            id: raw.id,
            nome: raw.nome,
            documentoNumero: raw.documentoNumero,
            documentoTipo: raw.documentoTipo,
            situacao: SituacaoVerificacao(rawValue: raw.situacao) ?? .unknown,
            selfieCapturadoEm: parseDate(raw.selfieCapturadoEm),
            solicitadoEm: parseDate(raw.solicitadoEm),
            resolvidoEm: parseDate(raw.resolvidoEm),
            resultadoScore: raw.resultadoScore,
            resultadoScoreMinimo: raw.resultadoScoreMinimo,
            resultadoMatchDocumento: raw.resultadoMatchDocumento,
            resultadoMotivo: raw.resultadoMotivo
        )
    }
}
