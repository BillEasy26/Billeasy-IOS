//
//  APIRoutes.swift
//  BillEasy
//

import Foundation

/// Rotas da aplicação web (Next.js) espelhadas no app iOS para navegação e deep links.
enum WebAppRoute: String, CaseIterable {
    // Públicas
    case landing = "/landing"
    case cadastro = "/cadastro"
    case forgotPassword = "/forgot-password"
    case resetPassword = "/reset-password"
    case verifyEmail = "/verify-email"
    case googleCallback = "/auth/google/callback"

    // Principal
    case home = "/home"
    case dashboard = "/dashboard"
    case notificacoes = "/notificacoes"
    case documentos = "/documentos"

    // Recebíveis / Pagáveis
    case queroReceber = "/quero-receber"
    case queroPagar = "/quero-pagar"

    // Contratos
    case contratos = "/contratos"
    case contratoWizard = "/contratos/novo"

    // Promissórias
    case promissorias = "/promissorias"
    case promissoriaWizard = "/promissorias/nova"

    // Verificações / KYC
    case verificacoes = "/verificacoes"

    // Dívidas / Agenda
    case dividas = "/dividas"
    case agenda = "/agenda"

    // Perfil e sub-rotas
    case perfil = "/perfil"
    case perfilDados = "/perfil/dados"
    case perfilSeguranca = "/perfil/seguranca"
    case perfilPlano = "/perfil/plano"
    case perfilAuditoria = "/perfil/auditoria"
    case mfaSetup = "/perfil/seguranca/2fa"

    // Pagamentos
    case pagamentos = "/pagamentos"

    // Compliance / Admin
    case auditoria = "/auditoria"
    case rbac = "/rbac"
    case privacidade = "/privacidade"

    // Legados (mantidos para compatibilidade com código existente)
    case seguranca = "/seguranca"
    case meuPlano = "/meu-plano"
    case configuracoes = "/configuracoes"
    case usuarios = "/usuarios"
    case empresas = "/empresas"
    case devedores = "/devedores"
    case localizar = "/localizar"
}

/// Destinos do site (frontend web) que o app pode abrir no navegador.
enum FrontendWebDestination {
    case register
    case login(email: String?)
}

/// Constrói URLs completas do site frontend a partir da base configurada no `Info.plist`.
enum FrontendWebRouteBuilder {
    /// Lê a URL base do frontend do `Info.plist` (chave `FRONTEND_BASE_URL`).
    static func resolveBaseURL(bundle: Bundle = .main) -> URL? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "FRONTEND_BASE_URL") as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return URL(string: trimmed)
    }

    /// Monta a URL final para o destino informado. Retorna `nil` se a base não estiver configurada.
    static func url(
        for destination: FrontendWebDestination,
        baseURL: URL? = FrontendWebRouteBuilder.resolveBaseURL()
    ) -> URL? {
        guard let baseURL else { return nil }

        switch destination {
        case .register:
            return baseURL.appendingPathComponent(WebAppRoute.cadastro.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        case let .login(email):
            var components = URLComponents(
                url: baseURL.appendingPathComponent(WebAppRoute.landing.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
                resolvingAgainstBaseURL: false
            )
            var queryItems = [URLQueryItem(name: "action", value: "login")]
            if let email = normalized(email), email.isEmpty == false {
                queryItems.append(URLQueryItem(name: "email", value: email))
            }
            components?.queryItems = queryItems
            return components?.url
        }
    }

    /// Retorna `true` se existe uma URL válida para o destino (ou seja, o frontend está configurado).
    static func hasURL(
        for destination: FrontendWebDestination,
        baseURL: URL? = FrontendWebRouteBuilder.resolveBaseURL()
    ) -> Bool {
        url(for: destination, baseURL: baseURL) != nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Caminhos de todos os endpoints da API backend e do serviço de IA.
/// Organizados por domínio — alinhados com a referência Android (billeasy_V2).
enum APIRoutes {

    // MARK: - Auth

    enum Auth {
        static let login            = "/auth/login"
        static let logout           = "/auth/logout"
        static let refresh          = "/auth/refresh"
        static let register         = "/auth/register"
        static let login2FA         = "/auth/login/2fa"
        static let me               = "/auth/me"
        static let excluirConta     = "/auth/me/conta"
        static let mobileHandoff    = "/auth/mobile-handoff"

        /// Token chega como segmento de path: `/auth/confirmar-email/{token}`
        static let confirmarEmail      = "/auth/confirmar-email"
        static let reenviarConfirmacao = "/auth/reenviar-confirmacao"

        static let forgotPassword      = "/auth/esqueci-senha"
        static let resetPassword       = "/auth/redefinir-senha"

        static func oauthLogin(_ provedor: String) -> String       { "/auth/oauth/\(provedor)" }
        static func oauthVincular(_ provedor: String) -> String    { "/auth/oauth/\(provedor)/vincular" }
        static func oauthDesvincular(_ provedor: String) -> String { "/auth/oauth/\(provedor)" }

        // Aliases iOS legados (mantidos para não quebrar chamadas existentes)
        static let mobileWebHandoff   = "/api/auth/mobile-web-handoff"
        static let validateResetToken = "/api/auth/validar-token-reset"
        static let verifyEmail        = "/api/auth/verificar-email"
        static let resendVerification = "/api/auth/reenviar-verificacao"
        static let googleCallback     = "/auth/oauth/google"
        static let googleLink         = "/api/auth/google/link"
        static let googleUnlink       = "/api/auth/google/unlink"
        static let appleCallback      = "/api/auth/apple/callback"
    }

    // MARK: - Session

    /// Endpoint legado iOS — use `Auth.me` para o path alinhado com Android.
    enum Session {
        static let me = "/api/session/me"
    }

    // MARK: - MFA

    enum Mfa {
        static let setup    = "/api/mfa/setup"
        static let verify   = "/api/mfa/verify"
        static let validate = "/api/mfa/validate"
        static let disable  = "/api/mfa"
    }

    // MARK: - Usuários

    enum Usuarios {
        static let base = "/api/usuarios"
        static func byID(_ id: String) -> String            { "\(base)/\(id)" }
        static func ativar(_ id: String) -> String          { "\(base)/\(id)/ativar" }
        static func bloquear(_ id: String) -> String        { "\(base)/\(id)/bloquear" }
        static func atualizarSenha(_ id: String) -> String  { "\(base)/\(id)/senha" }
    }

    // MARK: - Papéis / Permissões / RBAC

    enum Papeis {
        static let base = "/api/papeis"
        static func byID(_ id: Int) -> String                               { "\(base)/\(id)" }
        static func permissoes(_ papelId: Int) -> String                    { "\(base)/\(papelId)/permissoes" }
        static func permissao(_ papelId: Int, permissaoId: Int) -> String   { "\(base)/\(papelId)/permissoes/\(permissaoId)" }
    }

    enum Permissoes {
        static let base = "/api/permissoes"
    }

    enum UsuarioPapeis {
        static func base(usuarioId: String) -> String                       { "/api/usuarios/\(usuarioId)/papeis" }
        static func byID(usuarioId: String, papelId: Int) -> String         { "/api/usuarios/\(usuarioId)/papeis/\(papelId)" }
    }

    // MARK: - Empresas / Devedores

    enum Empresas {
        static let base = "/api/empresas"
        static func byID(_ id: String) -> String                                                    { "\(base)/\(id)" }
        static func devedores(_ id: String) -> String                                               { "\(base)/\(id)/devedores" }
        static func devedoresIA(_ id: String) -> String                                             { "\(base)/\(id)/devedores/ia" }
        static func devedor(_ empresaId: String, _ devedorId: String) -> String                     { "\(devedores(empresaId))/\(devedorId)" }
        static func ativarDevedor(_ empresaId: String, _ devedorId: String) -> String               { "\(devedor(empresaId, devedorId))/ativar" }
        static func bloquearDevedor(_ empresaId: String, _ devedorId: String) -> String             { "\(devedor(empresaId, devedorId))/bloquear" }
        static func inadimplenteDevedor(_ empresaId: String, _ devedorId: String) -> String         { "\(devedor(empresaId, devedorId))/inadimplente" }
        static func ativar(_ id: String) -> String                                                  { "\(base)/\(id)/ativar" }
        static func bloquear(_ id: String) -> String                                                { "\(base)/\(id)/bloquear" }
        static func suspender(_ id: String) -> String                                               { "\(base)/\(id)/suspender" }
    }

    enum Devedores {
        static let base = "/api/devedores"
        static func byID(_ id: String) -> String          { "\(base)/\(id)" }
        static func ativar(_ id: String) -> String        { "\(base)/\(id)/ativar" }
        static func bloquear(_ id: String) -> String      { "\(base)/\(id)/bloquear" }
        static func inadimplente(_ id: String) -> String  { "\(base)/\(id)/inadimplente" }
    }

    // MARK: - Dívidas

    enum Dividas {
        static let base    = "/api/dividas"
        /// Endpoint paginado com query `papel` (CREDOR/DEVEDOR) — alinhado com Android.
        static let me      = "/api/dividas/me"
        /// Aliases iOS legados.
        static let pagar   = "/api/dividas/pagar"
        static let receber = "/api/dividas/receber"
        static func byID(_ id: String) -> String              { "\(base)/\(id)" }
        static func cancelar(_ id: String) -> String          { "\(base)/\(id)/cancelar" }
        static func recalcularStatus(_ id: String) -> String  { "\(base)/\(id)/recalcular-status" }
    }

    // MARK: - Acordos / Parcelas

    enum Acordos {
        static func base(dividaId: String) -> String                                    { "/api/dividas/\(dividaId)/acordos" }
        static func aceitar(dividaId: String, acordoId: String) -> String               { "/api/dividas/\(dividaId)/acordos/\(acordoId)/aceitar" }
        static func recusar(dividaId: String, acordoId: String) -> String               { "/api/dividas/\(dividaId)/acordos/\(acordoId)/recusar" }
    }

    enum Parcelas {
        static func base(dividaId: String) -> String                                        { "/api/dividas/\(dividaId)/parcelas" }
        static func byID(dividaId: String, parcelaId: String) -> String                     { "/api/dividas/\(dividaId)/parcelas/\(parcelaId)" }
        static func marcarAtrasada(dividaId: String, parcelaId: String) -> String           { "/api/dividas/\(dividaId)/parcelas/\(parcelaId)/marcar-atrasada" }
        static func pagar(dividaId: String, parcelaId: String) -> String                    { "/api/dividas/\(dividaId)/parcelas/\(parcelaId)/pagar" }
        static func cancelar(dividaId: String, parcelaId: String) -> String                 { "/api/dividas/\(dividaId)/parcelas/\(parcelaId)/cancelar" }
    }

    // MARK: - Contratos

    enum Contratos {
        static let base         = "/api/contratos"
        /// Endpoint paginado — alinhado com Android (`/api/contratos/me`).
        static let me           = "/api/contratos/me"
        /// Alias iOS legado.
        static let meusContratos = "/api/contratos/meus-contratos"
        static func byID(_ id: String) -> String                    { "\(base)/\(id)" }
        /// Android usa `/documento`; o alias `.pdf` é mantido para retro-compatibilidade.
        static func documento(_ id: String) -> String               { "\(base)/\(id)/documento" }
        static func documentoPDF(_ id: String) -> String            { "\(base)/\(id)/documento.pdf" }
        /// Android usa `/enviar`; o alias longo é mantido.
        static func enviar(_ id: String) -> String                  { "\(base)/\(id)/enviar" }
        static func enviarAssinatura(_ id: String) -> String        { "\(base)/\(id)/enviar-assinatura" }
        static func assinarCredor(_ id: String) -> String           { "\(base)/\(id)/assinar-credor" }
        static func assinarDevedor(_ id: String) -> String          { "\(base)/\(id)/assinar-devedor" }
        static func assinaturas(_ id: String) -> String             { "\(base)/\(id)/assinaturas" }
        static func cancelar(_ id: String) -> String                { "\(base)/\(id)/cancelar" }
        static let fluxoIA      = "/api/contratos/fluxo-ia"
        static let classificarIA = "/api/contratos/classificar"
        static let gerarMinutaIA = "/api/contratos/gerar-minuta"
        static let catalogoIA   = "/api/contratos/catalogo-ia"
    }

    // MARK: - Promissórias  ← NOVO (M4, Android billeasy_V2)

    enum Promissorias {
        static let base = "/api/promissorias"
        static let me   = "/api/promissorias/me"
        static func byID(_ id: String) -> String                    { "\(base)/\(id)" }
        static func documento(_ id: String) -> String               { "\(base)/\(id)/documento" }
        static func iniciarKyc(_ id: String) -> String              { "\(base)/\(id)/iniciar-kyc" }
        static func enviarParaAssinatura(_ id: String) -> String    { "\(base)/\(id)/enviar-para-assinatura" }
        static func cancelar(_ id: String) -> String                { "\(base)/\(id)/cancelar" }
    }

    // MARK: - Verificações / KYC  ← NOVO (M4, Android billeasy_V2)

    enum Verificacoes {
        static let base = "/api/verificacoes"
        static let me   = "/api/verificacoes/me"
        static func byID(_ id: String) -> String    { "\(base)/\(id)" }
        static func selfie(_ id: String) -> String  { "\(base)/\(id)/selfie" }
    }

    // MARK: - Convites  ← NOVO (M6, Android billeasy_V2)

    enum Convites {
        static let base = "/api/convites"
        static func preview(_ token: String) -> String  { "\(base)/\(token)" }
        static func aceitar(_ token: String) -> String  { "\(base)/\(token)/aceitar" }
    }

    // MARK: - Formas de Pagamento / Planos / Assinaturas / Cartões

    enum FormasDePagamentos {
        static let base = "/api/formasDePagamentos"
        static func byID(_ id: String) -> String { "\(base)/\(id)" }
    }

    enum Planos {
        static let base = "/api/planos"
        static func byID(_ id: String) -> String { "\(base)/\(id)" }
    }

    enum Assinaturas {
        static let base        = "/api/assinaturas"
        static let minha       = "/api/assinaturas/minha"
        static let minhasCotas = "/api/assinaturas/minha/cotas"
    }

    enum Cartoes {
        static let base      = "/api/cartoes"
        static let tokenizar = "/api/cartoes/tokenizar"
        static func byID(_ id: String) -> String { "\(base)/\(id)" }
    }

    // MARK: - KYC (admin/devedor legacy — use Verificacoes para o fluxo mobile)

    enum KYC {
        static func porDevedor(_ devedorId: String) -> String  { "/api/devedores/\(devedorId)/kyc" }
        static func aprovar(_ kycId: String) -> String         { "/api/kyc/\(kycId)/aprovar" }
        static func reprovar(_ kycId: String) -> String        { "/api/kyc/\(kycId)/reprovar" }
    }

    // MARK: - ePromissórias (legacy — use Promissorias para o fluxo mobile)

    enum EPromissorias {
        static func base(dividaId: String) -> String                                            { "/api/dividas/\(dividaId)/epromissorias" }
        static func byID(dividaId: String, id: String) -> String                               { "/api/dividas/\(dividaId)/epromissorias/\(id)" }
        static func documentoPDF(dividaId: String, id: String) -> String                       { "/api/dividas/\(dividaId)/epromissorias/\(id)/documento.pdf" }
        static func aguardarAceite(dividaId: String, id: String) -> String                     { "/api/dividas/\(dividaId)/epromissorias/\(id)/aguardar-aceite" }
        static func aceitar(dividaId: String, id: String) -> String                            { "/api/dividas/\(dividaId)/epromissorias/\(id)/aceitar" }
        static func vincularKYC(dividaId: String, id: String, kycId: String) -> String        { "/api/dividas/\(dividaId)/epromissorias/\(id)/vincular-kyc/\(kycId)" }
        static func assinar(dividaId: String, id: String) -> String                            { "/api/dividas/\(dividaId)/epromissorias/\(id)/assinar" }
        static func emitir(dividaId: String, id: String) -> String                             { "/api/dividas/\(dividaId)/epromissorias/\(id)/emitir" }
        static func cancelar(dividaId: String, id: String) -> String                           { "/api/dividas/\(dividaId)/epromissorias/\(id)/cancelar" }
        static func assinatura(_ epromissoriaId: String) -> String                             { "/api/v1/epromissorias/\(epromissoriaId)/assinatura" }
    }

    enum Aceite {
        static func porEPromissoria(_ epromissoriaId: String) -> String { "/api/v1/epromissorias/\(epromissoriaId)/aceite" }
    }

    enum TermosAceite {
        static let base  = "/api/v1/termos-aceite"
        static let ativo = "/api/v1/termos-aceite/ativo"
        static func ativar(_ id: String) -> String { "\(base)/\(id)/ativar" }
    }

    // MARK: - Antifraude (legacy — use Verificacoes.selfie para o fluxo mobile)

    enum Antifraude {
        static let verificacoes = "/api/v1/antifraude/verificacoes"
        static func verificacaoByID(_ id: String) -> String                     { "/api/v1/antifraude/verificacoes/\(id)" }
        static func documento(_ id: String) -> String                           { "/api/v1/antifraude/verificacoes/\(id)/documento" }
        static func selfie(_ id: String) -> String                              { "/api/v1/antifraude/verificacoes/\(id)/selfie" }
        static func aprovar(_ id: String) -> String                             { "/api/v1/antifraude/verificacoes/\(id)/aprovar" }
        static func reprovar(_ id: String) -> String                            { "/api/v1/antifraude/verificacoes/\(id)/reprovar" }
        static func eventosEPromissoria(_ epromissoriaId: String) -> String     { "/api/v1/epromissorias/\(epromissoriaId)/antifraude-eventos" }
    }

    // MARK: - Admin

    enum Admin {
        static let stats              = "/api/admin/stats"
        static let migracaoAddonReset = "/api/admin/migracoes/addon-reset"
    }

    // MARK: - Pagamentos / Anexos

    enum Pagamentos {
        static let base = "/api/pagamentos"
        static func byID(_ id: String) -> String                                    { "\(base)/\(id)" }
        static func porParcela(dividaId: String, parcelaId: String) -> String       { "/api/dividas/\(dividaId)/parcelas/\(parcelaId)/pagamentos" }
    }

    enum Anexos {
        static let base = "/api/anexos"
        static func byID(_ id: String) -> String                    { "\(base)/\(id)" }
        static func download(_ id: String) -> String                { "\(base)/\(id)/download" }
        static func porDivida(_ dividaId: String) -> String         { "/api/dividas/\(dividaId)/anexos" }
        static func porContrato(_ contratoId: String) -> String     { "/api/contratos/\(contratoId)/anexos" }
        static func porUsuario(_ usuarioId: String) -> String       { "/api/usuarios/\(usuarioId)/anexos" }
    }

    // MARK: - Notificações  ← ATUALIZADO (M4, Android billeasy_V2)

    enum Notificacoes {
        static let base         = "/api/notificacoes"
        static let contagem     = "/api/notificacoes/contagem"
        static let todasLidas   = "/api/notificacoes/lidas"
        static func byID(_ id: String) -> String            { "\(base)/\(id)" }
        static func marcarLida(_ id: String) -> String      { "\(base)/\(id)/lida" }
        static func marcarNaoLida(_ id: String) -> String   { "\(base)/\(id)/nao-lida" }
    }

    // MARK: - Auditoria

    enum Auditoria {
        static let base          = "/api/auditoria"
        static let autenticacao  = "/api/auditoria/autenticacao"
        static let estatisticas  = "/api/auditoria/estatisticas"
        static func byID(_ id: String) -> String            { "\(base)/\(id)" }
        static func porUsuario(_ usuarioId: String) -> String { "\(base)/usuario/\(usuarioId)" }
        static func porAcao(_ acao: String) -> String       { "/api/auditoria/acao/\(acao)" }
    }

    // MARK: - LGPD

    enum LGPD {
        static let meusDados           = "/api/lgpd/meus-dados"
        static let downloadMeusDados   = "/api/lgpd/meus-dados/download"
        static let anonimizarMinhaConta = "/api/lgpd/minha-conta"
        static func exportar(_ usuarioId: String) -> String    { "/api/lgpd/exportar/\(usuarioId)" }
        static func anonimizar(_ usuarioId: String) -> String  { "/api/lgpd/anonimizar/\(usuarioId)" }
    }

    // MARK: - Utilitários

    enum CEP {
        static func consultar(_ cep: String) -> String { "/api/enderecos/cep/\(cep)" }
    }

    enum Exato {
        static let pessoaFisica  = "/api/exato/pessoa-fisica"
        static let analiseCredito = "/api/exato/analise-credito"
    }

    enum Integracoes {
        static let eventos = "/api/integracoes/eventos"
    }

    // MARK: - Dashboard

    enum Dashboard {
        static let credor = "/api/dashboard/credor"
        static let devedor = "/api/dashboard/devedor"
    }

    // MARK: - Serviço de IA

    enum AIService {
        static let health                 = "/health"
        static let transcribeAudio        = "/api/audio/transcribe"
        static let transcribeAndExtract   = "/api/audio/transcribe-and-extract"
        static let extractOCR             = "/api/ocr/extract"
        static let extractOCRFields       = "/api/ocr/extract-fields"
        static let extractOCRAndAnalyze   = "/api/ocr/extract-and-analyze"
        static let extractFromText        = "/api/extract/text"
        static let validateExtract        = "/api/extract/validate"
        static let confirmExtract         = "/api/extract/confirm"
        static func transcribeJob(_ jobId: String) -> String    { "/api/audio/job/\(jobId)" }
        static func searchDebtors(_ empresaId: String) -> String { "/api/extract/devedores/\(empresaId)" }
    }

    enum AIProxy {
        static let extractFromText  = "/api/ia/extrair-texto"
        static let extractFromImage = "/api/ia/extrair-de-imagem"
        static let transcribeAudio  = "/api/ia/audio/transcribe"
        static let extractOCR       = "/api/ia/ocr"
        static func transcribeJob(_ jobId: String) -> String { "/api/ia/audio/job/\(jobId)" }
    }
}
