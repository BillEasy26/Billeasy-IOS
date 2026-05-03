//
//  AppRuntimeConfiguration.swift
//  BillEasy
//

import Foundation

/// Modo de autenticação do app: local (dados salvos no dispositivo) ou remoto (API real).
enum AppAuthMode: String {
    case local
    case remote
}

/// Centraliza todas as flags de execução lidas de argumentos de processo e variáveis de ambiente.
/// Evita que `ProcessInfo` fique espalhado pelo código e facilita o controle dos testes de UI.
enum AppRuntimeConfiguration {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Retorna `true` se o app estiver sendo executado por testes automáticos (UI ou unitários).
    static var isRunningAutomatedTests: Bool {
        isRunningUITests || environment["XCTestConfigurationFilePath"] != nil
    }

    /// Lê o modo de autenticação do `Info.plist`.
    /// Em testes automáticos, sempre retorna `.local` para garantir determinismo.
    static var authMode: AppAuthMode {
        if isRunningAutomatedTests { return .local }

        guard
            let rawMode = Bundle.main.object(forInfoDictionaryKey: "APP_AUTH_MODE") as? String,
            let mode = AppAuthMode(rawValue: rawMode.lowercased())
        else {
            return .local
        }
        return mode
    }

    /// Se `true`, todos os `UserDefaults` são apagados ao iniciar o app.
    /// Ativado pelo argumento `-reset-local-data` nos testes de UI.
    static var shouldResetLocalDataOnLaunch: Bool {
        arguments.contains("-reset-local-data")
    }

    /// Pula alertas de permissão (câmera, microfone, etc.) durante testes de interface.
    static var shouldSkipPermissionOnboarding: Bool {
        arguments.contains("-skip-permission-onboarding")
    }

    /// Indica que o app está sendo executado por testes de UI (XCUITest).
    static var isRunningUITests: Bool {
        arguments.contains("-ui-testing")
    }

    /// Desativa animações UIKit para que os testes de UI sejam mais rápidos e previsíveis.
    static var shouldDisableAnimations: Bool {
        arguments.contains("-disable-ui-animations")
            || environment["UITEST_DISABLE_ANIMATIONS"] == "1"
            || isRunningUITests
    }

    /// Se `true`, cria uma sessão local antes de exibir o app principal (útil em testes que precisam de login).
    static var shouldSeedAuthenticatedSession: Bool {
        arguments.contains("-seed-auth-session")
    }

    /// E-mail usado para abrir direto a tela de confirmação de cadastro (sem passar pelo backend).
    /// Configurado via a variável de ambiente `UITEST_REGISTER_CONFIRMATION_EMAIL`.
    static var registerConfirmationPreviewEmail: String? {
        guard let rawValue = environment["UITEST_REGISTER_CONFIRMATION_EMAIL"] else { return nil }
        let email = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? nil : email
    }

    /// Caminho local de um PDF para abrir direto a tela de revisão de arquivo de contrato.
    /// Pode ser passado via variável de ambiente `UITEST_CONTRACT_FILE_REVIEW_PATH`
    /// ou pelo argumento `-preview-contract-file-review <caminho>`.
    static var contractFileReviewPreviewURL: URL? {
        if let rawValue = environment["UITEST_CONTRACT_FILE_REVIEW_PATH"] {
            let path = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }

        guard let flagIndex = arguments.firstIndex(of: "-preview-contract-file-review") else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }

        let path = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    /// Força o tema escuro (`true`) ou claro (`false`) durante testes e inspeções visuais.
    /// Configurado via `UITEST_FORCE_DARK_MODE` com os valores `1/true/yes` ou `0/false/no`.
    /// Retorna `nil` se a variável não estiver definida (sem forçar nenhum tema).
    static var forcedDarkModeEnabled: Bool? {
        guard let rawValue = environment["UITEST_FORCE_DARK_MODE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return nil }

        switch rawValue {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}
