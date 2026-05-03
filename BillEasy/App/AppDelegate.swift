//
//  AppDelegate.swift
//  BillEasy
//

import UIKit

/// Ponto de entrada do aplicativo. Gerencia o ciclo de vida global (antes das cenas).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Chamado logo depois que o app termina de inicializar.
    /// Aqui preparamos o estado inicial: limpamos dados de teste, aplicamos tema e desativamos animações se necessário.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Limpa todos os UserDefaults ao iniciar — útil para rodar testes do zero.
        if AppRuntimeConfiguration.shouldResetLocalDataOnLaunch,
           let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            UserDefaults.standard.synchronize()
        }

        // Permite forçar o tema escuro ou claro via variável de ambiente nos testes de UI.
        if let forcedDarkModeEnabled = AppRuntimeConfiguration.forcedDarkModeEnabled {
            UserDefaults.standard.set(forcedDarkModeEnabled, forKey: "billeasy.theme.dark_mode_enabled")
        }

        // Desativa animações para que os testes de UI sejam mais rápidos e estáveis.
        if AppRuntimeConfiguration.shouldDisableAnimations {
            UIView.setAnimationsEnabled(false)
        }

        return true
    }

    /// Retorna a configuração da cena a ser criada. Usamos sempre a configuração padrão do Info.plist.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
