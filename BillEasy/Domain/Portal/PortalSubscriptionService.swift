import CoreGraphics
import Foundation

/// Aqui eu descrevo um plano de assinatura exatamente no recorte que a UI do iOS consome.
struct PortalSubscriptionPlan {
    let id: String
    let name: String
    let slug: String
    let type: String
    let monthlyPrice: Decimal
    let maxContracts: Int
    let maxDebtorQueries: Int
    let trialDays: Int
    let allowsAddons: Bool

    var isFree: Bool {
        type.uppercased() == "FREE"
    }

    var isStandard: Bool {
        type.uppercased() == "STANDARD"
    }
}

/// Aqui eu mantenho o addon comprado já normalizado para cards e badges de status.
struct PortalSubscriptionAddon {
    let id: String
    let addonType: String
    let quantity: Int
    let unitPrice: Decimal
    let isActive: Bool
    let paymentStatus: String
    let availableQuantity: Int
    let consumedQuantity: Int
    let gatewayPaymentID: String?

    var label: String {
        switch addonType.uppercased() {
        case "ADDON_CONTRACT":
            return "Contrato Extra"
        case "ADDON_DEBTOR_QUERY":
            return "Consulta Extra"
        default:
            return addonType
        }
    }
}

/// Aqui eu centralizo o resumo de cota já pronto para a UI desenhar progresso e badge.
struct PortalQuotaSnapshot {
    let label: String
    let used: Int
    let limit: Int

    var progressFraction: CGFloat {
        guard limit > 0 else { return 1 }
        return CGFloat(min(Double(used) / Double(limit), 1))
    }

    var progressState: PortalQuotaProgressState {
        guard limit > 0 else { return .critical }
        let fraction = Double(used) / Double(limit)
        switch fraction {
        case 1...:
            return .critical
        case 0.8...:
            return .warning
        default:
            return .normal
        }
    }
}

enum PortalQuotaProgressState {
    case normal
    case warning
    case critical
}

/// Aqui eu exponho a assinatura atual já consolidada, com plano, cotas e addons.
struct PortalSubscriptionSnapshot {
    let id: String
    let plan: PortalSubscriptionPlan
    let status: String
    let billingProvider: String?
    let trialEndsAt: Date?
    let cycleStartsAt: Date?
    let cycleEndsAt: Date?
    let contractsUsed: Int
    let debtorQueriesUsed: Int
    let contractLimit: Int
    let debtorQueryLimit: Int
    let addons: [PortalSubscriptionAddon]
    let createdAt: Date?
    let updatedAt: Date?

    var contractQuota: PortalQuotaSnapshot {
        PortalQuotaSnapshot(label: "Contratos", used: contractsUsed, limit: contractLimit)
    }

    var debtorQueryQuota: PortalQuotaSnapshot {
        PortalQuotaSnapshot(label: "Consultas de Devedor", used: debtorQueriesUsed, limit: debtorQueryLimit)
    }

    var statusTitle: String {
        switch status.uppercased() {
        case "ATIVA":
            return "Ativo"
        case "TRIAL":
            return "Trial"
        case "INADIMPLENTE":
            return "Inadimplente"
        case "CANCELADA":
            return "Cancelada"
        case "EXPIRADA":
            return "Expirada"
        default:
            return status.capitalized
        }
    }

    var isFreePlan: Bool {
        plan.isFree
    }

    var isStandardPlan: Bool {
        plan.isStandard
    }

}

/// Aqui eu junto assinatura atual e catálogo de planos para a tela decidir banners e formulário.
struct PortalSubscriptionDashboard {
    let current: PortalSubscriptionSnapshot
    let availablePlans: [PortalSubscriptionPlan]

    var standardPlan: PortalSubscriptionPlan? {
        availablePlans.first(where: { $0.isStandard })
    }
}

enum PortalSubscriptionServiceError: LocalizedError {
    case integrationUnavailable

    var errorDescription: String? {
        switch self {
        case .integrationUnavailable:
            return "As assinaturas remotas estão disponíveis apenas para contas autenticadas no backend."
        }
    }
}

/// Aqui eu concentro a leitura e as ações de assinatura para a UI não conhecer payloads, rotas nem fallback local.
final class PortalSubscriptionService {
    private nonisolated struct PlanResponse: Decodable {
        let id: String
        let nome: String?
        let slug: String?
        let tipo: String?
        let precoMensal: Decimal?
        let maxContratos: Int?
        let maxConsultasDevedor: Int?
        let trialDias: Int?
        let permiteAddons: Bool?
    }

    private nonisolated struct AddonResponse: Decodable {
        let id: String
        let tipoAddon: String?
        let quantidade: Int?
        let precoUnitario: Decimal?
        let ativo: Bool?
        let statusPagamento: String?
        let quantidadeDisponivel: Int?
        let quantidadeConsumida: Int?
        let gatewayPagamentoId: String?
    }

    private nonisolated struct SubscriptionResponse: Decodable {
        let id: String
        let plano: PlanResponse
        let status: String?
        let billingProvider: String?
        let trialFimEm: String?
        let cicloInicioEm: String?
        let cicloFimEm: String?
        let contratosUtilizados: Int?
        let consultasUtilizadasCiclo: Int?
        let limiteContratosEfetivo: Int?
        let limiteConsultasEfetivo: Int?
        let addons: [AddonResponse]?
        let criadoEm: String?
        let atualizadoEm: String?
    }

    private nonisolated struct QuotaResponse: Decodable {
        let limiteContratos: Int?
        let contratosUtilizados: Int?
        let creditosContratoAddon: Int?
        let limiteConsultas: Int?
        let consultasUtilizadas: Int?
        let creditosConsultaAddon: Int?
        let tipoPlano: String?
        let statusAssinatura: String?
    }

    private let apiClient: RemoteAPIClient
    private let mode: AppAuthMode
    private let dataStore: LocalAppDataStore

    init(
        apiClient: RemoteAPIClient = RemoteAPIClient(),
        mode: AppAuthMode = AppRuntimeConfiguration.authMode,
        dataStore: LocalAppDataStore
    ) {
        self.apiClient = apiClient
        self.mode = mode
        self.dataStore = dataStore
    }

    var isRemoteMode: Bool {
        mode == .remote
    }

    /// Aqui eu carrego a assinatura atual e o catálogo de planos no mesmo passo para a tela nascer completa.
    func fetchDashboard() async throws -> PortalSubscriptionDashboard {
        guard isRemoteMode else {
            return makeLocalDashboard()
        }

        async let plansTask: [PlanResponse] = apiClient.request(
            target: .backend,
            path: APIRoutes.Planos.base
        )
        async let subscriptionTask: SubscriptionResponse = apiClient.request(
            target: .backend,
            path: APIRoutes.Assinaturas.minha
        )
        async let quotaTask: QuotaResponse? = try? apiClient.request(
            target: .backend,
            path: APIRoutes.Assinaturas.minhasCotas
        )

        let plans = try await plansTask.map(makePlan(from:))
        let subscription = try await subscriptionTask
        let quota = await quotaTask

        return PortalSubscriptionDashboard(
            current: makeSubscription(from: subscription, quota: quota),
            availablePlans: plans
        )
    }

    /// Aqui eu exponho o catálogo completo porque outras telas podem querer detalhar o plano Standard depois.
    func fetchPlans() async throws -> [PortalSubscriptionPlan] {
        guard isRemoteMode else {
            return makeLocalPlans()
        }

        let response: [PlanResponse] = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Planos.base
        )
        return response.map(makePlan(from:))
    }

    /// Aqui eu deixo pronto o fetch por id, mesmo que a primeira tela não use isso ainda.
    func fetchPlan(id: String) async throws -> PortalSubscriptionPlan {
        guard isRemoteMode else {
            throw PortalSubscriptionServiceError.integrationUnavailable
        }

        let response: PlanResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Planos.byID(id)
        )
        return makePlan(from: response)
    }

    private func fetchQuotaResponse() async throws -> QuotaResponse {
        try await apiClient.request(
            target: .backend,
            path: APIRoutes.Assinaturas.minhasCotas
        )
    }

    /// Aqui eu monto um fallback local previsível para desenvolvimento e para quando o app estiver em modo local.
    private func makeLocalDashboard() -> PortalSubscriptionDashboard {
        let plans = makeLocalPlans()
        let freePlan = plans.first(where: { $0.isFree }) ?? PortalSubscriptionPlan(
            id: "local-free",
            name: "Free",
            slug: "free",
            type: "FREE",
            monthlyPrice: .zero,
            maxContracts: 3,
            maxDebtorQueries: 1,
            trialDays: 0,
            allowsAddons: false
        )

        let subscription = PortalSubscriptionSnapshot(
            id: "local-subscription",
            plan: freePlan,
            status: "ATIVA",
            billingProvider: nil,
            trialEndsAt: nil,
            cycleStartsAt: nil,
            cycleEndsAt: nil,
            contractsUsed: dataStore.fetchContracts().count,
            debtorQueriesUsed: 0,
            contractLimit: freePlan.maxContracts,
            debtorQueryLimit: freePlan.maxDebtorQueries,
            addons: [],
            createdAt: nil,
            updatedAt: nil
        )

        return PortalSubscriptionDashboard(current: subscription, availablePlans: plans)
    }

    private func makeLocalPlans() -> [PortalSubscriptionPlan] {
        [
            PortalSubscriptionPlan(
                id: "local-free",
                name: "Free",
                slug: "free",
                type: "FREE",
                monthlyPrice: .zero,
                maxContracts: 3,
                maxDebtorQueries: 1,
                trialDays: 0,
                allowsAddons: false
            ),
            PortalSubscriptionPlan(
                id: "local-standard",
                name: "Standard",
                slug: "standard",
                type: "STANDARD",
                monthlyPrice: Decimal(string: "19.90") ?? .zero,
                maxContracts: 10,
                maxDebtorQueries: 2,
                trialDays: 7,
                allowsAddons: true
            )
        ]
    }

    private func makePlan(from response: PlanResponse) -> PortalSubscriptionPlan {
        PortalSubscriptionPlan(
            id: response.id,
            name: nonEmpty(response.nome) ?? "Plano",
            slug: nonEmpty(response.slug) ?? response.id,
            type: nonEmpty(response.tipo) ?? "FREE",
            monthlyPrice: response.precoMensal ?? .zero,
            maxContracts: response.maxContratos ?? 0,
            maxDebtorQueries: response.maxConsultasDevedor ?? 0,
            trialDays: response.trialDias ?? 0,
            allowsAddons: response.permiteAddons ?? false
        )
    }

    private func makeSubscription(from response: SubscriptionResponse, quota: QuotaResponse?) -> PortalSubscriptionSnapshot {
        let mappedPlan = makePlan(from: response.plano)
        let contractLimit = quota.flatMap { quotaValue in
            let base = quotaValue.limiteContratos ?? 0
            let addon = quotaValue.creditosContratoAddon ?? 0
            return max(base + addon, response.limiteContratosEfetivo ?? 0)
        } ?? response.limiteContratosEfetivo ?? mappedPlan.maxContracts

        let debtorQueryLimit = quota.flatMap { quotaValue in
            let base = quotaValue.limiteConsultas ?? 0
            let addon = quotaValue.creditosConsultaAddon ?? 0
            return max(base + addon, response.limiteConsultasEfetivo ?? 0)
        } ?? response.limiteConsultasEfetivo ?? mappedPlan.maxDebtorQueries

        return PortalSubscriptionSnapshot(
            id: response.id,
            plan: mappedPlan,
            status: nonEmpty(quota?.statusAssinatura) ?? nonEmpty(response.status) ?? "ATIVA",
            billingProvider: nonEmpty(response.billingProvider),
            trialEndsAt: parseDate(response.trialFimEm),
            cycleStartsAt: parseDate(response.cicloInicioEm),
            cycleEndsAt: parseDate(response.cicloFimEm),
            contractsUsed: quota?.contratosUtilizados ?? response.contratosUtilizados ?? 0,
            debtorQueriesUsed: quota?.consultasUtilizadas ?? response.consultasUtilizadasCiclo ?? 0,
            contractLimit: contractLimit,
            debtorQueryLimit: debtorQueryLimit,
            addons: (response.addons ?? []).map(makeAddon(from:)),
            createdAt: parseDate(response.criadoEm),
            updatedAt: parseDate(response.atualizadoEm)
        )
    }

    private func makeAddon(from response: AddonResponse) -> PortalSubscriptionAddon {
        PortalSubscriptionAddon(
            id: response.id,
            addonType: nonEmpty(response.tipoAddon) ?? "ADDON",
            quantity: response.quantidade ?? 0,
            unitPrice: response.precoUnitario ?? .zero,
            isActive: response.ativo ?? true,
            paymentStatus: nonEmpty(response.statusPagamento) ?? "DESCONHECIDO",
            availableQuantity: response.quantidadeDisponivel ?? 0,
            consumedQuantity: response.quantidadeConsumida ?? 0,
            gatewayPaymentID: nonEmpty(response.gatewayPagamentoId)
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value = nonEmpty(value) else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]
        if let date = fallbackISOFormatter.date(from: value) {
            return date
        }

        return Formatters.shortDate.date(from: value) ?? Formatters.fullNumericDate.date(from: value)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
