//
//  PromissoriasService.swift
//  BillEasy
//

import Foundation

// MARK: - Domain models

enum EtapaPromissoria: String, Decodable {
    case rascunho             = "RASCUNHO"
    case aguardandoKyc        = "AGUARDANDO_KYC"
    case aguardandoAssinaturas = "AGUARDANDO_ASSINATURAS"
    case emitida              = "EMITIDA"
    case cancelada            = "CANCELADA"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EtapaPromissoria(rawValue: raw) ?? .unknown
    }

    var displayTitle: String {
        switch self {
        case .rascunho:              return "Rascunho"
        case .aguardandoKyc:         return "Aguardando KYC"
        case .aguardandoAssinaturas: return "Aguardando Assinaturas"
        case .emitida:               return "Emitida"
        case .cancelada:             return "Cancelada"
        case .unknown:               return "Desconhecida"
        }
    }

    var badgeColor: (background: String, text: String) {
        switch self {
        case .rascunho:              return ("#E9EEF5", "#5A7291")
        case .aguardandoKyc:         return ("#FEF3C7", "#92400E")
        case .aguardandoAssinaturas: return ("#DBEAFE", "#1D4ED8")
        case .emitida:               return ("#D1FAE5", "#065F46")
        case .cancelada:             return ("#FEE2E2", "#991B1B")
        case .unknown:               return ("#F1F5F9", "#475569")
        }
    }

    var canIniciarKyc: Bool        { self == .rascunho }
    var canEnviarAssinatura: Bool  { self == .aguardandoKyc }
    var canCancelar: Bool          { self == .rascunho || self == .aguardandoKyc || self == .aguardandoAssinaturas }
    var hasDocumento: Bool         { self == .aguardandoAssinaturas || self == .emitida }
}

struct PartePromissoria {
    let id: String
    let papel: String
    let nome: String
    let documentoNumero: String
    let documentoTipo: String
    let email: String
    let telefone: String
    let kycAprovado: Bool
    let kycVerificacaoId: String?
    let assinadoEm: Date?

    var papelDisplay: String {
        switch papel.uppercased() {
        case "EMISSOR":      return "Emissor"
        case "BENEFICIARIO": return "Beneficiário"
        default:             return papel.capitalized
        }
    }

    var documentoFormatado: String {
        switch documentoTipo.uppercased() {
        case "CPF":  return Formatters.formatCPF(documentoNumero)
        case "CNPJ": return Formatters.formatCNPJ(documentoNumero)
        default:     return documentoNumero
        }
    }
}

struct Promissoria {
    let id: String
    let etapa: EtapaPromissoria
    let valorMontante: Decimal
    let metodoPagamento: String
    let quantidadeParcelas: Int
    let primeiroVencimento: Date
    let jurosMensalPercent: Decimal
    let multaAtrasoPercent: Decimal
    let partes: [PartePromissoria]
    let criadoEm: Date?
    let canceladoEm: Date?
    let motivoCancelamento: String?
    let documentoGeradoEm: Date?

    var valorDisplay: String { Formatters.currencyText(from: valorMontante) }

    var primeiroVencimentoDisplay: String {
        Formatters.shortDate.string(from: primeiroVencimento)
    }

    var emissor: PartePromissoria?  { partes.first { $0.papel.uppercased() == "EMISSOR" } }
    var beneficiario: PartePromissoria? { partes.first { $0.papel.uppercased() == "BENEFICIARIO" } }

    var metodoPagamentoDisplay: String {
        switch metodoPagamento.uppercased() {
        case "PIX":              return "Pix"
        case "BOLETO":           return "Boleto"
        case "TRANSFERENCIA":    return "Transferência"
        case "DINHEIRO":         return "Dinheiro"
        default:                 return metodoPagamento.capitalized
        }
    }
}

struct PromissoriaParteInput {
    let nome: String
    let documento: String
    let email: String
    let telefone: String
    let cep: String
    let numero: String
    let complemento: String?
    let chavePix: String?
    let banco: String?
    let agencia: String?
    let conta: String?
    let tipoConta: String?
}

struct CriarPromissoriaInput {
    let valorMontante: Decimal
    let metodoPagamento: String
    let quantidadeParcelas: Int
    let primeiroVencimento: Date
    let jurosMensalPercent: Decimal
    let multaAtrasoPercent: Decimal
    let emissor: PromissoriaParteInput
    let beneficiario: PromissoriaParteInput
}

// MARK: - Service

final class PromissoriasService {

    private struct PromissoriaResponse: Decodable {
        struct ParteResponse: Decodable {
            let id: String
            let papel: String
            let nome: String
            let documentoNumero: String
            let documentoTipo: String
            let email: String
            let telefone: String
            let kycAprovado: Bool
            let kycVerificacaoId: String?
            let assinadoEm: String?
        }
        let id: String
        let etapa: String
        let valorMontante: String
        let metodoPagamento: String
        let quantidadeParcelas: Int
        let primeiroVencimento: String
        let jurosMensalPercent: String
        let multaAtrasoPercent: String
        let partes: [ParteResponse]
        let criadoEm: String?
        let canceladoEm: String?
        let motivoCancelamento: String?
        let documentoGeradoEm: String?
    }

    private struct CriarResponse: Decodable {
        let id: String
    }

    private struct CriarPromissoriaRequest: Encodable {
        let valor: String
        let metodoPagamento: String
        let quantidadeParcelas: Int
        let primeiroVencimento: String
        let jurosMensalPercent: String?
        let multaAtrasoPercent: String?
        let emissor: ParteEmissorRequest
        let beneficiario: ParteBeneficiarioRequest
    }

    private struct ParteEmissorRequest: Encodable {
        let nome: String
        let documento: String
        let email: String
        let telefone: String
        let cep: String
        let numero: String
        let complemento: String?
    }

    private struct ParteBeneficiarioRequest: Encodable {
        let nome: String
        let documento: String
        let email: String
        let telefone: String
        let cep: String
        let numero: String
        let complemento: String?
        let chavePix: String?
        let banco: String?
        let agencia: String?
        let conta: String?
        let tipoConta: String?
    }

    private struct CancelarRequest: Encodable {
        let motivo: String
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

    func fetchMinhas() async throws -> [Promissoria] {
        let raw: [PromissoriaResponse] = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Promissorias.me
        )
        return raw.compactMap(mapPromissoria)
    }

    func fetchDetalhe(id: String) async throws -> Promissoria {
        let raw: PromissoriaResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Promissorias.byID(id)
        )
        guard let promissoria = mapPromissoria(raw) else {
            throw RemoteAPIClientError.invalidResponse
        }
        return promissoria
    }

    func baixarDocumento(id: String) async throws -> Data {
        try await apiClient.download(
            target: .backend,
            path: APIRoutes.Promissorias.documento(id)
        )
    }

    func criar(input: CriarPromissoriaInput) async throws -> String {
        let request = CriarPromissoriaRequest(
            valor: decimalString(input.valorMontante),
            metodoPagamento: input.metodoPagamento,
            quantidadeParcelas: input.quantidadeParcelas,
            primeiroVencimento: Self.isoDate.string(from: input.primeiroVencimento),
            jurosMensalPercent: optionalPercentString(input.jurosMensalPercent),
            multaAtrasoPercent: optionalPercentString(input.multaAtrasoPercent),
            emissor: ParteEmissorRequest(
                nome: input.emissor.nome,
                documento: Formatters.digitsOnly(input.emissor.documento),
                email: input.emissor.email,
                telefone: Formatters.digitsOnly(input.emissor.telefone),
                cep: Formatters.digitsOnly(input.emissor.cep),
                numero: input.emissor.numero,
                complemento: trimmedOptional(input.emissor.complemento)
            ),
            beneficiario: ParteBeneficiarioRequest(
                nome: input.beneficiario.nome,
                documento: Formatters.digitsOnly(input.beneficiario.documento),
                email: input.beneficiario.email,
                telefone: Formatters.digitsOnly(input.beneficiario.telefone),
                cep: Formatters.digitsOnly(input.beneficiario.cep),
                numero: input.beneficiario.numero,
                complemento: trimmedOptional(input.beneficiario.complemento),
                chavePix: trimmedOptional(input.beneficiario.chavePix),
                banco: trimmedOptional(input.beneficiario.banco),
                agencia: trimmedOptional(input.beneficiario.agencia),
                conta: trimmedOptional(input.beneficiario.conta),
                tipoConta: trimmedOptional(input.beneficiario.tipoConta)
            )
        )

        let response: CriarResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Promissorias.base,
            method: "POST",
            body: request
        )
        return response.id
    }

    func iniciarKyc(id: String) async throws {
        try await apiClient.sendVoid(
            target: .backend,
            path: APIRoutes.Promissorias.iniciarKyc(id),
            method: "POST"
        )
    }

    func enviarParaAssinatura(id: String) async throws {
        try await apiClient.sendVoid(
            target: .backend,
            path: APIRoutes.Promissorias.enviarParaAssinatura(id),
            method: "POST"
        )
    }

    func cancelar(id: String, motivo: String) async throws {
        try await apiClient.sendVoid(
            target: .backend,
            path: APIRoutes.Promissorias.cancelar(id),
            method: "POST",
            body: CancelarRequest(motivo: motivo)
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

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func optionalPercentString(_ value: Decimal) -> String? {
        value == .zero ? nil : decimalString(value)
    }

    private func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapPromissoria(_ raw: PromissoriaResponse) -> Promissoria? {
        guard let vencimento = parseDate(raw.primeiroVencimento) else { return nil }
        let partes = raw.partes.map { p in
            PartePromissoria(
                id: p.id,
                papel: p.papel,
                nome: p.nome,
                documentoNumero: p.documentoNumero,
                documentoTipo: p.documentoTipo,
                email: p.email,
                telefone: p.telefone,
                kycAprovado: p.kycAprovado,
                kycVerificacaoId: p.kycVerificacaoId,
                assinadoEm: parseDate(p.assinadoEm)
            )
        }
        return Promissoria(
            id: raw.id,
            etapa: EtapaPromissoria(rawValue: raw.etapa) ?? .unknown,
            valorMontante: Formatters.decimalFromCurrencyString(raw.valorMontante) ?? .zero,
            metodoPagamento: raw.metodoPagamento,
            quantidadeParcelas: raw.quantidadeParcelas,
            primeiroVencimento: vencimento,
            jurosMensalPercent: Formatters.decimalFromCurrencyString(raw.jurosMensalPercent) ?? .zero,
            multaAtrasoPercent: Formatters.decimalFromCurrencyString(raw.multaAtrasoPercent) ?? .zero,
            partes: partes,
            criadoEm: parseDate(raw.criadoEm),
            canceladoEm: parseDate(raw.canceladoEm),
            motivoCancelamento: raw.motivoCancelamento,
            documentoGeradoEm: parseDate(raw.documentoGeradoEm)
        )
    }
}
