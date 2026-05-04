//
//  BillEasyTests.swift
//  BillEasyTests
//
//  Created by Samuel Jammes  on 10/03/26.
//

import Foundation
import Testing
@testable import BillEasy

struct BillEasyTests {

    @Test("Route catalog has baseline modules configured")
    func routeCatalogHasCoreRoutes() {
        #expect(AppNavigationCatalog.all.count > 15)
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .dashboard }))
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .queroReceber }))
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .queroPagar }))
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .agenda }))
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .localizar }))
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .perfil }))
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .meuPlano }))
        #expect(AppNavigationCatalog.all.contains(where: { $0.webRoute == .usuarios }))
    }

    @Test("Admin session starts with empty operational workspace on mobile")
    func adminSessionUsesEmptyWorkspace() {
        let session = AuthSession(
            userID: "admin",
            displayName: "Admin",
            email: "admin@billeasy.com.br",
            provider: .email,
            roles: ["SUPER_ADMIN"]
        )

        #expect(session.isAdminLike)
        #expect(session.canAccessCreditorWorkspace == false)
        #expect(session.canAccessDebtorWorkspace == false)
        #expect(session.shouldStartWithEmptyWorkspace)
    }

    @Test("Operational session exposes creditor and debtor workspaces from remote context")
    func operationalSessionExposesWorkspaces() {
        let session = AuthSession(
            userID: "user",
            displayName: "Usuário",
            email: "user@billeasy.ai",
            provider: .email,
            empresaID: "empresa-1",
            roles: ["USUARIO"],
            hasDebtorProfile: true
        )

        #expect(session.isAdminLike == false)
        #expect(session.canAccessCreditorWorkspace)
        #expect(session.canAccessDebtorWorkspace)
        #expect(session.shouldStartWithEmptyWorkspace == false)
    }

    @Test("API route catalog stays aligned with current web endpoints")
    func apiRoutesStayAlignedWithWeb() {
        #expect(APIRoutes.CEP.consultar("01310100") == "/api/enderecos/cep/01310100")
        #expect(APIRoutes.Dividas.pagar == "/api/dividas/pagar")
        #expect(APIRoutes.Dividas.receber == "/api/dividas/receber")
        #expect(APIRoutes.Dividas.byID("div-1") == "/api/dividas/div-1")
        #expect(APIRoutes.Contratos.fluxoIA == "/api/contratos/fluxo-ia")
        #expect(APIRoutes.Contratos.classificarIA == "/api/contratos/classificar")
        #expect(APIRoutes.Contratos.documentoPDF("ctr-1") == "/api/contratos/ctr-1/documento.pdf")
        #expect(APIRoutes.Contratos.assinarCredor("ctr-1") == "/api/contratos/ctr-1/assinar-credor")
        #expect(APIRoutes.Contratos.assinarDevedor("ctr-1") == "/api/contratos/ctr-1/assinar-devedor")
        #expect(APIRoutes.FormasDePagamentos.base == "/api/formasDePagamentos")
        #expect(APIRoutes.Planos.base == "/api/planos")
        #expect(APIRoutes.Planos.byID("pln-1") == "/api/planos/pln-1")
        #expect(APIRoutes.Assinaturas.minha == "/api/assinaturas/minha")
        #expect(APIRoutes.Assinaturas.minhasCotas == "/api/assinaturas/minha/cotas")
        #expect(APIRoutes.Anexos.porUsuario("usr-1") == "/api/usuarios/usr-1/anexos")
        #expect(APIRoutes.AIProxy.transcribeAudio == "/api/ia/audio/transcribe")
        #expect(APIRoutes.AIProxy.transcribeJob("job-1") == "/api/ia/audio/job/job-1")
        #expect(APIRoutes.AIProxy.extractFromImage == "/api/ia/extrair-de-imagem")
        #expect(APIRoutes.AIProxy.extractOCR == "/api/ia/ocr")
        #expect(APIRoutes.AIProxy.extractFromText == "/api/ia/extrair-texto")
        #expect(APIRoutes.Auth.forgotPassword == "/auth/esqueci-senha")
        #expect(APIRoutes.Auth.validateResetToken == "/api/auth/validar-token-reset")
        #expect(APIRoutes.Auth.resetPassword == "/auth/redefinir-senha")
        #expect(APIRoutes.Auth.verifyEmail == "/api/auth/verificar-email")
        #expect(APIRoutes.Auth.resendVerification == "/api/auth/reenviar-verificacao")
    }

    @Test("Document formatter switches automatically between CPF and CNPJ masks")
    func documentFormatterAppliesBrazilianMasks() {
        #expect(Formatters.formatCPFOrCNPJ("06427166174") == "064.271.661-74")
        #expect(Formatters.formatCPFOrCNPJ("12345678000195") == "12.345.678/0001-95")
        #expect(Formatters.formatCPFOrCNPJ("12.345.678/0001-95") == "12.345.678/0001-95")
        #expect(Formatters.formatCEP("01310100") == "01310-100")
    }

    @Test("Currency formatter keeps editable values and display strings in Brazilian real")
    func currencyFormatterAppliesBrazilianRealPattern() {
        #expect(Formatters.formatCurrencyInput("765000") == "R$ 7.650,00")
        #expect(Formatters.decimalFromCurrencyInput("R$ 7.650,00") == Decimal(string: "7650")!)
        #expect(Formatters.normalizeCurrencyDisplay("R$ 7650,00") == "R$ 7.650,00")
        #expect(Formatters.normalizeCurrencyDisplay("2500.00") == "R$ 2.500,00")
    }

    @Test("Date formatter normalizes API and OCR inputs to Brazilian numeric dates")
    func dateFormatterNormalizesContractInputs() {
        #expect(Formatters.normalizeDateDisplay("2026-03-24") == "24/03/2026")
        #expect(Formatters.normalizeDateDisplay("24/03/2026") == "24/03/2026")
    }

    @Test("Remote API error parser extracts user-facing messages from problem+json payloads")
    func remoteAPIParsesProblemJSONMessages() {
        let payload = """
        {
          "status": 402,
          "type": "https://billeasy.com.br/problems/limite-plano-excedido",
          "title": "Limite do plano excedido",
          "detail": "Limite de consultas de devedor atingido. Seu plano permite 1 consulta(s) por ciclo. Faça upgrade ou adicione um add-on.",
          "userMessage": "Limite de consultas de devedor atingido. Seu plano permite 1 consulta(s) por ciclo. Faça upgrade ou adicione um add-on."
        }
        """.data(using: .utf8)!

        #expect(
            RemoteAPIClient.extractUserFacingErrorMessage(from: payload) ==
            "Limite de consultas de devedor atingido. Seu plano permite 1 consulta(s) por ciclo. Faça upgrade ou adicione um add-on."
        )
    }

    @Test("Fluxos web públicos e rotas de handoff ficam alinhados com o backend")
    func frontendWebRoutesStayConsistent() {
        let baseURL = URL(string: "http://localhost:3000")
        let loginURL = FrontendWebRouteBuilder.url(
            for: .login(email: "user@billeasy.com.br"),
            baseURL: baseURL
        )
        let registerURL = FrontendWebRouteBuilder.url(for: .register, baseURL: baseURL)

        #expect(registerURL?.absoluteString == "http://localhost:3000/cadastro")
        #expect(FrontendWebRouteBuilder.hasURL(for: .login(email: nil), baseURL: baseURL))
        #expect(APIRoutes.Auth.mobileHandoff == "/auth/mobile-handoff")
        #expect(PortalWebHandoffDestination.myPlan.nextPath == "/app/conta/plano")
        #expect(PortalWebHandoffDestination.debtorLocator.nextPath == "/app/localizar-devedor")

        let loginComponents = loginURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let loginItems = Dictionary(uniqueKeysWithValues: (loginComponents?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(loginComponents?.path == "/landing")
        #expect(loginItems["action"] == "login")
        #expect(loginItems["email"] == "user@billeasy.com.br")
    }

}
