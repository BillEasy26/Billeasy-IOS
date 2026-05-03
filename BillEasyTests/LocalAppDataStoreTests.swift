import Foundation
import Testing
@testable import BillEasy

struct LocalAppDataStoreTests {

    @Test("New account starts with empty dashboard summary")
    func emptyAccountHasEmptySummary() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Zero", email: "zero@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)
        let summary = store.dashboardSummary()

        #expect(summary.totalUsuarios == 0)
        #expect(summary.totalDividas == 0)
        #expect(summary.valorEmAberto == Decimal.zero)
    }

    @Test("Adding debt updates summary and debt status can advance")
    func debtLifecycleUpdatesSummary() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Debtor", email: "debtor@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)
        store.addDebt(title: "Divida teste", debtorName: "Cliente", amount: Decimal(string: "500")!, dueDate: Date())

        let summaryAfterAdd = store.dashboardSummary()
        #expect(summaryAfterAdd.totalDividas == 1)
        #expect(summaryAfterAdd.valorEmAberto == Decimal(string: "500")!)

        guard let debtID = store.fetchDebts().first?.id else {
            Issue.record("Expected one debt after addDebt.")
            return
        }

        store.advanceDebtStatus(debtID: debtID)
        #expect(store.fetchDebts().first?.status == .negociada)
    }

    @Test("Contract and payment status advance through expected cycle")
    func contractAndPaymentStatusAdvance() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Fluxo", email: "fluxo@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        store.addContract(title: "Contrato A", debtorName: "Cliente A", amount: Decimal(string: "1200")!)
        guard let contractID = store.fetchContracts().first?.id else {
            Issue.record("Expected one contract after addContract.")
            return
        }

        store.advanceContractStatus(contractID: contractID)
        #expect(store.fetchContracts().first?.status == .aguardandoAssinatura)

        store.addPayment(reference: "Pagamento A", method: "pix", amount: Decimal(string: "100")!)
        guard let paymentID = store.fetchPayments().first?.id else {
            Issue.record("Expected one payment after addPayment.")
            return
        }

        store.advancePaymentStatus(paymentID: paymentID)
        #expect(store.fetchPayments().first?.status == .confirmado)
    }

    @Test("Upserting debtor creates one record and later updates the same entry")
    func debtorUpsertCreatesAndUpdatesSameRecord() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Contrato", email: "contrato@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        store.upsertDebtor(
            name: "Maria Oliveira",
            document: "123.456.789-00",
            email: "maria@teste.com",
            phone: "(11) 99999-1111"
        )
        store.upsertDebtor(
            name: "Maria O.",
            document: "123.456.789-00",
            email: "maria.novo@teste.com",
            phone: "(11) 98888-2222"
        )

        let debtors = store.fetchDebtors()
        #expect(debtors.count == 1)
        #expect(debtors.first?.nome == "Maria O.")
        #expect(debtors.first?.email == "maria.novo@teste.com")
        #expect(debtors.first?.telefone == "(11) 98888-2222")
    }

    @Test("Company and debtor directory metadata are persisted locally for CRUD fallbacks")
    func directoryMetadataPersistsLocally() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Diretorio", email: "diretorio@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let company = store.upsertCompany(
            name: "BillEasy Serviços",
            document: "12.345.678/0001-90",
            phone: "(61) 99301-1072",
            isActive: true,
            type: "PESSOA_JURIDICA",
            status: "ATIVA",
            addressSummary: "Avenida Paulista, 1578 • Bela Vista • São Paulo • SP",
            responsibleName: "Samuel"
        )

        let debtor = store.upsertDebtor(
            name: "Maria Oliveira",
            document: "123.456.789-00",
            email: "maria@teste.com",
            phone: "(11) 98888-2222",
            status: "ATIVO",
            companyID: company?.id,
            companyName: company?.nome,
            addressSummary: "CEP 01310-100 • Número 1578 • Sala 12"
        )

        #expect(company?.tipo == "PESSOA_JURIDICA")
        #expect(company?.status == "ATIVA")
        #expect(company?.addressSummary?.contains("Avenida Paulista") == true)
        #expect(debtor?.companyName == "BillEasy Serviços")
        #expect(debtor?.addressSummary == "CEP 01310-100 • Número 1578 • Sala 12")
    }

    @Test("Company and debtor lifecycle updates persist locally for offline actions")
    func directoryLifecycleActionsPersistLocally() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Diretorio", email: "diretorio@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        let company = store.upsertCompany(
            name: "BillEasy Serviços",
            document: "12.345.678/0001-90",
            phone: "(61) 99301-1072",
            isActive: true,
            type: "PESSOA_JURIDICA",
            status: "ATIVA"
        )

        let debtor = store.upsertDebtor(
            name: "Maria Oliveira",
            document: "123.456.789-00",
            email: "maria@teste.com",
            phone: "(11) 98888-2222",
            status: "ATIVO"
        )

        let suspendedCompany = store.updateCompanyLifecycle(
            companyID: company?.id ?? "",
            isActive: false,
            status: "SUSPENSO",
            auditAction: "suspender_empresa"
        )

        let blockedDebtor = store.updateDebtorLifecycle(
            debtorID: debtor?.id ?? "",
            status: "BLOQUEADO",
            auditAction: "bloquear_devedor"
        )

        #expect(suspendedCompany?.ativa == false)
        #expect(suspendedCompany?.status == "SUSPENSO")
        #expect(blockedDebtor?.status == "BLOQUEADO")
    }

    @Test("Privacy and security updates are persisted")
    func privacyAndSecurityUpdatesPersist() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        _ = try authStore.register(nome: "Priv", email: "priv@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        store.updatePrivacy(marketingEmailsEnabled: true)
        store.requestDataExport()
        store.updateSecurity(mfaEnabled: true, biometricEnabled: true)

        let privacy = store.fetchPrivacySettings()
        let security = store.fetchSecuritySettings()

        #expect(privacy.marketingEmailsEnabled)
        #expect(privacy.dataExportRequestedAt != nil)
        #expect(security.mfaEnabled)
        #expect(security.biometricEnabled)
    }

    @Test("Snapshots are isolated by authenticated user")
    func userSnapshotIsolationWorks() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let authStore = LocalAuthStore(defaults: helper.defaults)
        let userA = try authStore.register(nome: "A", email: "a@teste.com", telefone: "", cpfCnpj: "", senha: "123")
        let store = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)

        store.addDebt(title: "Divida A", debtorName: "Cliente A", amount: Decimal(string: "700")!, dueDate: Date())
        #expect(store.dashboardSummary().totalDividas == 1)

        authStore.logout()
        _ = try authStore.register(nome: "B", email: "b@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let storeForUserB = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)
        #expect(storeForUserB.dashboardSummary().totalDividas == 0)

        _ = try authStore.login(email: userA.email, senha: "123")
        let storeForUserA = LocalAppDataStore(defaults: helper.defaults, authStore: authStore)
        #expect(storeForUserA.dashboardSummary().totalDividas == 1)
    }

}
