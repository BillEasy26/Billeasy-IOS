//
//  AuthModels.swift
//  BillEasy
//

import Foundation

/// Provedor de identidade usado no login.
enum AuthProvider: String, Codable {
    case email
    case google
    case apple
}

/// Representa a sessão autenticada de um usuário.
/// Contém os dados necessários para personalizar a experiência e controlar o acesso às funcionalidades.
struct AuthSession: Codable {
    let userID: String
    let displayName: String
    let email: String
    let provider: AuthProvider

    /// URL do avatar do usuário (opcional, vindo do Google ou perfil remoto).
    let avatarURL: String?

    /// ID da empresa à qual o usuário está vinculado como credor. `nil` se não tiver empresa.
    let empresaID: String?

    /// Telefone do usuário (opcional).
    let phone: String?

    /// Lista de papéis/permissões do usuário (ex.: `"USUARIO"`, `"ADMIN"`, `"SUPER_ADMIN"`).
    let roles: [String]

    /// Indica se o usuário possui um perfil de devedor cadastrado.
    let hasDebtorProfile: Bool

    init(
        userID: String,
        displayName: String,
        email: String,
        provider: AuthProvider,
        avatarURL: String? = nil,
        empresaID: String? = nil,
        phone: String? = nil,
        roles: [String] = [],
        hasDebtorProfile: Bool = false
    ) {
        self.userID = userID
        self.displayName = displayName
        self.email = email
        self.provider = provider
        self.avatarURL = avatarURL
        self.empresaID = empresaID
        self.phone = phone
        self.roles = roles
        self.hasDebtorProfile = hasDebtorProfile
    }

    /// `true` se o usuário é administrador (`ADMIN` ou `SUPER_ADMIN`).
    /// Administradores não acessam os workspaces operacionais de credor ou devedor.
    var isAdminLike: Bool {
        let normalized = roles.map { $0.uppercased() }
        return normalized.contains("SUPER_ADMIN") || normalized.contains("ADMIN")
    }

    /// `true` se o usuário pode ver o workspace de credor (recebimentos, dívidas, contratos).
    /// Requer empresa vinculada e não ser administrador.
    var canAccessCreditorWorkspace: Bool {
        guard !isAdminLike else { return false }
        return hasNonEmptyCompany
    }

    /// `true` se o usuário pode ver o workspace de devedor (dívidas a pagar).
    /// Requer perfil de devedor cadastrado e não ser administrador.
    var canAccessDebtorWorkspace: Bool {
        guard !isAdminLike else { return false }
        return hasDebtorProfile
    }

    /// `true` quando a conta deve abrir com o workspace vazio no mobile
    /// (administradores sem empresa nem perfil de devedor).
    var shouldStartWithEmptyWorkspace: Bool {
        isAdminLike && !hasNonEmptyCompany && !hasDebtorProfile
    }

    /// `true` se o `empresaID` está preenchido (não nulo e não vazio).
    private var hasNonEmptyCompany: Bool {
        empresaID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
