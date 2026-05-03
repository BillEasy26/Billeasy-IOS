//
//  ConvitesService.swift
//  BillEasy
//

import Foundation

// MARK: - Domain models

struct ConvitePreview {
    let participanteID: String
    let origemTipo: String
    let contratoID: String?
    let contratoIDCurto: String?
    let promissoriaID: String?
    let promissoriaIDCurto: String?
    let papel: String
    let nomeCriador: String
    let nomeConvidado: String
    let documentoConvidado: String
    let emailConvidado: String
    let telefoneConvidado: String
    let valorMontante: Decimal
    let moeda: String
    let metodoPagamento: String
    let quantidadeParcelas: Int
    let primeiroVencimento: Date?
    let jaPossuiConta: Bool
    let jaAceito: Bool

    var tipoDisplay: String {
        switch origemTipo.uppercased() {
        case "CONTRATO": return "Convite para contrato"
        case "PROMISSORIA", "PROMISSÓRIA": return "Convite para promissória"
        default: return "Convite"
        }
    }

    var papelDisplay: String {
        switch papel.uppercased() {
        case "CREDOR": return "Credor"
        case "DEVEDOR": return "Devedor"
        case "EMISSOR": return "Emissor"
        case "BENEFICIARIO": return "Beneficiário"
        default: return papel.capitalized
        }
    }

    var documentoDisplay: String {
        Formatters.formatCPFOrCNPJ(documentoConvidado)
    }

    var valorDisplay: String {
        Formatters.currencyText(from: valorMontante)
    }

    var vencimentoDisplay: String {
        primeiroVencimento.map { Formatters.shortDate.string(from: $0) } ?? "Não informado"
    }

    var metodoPagamentoDisplay: String {
        switch metodoPagamento.uppercased() {
        case "PIX": return "Pix"
        case "BOLETO": return "Boleto"
        case "TED": return "TED"
        case "TRANSFERENCIA", "TRANSFERÊNCIA": return "Transferência"
        default: return metodoPagamento.capitalized
        }
    }

    var referenciaDisplay: String {
        if let promissoriaIDCurto, promissoriaIDCurto.isEmpty == false {
            return promissoriaIDCurto
        }
        if let contratoIDCurto, contratoIDCurto.isEmpty == false {
            return contratoIDCurto
        }
        if let promissoriaID, promissoriaID.isEmpty == false {
            return promissoriaID
        }
        if let contratoID, contratoID.isEmpty == false {
            return contratoID
        }
        return participanteID
    }

    var descricao: String {
        "\(nomeCriador) convidou você para participar como \(papelDisplay.lowercased()) em \(tipoDisplay.lowercased())."
    }
}

// MARK: - Service

final class ConvitesService {

    private struct ConvitePreviewResponse: Decodable {
        let participanteID: String
        let origemTipo: String
        let contratoID: String?
        let contratoIDCurto: String?
        let promissoriaID: String?
        let promissoriaIDCurto: String?
        let papel: String
        let nomeCriador: String
        let nomeConvidado: String
        let documentoConvidado: String
        let emailConvidado: String
        let telefoneConvidado: String
        let valorMontante: Decimal
        let moeda: String
        let metodoPagamento: String
        let quantidadeParcelas: Int
        let primeiroVencimento: String?
        let jaPossuiConta: Bool
        let jaAceito: Bool

        enum CodingKeys: String, CodingKey {
            case participanteID = "participanteId"
            case origemTipo
            case contratoID = "contratoId"
            case contratoIDCurto = "contratoIdCurto"
            case promissoriaID = "promissoriaId"
            case promissoriaIDCurto = "promissoriaIdCurto"
            case papel
            case nomeCriador
            case nomeConvidado
            case documentoConvidado
            case emailConvidado
            case telefoneConvidado
            case valorMontante
            case moeda
            case metodoPagamento
            case quantidadeParcelas
            case primeiroVencimento
            case jaPossuiConta
            case jaAceito
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            participanteID = container.decodeLossyString(forKey: .participanteID)
            origemTipo = container.decodeLossyString(forKey: .origemTipo)
            contratoID = container.decodeOptionalLossyString(forKey: .contratoID)
            contratoIDCurto = container.decodeOptionalLossyString(forKey: .contratoIDCurto)
            promissoriaID = container.decodeOptionalLossyString(forKey: .promissoriaID)
            promissoriaIDCurto = container.decodeOptionalLossyString(forKey: .promissoriaIDCurto)
            papel = container.decodeLossyString(forKey: .papel)
            nomeCriador = container.decodeLossyString(forKey: .nomeCriador)
            nomeConvidado = container.decodeLossyString(forKey: .nomeConvidado)
            documentoConvidado = container.decodeLossyString(forKey: .documentoConvidado)
            emailConvidado = container.decodeLossyString(forKey: .emailConvidado)
            telefoneConvidado = container.decodeLossyString(forKey: .telefoneConvidado)
            valorMontante = container.decodeLossyDecimal(forKey: .valorMontante) ?? .zero
            moeda = container.decodeLossyString(forKey: .moeda, defaultValue: "BRL")
            metodoPagamento = container.decodeLossyString(forKey: .metodoPagamento)
            quantidadeParcelas = container.decodeLossyInt(forKey: .quantidadeParcelas)
            primeiroVencimento = container.decodeOptionalLossyString(forKey: .primeiroVencimento)
            jaPossuiConta = container.decodeLossyBool(forKey: .jaPossuiConta)
            jaAceito = container.decodeLossyBool(forKey: .jaAceito)
        }
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

    func fetchPreview(token: String) async throws -> ConvitePreview {
        let raw: ConvitePreviewResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Convites.preview(token)
        )
        return mapPreview(raw)
    }

    func aceitar(token: String) async throws {
        try await apiClient.sendVoid(
            target: .backend,
            path: APIRoutes.Convites.aceitar(token),
            method: "POST"
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

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
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
            ?? Self.isoDate.date(from: raw)
    }

    private func mapPreview(_ raw: ConvitePreviewResponse) -> ConvitePreview {
        ConvitePreview(
            participanteID: raw.participanteID,
            origemTipo: raw.origemTipo,
            contratoID: raw.contratoID,
            contratoIDCurto: raw.contratoIDCurto,
            promissoriaID: raw.promissoriaID,
            promissoriaIDCurto: raw.promissoriaIDCurto,
            papel: raw.papel,
            nomeCriador: raw.nomeCriador,
            nomeConvidado: raw.nomeConvidado,
            documentoConvidado: raw.documentoConvidado,
            emailConvidado: raw.emailConvidado,
            telefoneConvidado: raw.telefoneConvidado,
            valorMontante: raw.valorMontante,
            moeda: raw.moeda,
            metodoPagamento: raw.metodoPagamento,
            quantidadeParcelas: raw.quantidadeParcelas,
            primeiroVencimento: parseDate(raw.primeiroVencimento),
            jaPossuiConta: raw.jaPossuiConta,
            jaAceito: raw.jaAceito
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key, defaultValue: String = "") -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return defaultValue
    }

    func decodeOptionalLossyString(forKey key: Key) -> String? {
        let value = decodeLossyString(forKey: key)
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    func decodeLossyDecimal(forKey key: Key) -> Decimal? {
        if let value = try? decode(Decimal.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Decimal(value) }
        if let value = try? decode(Int.self, forKey: key) { return Decimal(value) }
        if let value = try? decode(String.self, forKey: key) {
            return Formatters.decimalFromCurrencyString(value)
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key, defaultValue: Int = 0) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key), let intValue = Int(value) { return intValue }
        return defaultValue
    }

    func decodeLossyBool(forKey key: Key, defaultValue: Bool = false) -> Bool {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            return ["true", "1", "sim", "yes"].contains(value.lowercased())
        }
        return defaultValue
    }
}
