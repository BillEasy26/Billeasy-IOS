//
//  AppCoordinator.swift
//  BillEasy
//

import UIKit

/// Coordinator raiz do app. Decide qual fluxo exibir como raiz da janela
/// (tela pública, app autenticado ou modos especiais de preview para testes).
final class AppCoordinator {
    private let window: UIWindow
    private let authService: AuthService
    private let dataStore: LocalAppDataStore

    init(
        window: UIWindow,
        authService: AuthService = AuthService(),
        dataStore: LocalAppDataStore = LocalAppDataStore()
    ) {
        self.window = window
        self.authService = authService
        self.dataStore = dataStore
    }

    /// Inicia o app escolhendo a primeira tela com base no estado de autenticação atual.
    /// Suporta três modos especiais de preview controlados por variáveis de ambiente (para testes de UI):
    ///   - `registerConfirmationPreviewEmail`: abre direto a tela de confirmação de cadastro.
    ///   - `contractFileReviewPreviewURL`: abre direto a revisão de arquivo de contrato.
    ///   - Caso contrário: sessão existente → app principal; sem sessão → tela pública.
    func start() {
        seedSessionForUITestingIfNeeded()

        if let previewEmail = AppRuntimeConfiguration.registerConfirmationPreviewEmail {
            showPublicHome(animated: false)
            if let nav = window.rootViewController as? UINavigationController {
                nav.pushViewController(makeRegisterConfirmationScreen(email: previewEmail), animated: false)
            }
            window.makeKeyAndVisible()
            return
        }

        if let previewURL = AppRuntimeConfiguration.contractFileReviewPreviewURL {
            showContractFileReviewPreview(with: previewURL)
            window.makeKeyAndVisible()
            return
        }

        if let session = authService.currentSession() {
            showMainApp(with: session, animated: false)
        } else {
            showPublicHome(animated: false)
        }
        window.makeKeyAndVisible()
    }

    /// Monta a pilha pública: landing page com botões de login, login social e redirecionamento para cadastro na web.
    private func showPublicHome(animated: Bool) {
        let home = PublicHomeViewController()

        home.onLoginRequested = { [weak self, weak home] in
            guard let self, let nav = home?.navigationController else { return }
            nav.pushViewController(self.makeLoginScreen(), animated: true)
        }
        home.onAppleLoginRequested = { [weak self, weak home] in
            guard let self, let nav = home?.navigationController else { return }
            nav.pushViewController(self.makeLoginScreen(startWithAppleLogin: true), animated: true)
        }
        home.onGoogleLoginRequested = { [weak self, weak home] in
            guard let self, let nav = home?.navigationController else { return }
            nav.pushViewController(self.makeLoginScreen(startWithGoogleLogin: true), animated: true)
        }
        home.onRegisterRequested = { [weak self, weak home] in
            guard let self else { return }
            self.openFrontend(.register, from: home)
        }

        let nav = UINavigationController(rootViewController: home)
        nav.setNavigationBarHidden(true, animated: false)
        setRoot(nav, animated: animated)
    }

    /// Cria a tela de login configurando os callbacks de sucesso e opções de login social inicial.
    /// - Parameters:
    ///   - prefilledEmail: e-mail já preenchido no campo (vindo de um redirecionamento).
    ///   - startWithAppleLogin: inicia o fluxo Apple Sign In automaticamente ao aparecer.
    ///   - startWithGoogleLogin: inicia o fluxo Google OAuth automaticamente ao aparecer.
    private func makeLoginScreen(
        prefilledEmail: String? = nil,
        startWithAppleLogin: Bool = false,
        startWithGoogleLogin: Bool = false
    ) -> LoginViewController {
        let login = LoginViewController(authService: authService)
        login.prefilledEmail = prefilledEmail
        login.startWithAppleLogin = startWithAppleLogin
        login.startWithGoogleLogin = startWithGoogleLogin
        login.onLoginSuccess = { [weak self] session in
            self?.showMainApp(with: session, animated: true)
        }
        return login
    }

    /// Cria a tela de confirmação de cadastro passando o e-mail e o serviço de auth.
    private func makeRegisterConfirmationScreen(email: String) -> RegisterConfirmationViewController {
        RegisterConfirmationViewController(email: email, authService: authService)
    }

    /// Exibe direto a tela de revisão de arquivo de contrato com uma sessão de preview.
    /// Usado apenas em inspeções visuais controladas durante o desenvolvimento.
    private func showContractFileReviewPreview(with fileURL: URL) {
        let previewSession = AuthSession(
            userID: "preview-user",
            displayName: "Preview User",
            email: "preview@billeasy.ai",
            provider: .email,
            empresaID: "preview-company",
            roles: ["USUARIO"]
        )
        let controller = ContractsViewController(session: previewSession, dataStore: dataStore)
        controller.configureDebugFileReviewPreview(fileURL: fileURL)
        let nav = UINavigationController(rootViewController: controller)
        nav.setNavigationBarHidden(true, animated: false)
        setRoot(nav, animated: false)
    }

    /// Sobe o shell principal do app (tab bar) com a sessão autenticada já carregada.
    /// Configura o callback de logout para retornar à tela pública.
    private func showMainApp(with session: AuthSession, animated: Bool) {
        let main = MainTabBarController(session: session, authService: authService, dataStore: dataStore)
        main.onLogout = { [weak self] in
            self?.showPublicHome(animated: true)
        }
        setRoot(main, animated: animated)
    }

    /// Recebe URLs de deep link ou OAuth via URL scheme vindas do SceneDelegate.
    func handleOpenURL(_ url: URL) {
        // Ponto de extensão: encaminhar a URL para o serviço OAuth registrado para o scheme.
        _ = url
    }

    /// Troca a view controller raiz da janela, com ou sem animação de cross-dissolve.
    private func setRoot(_ viewController: UIViewController, animated: Bool) {
        guard animated else {
            window.rootViewController = viewController
            return
        }
        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
            self.window.rootViewController = viewController
        }
    }

    /// Abre uma URL do site (cadastro, login) no navegador padrão do dispositivo.
    /// Exibe um alerta se a URL não estiver configurada ou se o sistema não conseguir abrir.
    private func openFrontend(_ destination: FrontendWebDestination, from presenter: UIViewController?) {
        guard let url = FrontendWebRouteBuilder.url(for: destination) else {
            let alert = UIAlertController(
                title: "Site indisponível",
                message: "Não encontrei a URL do site para continuar esse fluxo.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter?.present(alert, animated: true)
            return
        }

        UIApplication.shared.open(url) { [weak presenter] success in
            guard !success else { return }
            let alert = UIAlertController(
                title: "Não consegui abrir o site",
                message: "Tente novamente em instantes.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter?.present(alert, animated: true)
        }
    }

    /// Cria uma sessão local de teste se o argumento `-seed-auth-session` estiver presente.
    /// Só executa em modo local e apenas se ainda não houver nenhuma sessão salva.
    private func seedSessionForUITestingIfNeeded() {
        guard AppRuntimeConfiguration.shouldSeedAuthenticatedSession else { return }
        guard authService.isLocalMode else { return }

        let store = LocalAuthStore()
        guard store.currentSession() == nil else { return }

        _ = try? store.register(
            nome: "UI Test User",
            email: "ui.test@billeasy.ai",
            telefone: "",
            cpfCnpj: "",
            senha: "senha123"
        )
    }
}
