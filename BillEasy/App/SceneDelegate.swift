//
//  SceneDelegate.swift
//  BillEasy
//

import UIKit

/// Gerencia o ciclo de vida de uma cena (janela) do app.
/// Cria a janela principal, inicializa o coordinador de navegação e cuida da sobreposição de privacidade.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    /// Sobreposição exibida quando o app vai para segundo plano,
    /// impedindo que o conteúdo sensível apareça no seletor de apps.
    private var privacyOverlay: UIView?
    private let privacyOverlayTag = 0xB11EA5

    /// Chamado quando a cena está prestes a se conectar à sessão.
    /// Cria a janela, instancia o AppCoordinator e inicia o fluxo de navegação.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        let coordinator = AppCoordinator(window: window)
        appCoordinator = coordinator
        coordinator.start()
    }

    /// Recebe URLs externas (deep links, OAuth via URL scheme) e as repassa ao coordinator.
    /// O ASWebAuthenticationSession já gerencia o seu próprio callback internamente;
    /// este método cobre apenas fluxos que usam URL scheme manual.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        appCoordinator?.handleOpenURL(url)
    }

    /// Exibe uma tela neutra sobre a janela quando o app perde o foco (ex.: usuário abre o seletor de apps).
    /// Protege dados financeiros sensíveis de aparecerem em capturas de tela do sistema.
    func sceneWillResignActive(_ scene: UIScene) {
        guard let window else { return }
        removePrivacyOverlay()

        let overlay = UIView(frame: window.bounds)
        overlay.tag = privacyOverlayTag
        overlay.accessibilityIdentifier = "privacy.overlay"
        overlay.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(fixedHex: "#081220")
                : UIColor(fixedHex: "#E6EAEE")
        }
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        window.addSubview(overlay)
        privacyOverlay = overlay
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        removePrivacyOverlay()
    }

    /// Remove o desfoque quando o app volta a ficar ativo — cobre tanto retornos do background
    /// quanto dismissals de interrupções leves (central de controle, ligação, notificação).
    func sceneDidBecomeActive(_ scene: UIScene) {
        removePrivacyOverlay()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        removePrivacyOverlay()
    }

    private func removePrivacyOverlay() {
        privacyOverlay?.removeFromSuperview()
        window?.subviews
            .filter { $0.tag == privacyOverlayTag || $0.accessibilityIdentifier == "privacy.overlay" }
            .forEach { $0.removeFromSuperview() }
        privacyOverlay = nil
    }
}
