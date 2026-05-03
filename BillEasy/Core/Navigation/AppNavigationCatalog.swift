//
//  AppNavigationCatalog.swift
//  BillEasy
//

import Foundation

enum RouteAccessLevel {
    case `public`
    case authenticated
    case admin
}

struct AppRouteDefinition {
    let webRoute: WebAppRoute
    let title: String
    let access: RouteAccessLevel
}

enum AppNavigationCatalog {
    static let all: [AppRouteDefinition] = [

        // MARK: Públicas
        AppRouteDefinition(webRoute: .landing,        title: "Landing",          access: .public),
        AppRouteDefinition(webRoute: .cadastro,       title: "Cadastro",         access: .public),
        AppRouteDefinition(webRoute: .forgotPassword, title: "Esqueci Senha",    access: .public),
        AppRouteDefinition(webRoute: .resetPassword,  title: "Reset Senha",      access: .public),
        AppRouteDefinition(webRoute: .verifyEmail,    title: "Verificar Email",  access: .public),
        AppRouteDefinition(webRoute: .googleCallback, title: "Google Callback",  access: .public),

        // MARK: Home / Principal
        AppRouteDefinition(webRoute: .home,           title: "Home",             access: .authenticated),
        AppRouteDefinition(webRoute: .dashboard,      title: "Dashboard",        access: .authenticated),
        AppRouteDefinition(webRoute: .notificacoes,   title: "Notificações",     access: .authenticated),
        AppRouteDefinition(webRoute: .documentos,     title: "Documentos",       access: .authenticated),

        // MARK: Recebíveis / Pagáveis
        AppRouteDefinition(webRoute: .queroReceber,   title: "Quero Receber",    access: .authenticated),
        AppRouteDefinition(webRoute: .queroPagar,     title: "Quero Pagar",      access: .authenticated),

        // MARK: Contratos
        AppRouteDefinition(webRoute: .contratos,      title: "Contratos",        access: .authenticated),
        AppRouteDefinition(webRoute: .contratoWizard, title: "Novo Contrato",    access: .authenticated),

        // MARK: Promissórias
        AppRouteDefinition(webRoute: .promissorias,      title: "Promissórias",     access: .authenticated),
        AppRouteDefinition(webRoute: .promissoriaWizard, title: "Nova Promissória", access: .authenticated),

        // MARK: Verificações / KYC
        AppRouteDefinition(webRoute: .verificacoes,   title: "Verificações",     access: .authenticated),

        // MARK: Dívidas / Agenda
        AppRouteDefinition(webRoute: .dividas,        title: "Dívidas",          access: .authenticated),
        AppRouteDefinition(webRoute: .agenda,         title: "Agenda",           access: .authenticated),

        // MARK: Pagamentos
        AppRouteDefinition(webRoute: .pagamentos,     title: "Pagamentos",       access: .authenticated),

        // MARK: Perfil e sub-rotas
        AppRouteDefinition(webRoute: .perfil,         title: "Perfil",           access: .authenticated),
        AppRouteDefinition(webRoute: .perfilDados,    title: "Meus Dados",       access: .authenticated),
        AppRouteDefinition(webRoute: .perfilSeguranca, title: "Segurança",       access: .authenticated),
        AppRouteDefinition(webRoute: .perfilPlano,    title: "Meu Plano",        access: .authenticated),
        AppRouteDefinition(webRoute: .perfilAuditoria, title: "Minha Auditoria", access: .authenticated),
        AppRouteDefinition(webRoute: .mfaSetup,       title: "Config. 2FA",      access: .authenticated),

        // MARK: Compliance / Admin
        AppRouteDefinition(webRoute: .auditoria,      title: "Auditoria",        access: .admin),
        AppRouteDefinition(webRoute: .rbac,           title: "RBAC",             access: .admin),
        AppRouteDefinition(webRoute: .privacidade,    title: "Privacidade",      access: .authenticated),

        // MARK: Legados (mantidos para não quebrar RouteListViewController existente)
        AppRouteDefinition(webRoute: .seguranca,      title: "Segurança (legado)", access: .authenticated),
        AppRouteDefinition(webRoute: .meuPlano,       title: "Meu Plano (legado)", access: .authenticated),
        AppRouteDefinition(webRoute: .configuracoes,  title: "Configurações",    access: .authenticated),
        AppRouteDefinition(webRoute: .usuarios,       title: "Usuários",         access: .authenticated),
        AppRouteDefinition(webRoute: .empresas,       title: "Empresas",         access: .authenticated),
        AppRouteDefinition(webRoute: .devedores,      title: "Devedores",        access: .authenticated),
        AppRouteDefinition(webRoute: .localizar,      title: "Localizar Devedor", access: .authenticated),
    ]
}
