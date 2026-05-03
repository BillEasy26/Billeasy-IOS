//
//  RouteScreenFactory.swift
//  BillEasy
//

import UIKit

/// Fábrica que instancia a `UIViewController` correta para cada rota da aplicação.
/// Centraliza a criação de telas para que `RouteListViewController` (modo debug) e outros
/// pontos de entrada não precisem conhecer os detalhes de inicialização de cada controller.
enum RouteScreenFactory {

    private static func fallbackSession() -> AuthSession {
        AuthSession(userID: "local", displayName: "Conta Local", email: "local@billeasy.ai", provider: .email)
    }

    /// Retorna a `UIViewController` correspondente à rota informada.
    static func makeScreen(
        for route: WebAppRoute,
        title: String,
        dataStore: LocalAppDataStore,
        session: AuthSession? = nil
    ) -> UIViewController {
        let resolvedSession = session ?? fallbackSession()

        switch route {

        // MARK: Home / Principal
        case .home, .dashboard, .queroReceber:
            return DashboardViewController(session: resolvedSession, dataStore: dataStore)

        case .notificacoes:
            return NotificacoesViewController(session: resolvedSession)

        case .documentos:
            return RoutePlaceholderViewController(route: route, displayTitle: title)

        // MARK: Recebíveis / Pagáveis
        case .queroPagar:
            return PaymentsViewController(session: resolvedSession, dataStore: dataStore)

        // MARK: Dívidas / Agenda
        case .dividas, .agenda:
            return AgendaViewController(session: resolvedSession, dataStore: dataStore)

        // MARK: Contratos
        case .contratos:
            return ContractsViewController(session: resolvedSession, dataStore: dataStore)

        case .contratoWizard:
            return RoutePlaceholderViewController(route: route, displayTitle: title)

        // MARK: Promissórias  ← NOVO (M4)
        case .promissorias:
            return PromissoriasViewController(session: resolvedSession)

        case .promissoriaWizard:
            return PromissoriaWizardViewController(session: resolvedSession)

        // MARK: Verificações / KYC  ← NOVO (M4)
        case .verificacoes:
            return VerificacoesViewController(session: resolvedSession)

        // MARK: Pagamentos
        case .pagamentos:
            return PaymentsViewController(session: resolvedSession, dataStore: dataStore)

        // MARK: Perfil e sub-rotas
        case .perfil, .perfilDados, .usuarios, .configuracoes:
            return ProfileViewController(session: resolvedSession, dataStore: dataStore)

        case .perfilSeguranca, .seguranca:
            return SecurityViewController(dataStore: dataStore)

        case .perfilPlano, .meuPlano:
            return MeuPlanoViewController(session: resolvedSession, dataStore: dataStore)

        case .perfilAuditoria:
            return AuditViewController(dataStore: dataStore)

        case .mfaSetup:
            return RoutePlaceholderViewController(route: route, displayTitle: title)

        // MARK: Compliance / Admin
        case .auditoria:
            return AuditViewController(dataStore: dataStore)

        case .rbac:
            return RbacViewController(style: .insetGrouped)

        case .privacidade:
            return PrivacyViewController(dataStore: dataStore)

        // MARK: Diretório de empresas / devedores
        case .empresas:
            return CompaniesViewController(session: resolvedSession, dataStore: dataStore)

        case .devedores:
            return DebtorDirectoryViewController(session: resolvedSession, dataStore: dataStore)

        case .localizar:
            #if DEBUG
            return DebtorsViewController(session: resolvedSession, dataStore: dataStore)
            #else
            return RoutePlaceholderViewController(route: route, displayTitle: title)
            #endif

        // MARK: Públicas (só chegam aqui via debug / RouteList)
        case .landing, .cadastro, .forgotPassword, .resetPassword, .verifyEmail, .googleCallback:
            return RoutePlaceholderViewController(route: route, displayTitle: title)
        }
    }
}
