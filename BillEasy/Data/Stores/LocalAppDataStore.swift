//
//  LocalAppDataStore.swift
//  BillEasy
//

import Foundation

enum DebtStatus: String, Codable, CaseIterable {
    case pendente
    case vencida
    case negociada
    case parcial
    case paga
    case cancelada

    var displayName: String {
        switch self {
        case .pendente: return "Pendente"
        case .vencida: return "Vencida"
        case .negociada: return "Negociada"
        case .parcial: return "Parcial"
        case .paga: return "Paga"
        case .cancelada: return "Cancelada"
        }
    }
}

enum ContractStatus: String, Codable, CaseIterable {
    case rascunho
    case aguardandoAssinatura
    case assinado
    case cancelado

    var displayName: String {
        switch self {
        case .rascunho: return "Rascunho"
        case .aguardandoAssinatura: return "Aguardando assinatura"
        case .assinado: return "Assinado"
        case .cancelado: return "Cancelado"
        }
    }
}

enum PaymentStatus: String, Codable, CaseIterable {
    case processando
    case confirmado
    case falhou

    var displayName: String {
        switch self {
        case .processando: return "Processando"
        case .confirmado: return "Confirmado"
        case .falhou: return "Falhou"
        }
    }
}

struct DashboardSummary {
    let totalUsuarios: Int
    let totalEmpresas: Int
    let totalDevedores: Int
    let totalDividas: Int
    let totalContratos: Int
    let totalPagamentos: Int
    let valorEmAberto: Decimal
}

struct UserItem: Codable {
    let id: String
    var nome: String
    var email: String
    var papel: String
    var ativo: Bool
}

struct CompanyItem: Codable {
    let id: String
    var nome: String
    var documento: String
    var telefone: String
    var ativa: Bool
    var tipo: String?
    var status: String?
    var addressSummary: String?
    var responsibleName: String?
}

struct DebtorItem: Codable {
    let id: String
    var nome: String
    var cpfCnpj: String
    var email: String
    var telefone: String
    var status: String
    var companyID: String?
    var companyName: String?
    var addressSummary: String?
}

struct DebtItem: Codable {
    let id: String
    var titulo: String
    var devedorNome: String
    var valor: Decimal
    var vencimento: Date
    var status: DebtStatus
    var contractID: String? = nil
    var firstInstallmentID: String? = nil
    var debtorDocument: String? = nil
}

struct ContractItem: Codable {
    let id: String
    var titulo: String
    var devedorNome: String
    var valor: Decimal
    var status: ContractStatus
    var updatedAt: Date
}

struct PaymentItem: Codable {
    let id: String
    var referencia: String
    var metodo: String
    var valor: Decimal
    var status: PaymentStatus
    var createdAt: Date
}

struct AuditItem: Codable {
    let id: String
    var acao: String
    var modulo: String
    var usuario: String
    var createdAt: Date
}

struct PrivacySettings: Codable {
    var marketingEmailsEnabled: Bool
    var dataExportRequestedAt: Date?
}

struct SecuritySettings: Codable {
    var mfaEnabled: Bool
    var biometricEnabled: Bool
    var lastPasswordChangeAt: Date
}

private struct LocalAppSnapshot: Codable {
    var users: [UserItem]
    var companies: [CompanyItem]
    var debtors: [DebtorItem]
    var debts: [DebtItem]
    var contracts: [ContractItem]
    var payments: [PaymentItem]
    var audit: [AuditItem]
    var privacy: PrivacySettings
    var security: SecuritySettings
}

final class LocalAppDataStore {
    private let defaults: UserDefaults
    private let authStore: LocalAuthStore
    private let keyPrefix = "billeasy.local.app.snapshot.v2"

    init(defaults: UserDefaults = .standard, authStore: LocalAuthStore = LocalAuthStore()) {
        self.defaults = defaults
        self.authStore = authStore
    }

    // MARK: - Dashboard

    func dashboardSummary() -> DashboardSummary {
        let snapshot = loadSnapshot()
        let openValue = snapshot.debts
            .filter { $0.status != .paga && $0.status != .cancelada }
            .reduce(Decimal.zero) { $0 + $1.valor }

        return DashboardSummary(
            totalUsuarios: snapshot.users.count,
            totalEmpresas: snapshot.companies.count,
            totalDevedores: snapshot.debtors.count,
            totalDividas: snapshot.debts.count,
            totalContratos: snapshot.contracts.count,
            totalPagamentos: snapshot.payments.count,
            valorEmAberto: openValue
        )
    }

    // MARK: - Users

    func fetchUsers() -> [UserItem] {
        loadSnapshot().users.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    func toggleUserStatus(userID: String) {
        var snapshot = loadSnapshot()
        guard let index = snapshot.users.firstIndex(where: { $0.id == userID }) else { return }
        snapshot.users[index].ativo.toggle()
        appendAudit(action: snapshot.users[index].ativo ? "ativar_usuario" : "bloquear_usuario", module: "usuarios", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    // MARK: - Companies

    func fetchCompanies() -> [CompanyItem] {
        loadSnapshot().companies.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    @discardableResult
    func updateCompanyLifecycle(companyID: String, isActive: Bool, status: String, auditAction: String) -> CompanyItem? {
        var snapshot = loadSnapshot()
        guard let index = snapshot.companies.firstIndex(where: { $0.id == companyID }) else { return nil }
        snapshot.companies[index].ativa = isActive
        snapshot.companies[index].status = status
        appendAudit(action: auditAction, module: "empresas", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
        return snapshot.companies[index]
    }

    @discardableResult
    func upsertCompany(
        id: String? = nil,
        name: String,
        document: String,
        phone: String,
        isActive: Bool = true,
        type: String? = nil,
        status: String? = nil,
        addressSummary: String? = nil,
        responsibleName: String? = nil
    ) -> CompanyItem? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDocument = document.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddress = addressSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedResponsible = responsibleName?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty || !normalizedDocument.isEmpty || !normalizedPhone.isEmpty else {
            return nil
        }

        var snapshot = loadSnapshot()
        let existingIndex = snapshot.companies.firstIndex { item in
            if let id, item.id == id { return true }
            return (!normalizedDocument.isEmpty && item.documento == normalizedDocument)
                || (!normalizedName.isEmpty && item.nome.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame)
        }

        if let existingIndex {
            snapshot.companies[existingIndex].nome = normalizedName.isEmpty ? snapshot.companies[existingIndex].nome : normalizedName
            snapshot.companies[existingIndex].documento = normalizedDocument.isEmpty ? snapshot.companies[existingIndex].documento : normalizedDocument
            snapshot.companies[existingIndex].telefone = normalizedPhone.isEmpty ? snapshot.companies[existingIndex].telefone : normalizedPhone
            snapshot.companies[existingIndex].ativa = isActive
            snapshot.companies[existingIndex].tipo = type ?? snapshot.companies[existingIndex].tipo
            snapshot.companies[existingIndex].status = status ?? snapshot.companies[existingIndex].status
            snapshot.companies[existingIndex].addressSummary = normalizedAddress ?? snapshot.companies[existingIndex].addressSummary
            snapshot.companies[existingIndex].responsibleName = normalizedResponsible ?? snapshot.companies[existingIndex].responsibleName
            appendAudit(action: "atualizar_empresa", module: "empresas", user: "local", snapshot: &snapshot)
            saveSnapshot(snapshot)
            return snapshot.companies[existingIndex]
        }

        let company = CompanyItem(
            id: id ?? UUID().uuidString,
            nome: normalizedName.isEmpty ? "Empresa sem nome" : normalizedName,
            documento: normalizedDocument,
            telefone: normalizedPhone,
            ativa: isActive,
            tipo: type,
            status: status,
            addressSummary: normalizedAddress,
            responsibleName: normalizedResponsible
        )

        snapshot.companies.insert(company, at: 0)
        appendAudit(action: "criar_empresa", module: "empresas", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
        return company
    }

    // MARK: - Debtors

    func fetchDebtors() -> [DebtorItem] {
        loadSnapshot().debtors.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    @discardableResult
    func updateDebtorLifecycle(debtorID: String, status: String, auditAction: String) -> DebtorItem? {
        var snapshot = loadSnapshot()
        guard let index = snapshot.debtors.firstIndex(where: { $0.id == debtorID }) else { return nil }
        snapshot.debtors[index].status = status
        appendAudit(action: auditAction, module: "devedores", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
        return snapshot.debtors[index]
    }

    func upsertDebtor(name: String, document: String, email: String, phone: String) {
        _ = upsertDebtor(
            id: nil,
            name: name,
            document: document,
            email: email,
            phone: phone
        )
    }

    @discardableResult
    func upsertDebtor(
        id: String? = nil,
        name: String,
        document: String,
        email: String,
        phone: String,
        status: String = "Ativo",
        companyID: String? = nil,
        companyName: String? = nil,
        addressSummary: String? = nil
    ) -> DebtorItem? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDocument = document.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCompanyID = companyID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCompanyName = companyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddress = addressSummary?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty || !normalizedDocument.isEmpty || !normalizedEmail.isEmpty || !normalizedPhone.isEmpty else {
            return nil
        }

        var snapshot = loadSnapshot()
        let existingIndex = snapshot.debtors.firstIndex { item in
            if let id, item.id == id { return true }
            return (!normalizedDocument.isEmpty && item.cpfCnpj == normalizedDocument)
                || (!normalizedEmail.isEmpty && item.email.lowercased() == normalizedEmail)
                || (!normalizedName.isEmpty && item.nome.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame)
        }

        if let existingIndex {
            if !normalizedName.isEmpty {
                snapshot.debtors[existingIndex].nome = normalizedName
            }
            if !normalizedDocument.isEmpty {
                snapshot.debtors[existingIndex].cpfCnpj = normalizedDocument
            }
            if !normalizedEmail.isEmpty {
                snapshot.debtors[existingIndex].email = normalizedEmail
            }
            if !normalizedPhone.isEmpty {
                snapshot.debtors[existingIndex].telefone = normalizedPhone
            }
            snapshot.debtors[existingIndex].status = status
            snapshot.debtors[existingIndex].companyID = normalizedCompanyID ?? snapshot.debtors[existingIndex].companyID
            snapshot.debtors[existingIndex].companyName = normalizedCompanyName ?? snapshot.debtors[existingIndex].companyName
            snapshot.debtors[existingIndex].addressSummary = normalizedAddress ?? snapshot.debtors[existingIndex].addressSummary

            appendAudit(action: "atualizar_devedor", module: "devedores", user: "local", snapshot: &snapshot)
            saveSnapshot(snapshot)
            return snapshot.debtors[existingIndex]
        } else {
            let debtor = DebtorItem(
                id: id ?? UUID().uuidString,
                nome: normalizedName.isEmpty ? "Devedor sem nome" : normalizedName,
                cpfCnpj: normalizedDocument,
                email: normalizedEmail,
                telefone: normalizedPhone,
                status: status,
                companyID: normalizedCompanyID,
                companyName: normalizedCompanyName,
                addressSummary: normalizedAddress
            )
            snapshot.debtors.insert(debtor, at: 0)
            appendAudit(action: "criar_devedor", module: "devedores", user: "local", snapshot: &snapshot)
            saveSnapshot(snapshot)
            return debtor
        }
    }

    // MARK: - Debts

    func fetchDebts() -> [DebtItem] {
        loadSnapshot().debts.sorted { $0.vencimento < $1.vencimento }
    }

    func addDebt(title: String, debtorName: String, amount: Decimal, dueDate: Date) {
        var snapshot = loadSnapshot()
        let newDebt = DebtItem(
            id: UUID().uuidString,
            titulo: title,
            devedorNome: debtorName,
            valor: amount,
            vencimento: dueDate,
            status: .pendente
        )
        snapshot.debts.insert(newDebt, at: 0)
        appendAudit(action: "criar_divida", module: "dividas", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    func advanceDebtStatus(debtID: String) {
        var snapshot = loadSnapshot()
        guard let index = snapshot.debts.firstIndex(where: { $0.id == debtID }) else { return }

        let current = snapshot.debts[index].status
        let next: DebtStatus
        switch current {
        case .pendente: next = .negociada
        case .negociada: next = .parcial
        case .parcial: next = .paga
        case .vencida: next = .negociada
        case .paga: next = .cancelada
        case .cancelada: next = .pendente
        }
        snapshot.debts[index].status = next

        appendAudit(action: "atualizar_status_divida", module: "dividas", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    // MARK: - Contracts

    func fetchContracts() -> [ContractItem] {
        loadSnapshot().contracts.sorted { $0.updatedAt > $1.updatedAt }
    }

    func addContract(title: String, debtorName: String, amount: Decimal) {
        var snapshot = loadSnapshot()
        let now = Date()
        let contract = ContractItem(
            id: UUID().uuidString,
            titulo: title,
            devedorNome: debtorName,
            valor: amount,
            status: .rascunho,
            updatedAt: now
        )
        snapshot.contracts.insert(contract, at: 0)
        appendAudit(action: "criar_contrato", module: "contratos", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    func advanceContractStatus(contractID: String) {
        var snapshot = loadSnapshot()
        guard let index = snapshot.contracts.firstIndex(where: { $0.id == contractID }) else { return }

        switch snapshot.contracts[index].status {
        case .rascunho:
            snapshot.contracts[index].status = .aguardandoAssinatura
        case .aguardandoAssinatura:
            snapshot.contracts[index].status = .assinado
        case .assinado:
            snapshot.contracts[index].status = .cancelado
        case .cancelado:
            snapshot.contracts[index].status = .rascunho
        }
        snapshot.contracts[index].updatedAt = Date()

        appendAudit(action: "atualizar_status_contrato", module: "contratos", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    // MARK: - Payments

    func fetchPayments() -> [PaymentItem] {
        loadSnapshot().payments.sorted { $0.createdAt > $1.createdAt }
    }

    func addPayment(reference: String, method: String, amount: Decimal) {
        var snapshot = loadSnapshot()
        let payment = PaymentItem(
            id: UUID().uuidString,
            referencia: reference,
            metodo: method,
            valor: amount,
            status: .processando,
            createdAt: Date()
        )
        snapshot.payments.insert(payment, at: 0)
        appendAudit(action: "criar_pagamento", module: "pagamentos", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    func advancePaymentStatus(paymentID: String) {
        var snapshot = loadSnapshot()
        guard let index = snapshot.payments.firstIndex(where: { $0.id == paymentID }) else { return }

        switch snapshot.payments[index].status {
        case .processando:
            snapshot.payments[index].status = .confirmado
        case .confirmado:
            snapshot.payments[index].status = .falhou
        case .falhou:
            snapshot.payments[index].status = .processando
        }

        appendAudit(action: "atualizar_status_pagamento", module: "pagamentos", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    // MARK: - Audit / Settings

    func fetchAuditEvents(limit: Int = 120) -> [AuditItem] {
        Array(loadSnapshot().audit.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    func fetchPrivacySettings() -> PrivacySettings {
        loadSnapshot().privacy
    }

    func updatePrivacy(marketingEmailsEnabled: Bool) {
        var snapshot = loadSnapshot()
        snapshot.privacy.marketingEmailsEnabled = marketingEmailsEnabled
        appendAudit(action: "atualizar_privacidade", module: "privacidade", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    func requestDataExport() {
        var snapshot = loadSnapshot()
        snapshot.privacy.dataExportRequestedAt = Date()
        appendAudit(action: "solicitar_exportacao_dados", module: "privacidade", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    func fetchSecuritySettings() -> SecuritySettings {
        loadSnapshot().security
    }

    func updateSecurity(mfaEnabled: Bool? = nil, biometricEnabled: Bool? = nil) {
        var snapshot = loadSnapshot()
        if let mfaEnabled {
            snapshot.security.mfaEnabled = mfaEnabled
        }
        if let biometricEnabled {
            snapshot.security.biometricEnabled = biometricEnabled
        }
        appendAudit(action: "atualizar_seguranca", module: "seguranca", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    func markPasswordChanged() {
        var snapshot = loadSnapshot()
        snapshot.security.lastPasswordChangeAt = Date()
        appendAudit(action: "alterar_senha", module: "seguranca", user: "local", snapshot: &snapshot)
        saveSnapshot(snapshot)
    }

    // MARK: - Helpers

    private func appendAudit(action: String, module: String, user: String, snapshot: inout LocalAppSnapshot) {
        let event = AuditItem(
            id: UUID().uuidString,
            acao: action,
            modulo: module,
            usuario: user,
            createdAt: Date()
        )
        snapshot.audit.insert(event, at: 0)
    }

    private func loadSnapshot() -> LocalAppSnapshot {
        let key = snapshotKey()
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(LocalAppSnapshot.self, from: data) {
            return decoded
        }

        let empty = emptySnapshot()
        saveSnapshot(empty)
        return empty
    }

    private func saveSnapshot(_ snapshot: LocalAppSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey())
    }

    private func snapshotKey() -> String {
        guard let session = authStore.currentSession() else {
            return "\(keyPrefix).guest"
        }
        return "\(keyPrefix).\(session.userID)"
    }

    private func emptySnapshot() -> LocalAppSnapshot {
        return LocalAppSnapshot(
            users: [],
            companies: [],
            debtors: [],
            debts: [],
            contracts: [],
            payments: [],
            audit: [],
            privacy: PrivacySettings(marketingEmailsEnabled: false, dataExportRequestedAt: nil),
            security: SecuritySettings(mfaEnabled: false, biometricEnabled: false, lastPasswordChangeAt: Date())
        )
    }
}
