//
//  PortalPrivacyService.swift
//  BillEasy
//

import Foundation

/// Aqui eu concentro os fluxos remotos de LGPD para a UI não conhecer detalhes de rota ou arquivo temporário.
enum PortalPrivacyServiceError: LocalizedError {
    case integrationUnavailable

    var errorDescription: String? {
        switch self {
        case .integrationUnavailable:
            return "As ações de privacidade remota estão disponíveis apenas no modo autenticado."
        }
    }
}

final class PortalPrivacyService {
    struct MyDataExport: Decodable {
        struct PersonalData: Decodable {
            let nome: String?
            let email: String?
            let telefone: String?
            let cpfCnpjEnc: String?
            let status: String?
            let mfaHabilitado: Bool?
            let criadoEm: Date?
            let atualizadoEm: Date?
        }

        struct CompanySummary: Decodable {
            let id: String?
            let nome: String?
            let cpfCnpj: String?
            let tipo: String?
        }

        struct AuditEvent: Decodable {
            let acao: String?
            let entidade: String?
            let ip: String?
            let data: Date?
        }

        let dataExportacao: Date?
        let usuarioId: String?
        let dadosPessoais: PersonalData?
        let papeis: [String]?
        let permissoes: [String]?
        let empresas: [CompanySummary]?
        let historicoAuditoria: [AuditEvent]?
    }

    struct AnonymizationResult: Decodable {
        let sucesso: Bool?
        let mensagem: String?
    }

    private struct AnonymizeRequest: Encodable {
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

    var isRemoteMode: Bool {
        mode == .remote
    }

    /// Aqui eu leio o payload estruturado de LGPD para o preview no app, como a versão web já faz.
    func fetchMyData() async throws -> MyDataExport {
        guard isRemoteMode else {
            throw PortalPrivacyServiceError.integrationUnavailable
        }

        return try await apiClient.request(
            target: .backend,
            path: APIRoutes.LGPD.meusDados
        )
    }

    /// Aqui eu baixo o JSON LGPD do backend e devolvo uma URL temporária pronta para preview/compartilhamento.
    func downloadMyData() async throws -> URL {
        guard isRemoteMode else {
            throw PortalPrivacyServiceError.integrationUnavailable
        }

        let data = try await apiClient.download(
            target: .backend,
            path: APIRoutes.LGPD.downloadMeusDados
        )

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meus-dados-lgpd")
            .appendingPathExtension("json")

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Aqui eu anonimizo a conta autenticada usando o mesmo endpoint exposto pelo web.
    func anonymizeMyAccount(reason: String) async throws -> AnonymizationResult {
        guard isRemoteMode else {
            throw PortalPrivacyServiceError.integrationUnavailable
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await apiClient.request(
            target: .backend,
            path: APIRoutes.LGPD.anonimizarMinhaConta,
            method: "DELETE",
            body: AnonymizeRequest(
                motivo: trimmedReason.isEmpty ? "Solicitação do titular" : trimmedReason
            )
        )
    }
}
