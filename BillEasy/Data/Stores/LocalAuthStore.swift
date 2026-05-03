//
//  LocalAuthStore.swift
//  BillEasy
//

import CryptoKit
import Foundation

/// Registro de um usuário salvo localmente no dispositivo.
private struct LocalUserRecord: Codable {
    let id: String
    let nome: String
    let email: String
    let telefone: String
    let cpfCnpj: String
    /// Senha armazenada no formato `<salt>$<sha256hex>` — nunca em texto puro.
    let senha: String
}

/// Snapshot completo do estado de autenticação local (lista de usuários + usuário ativo).
private struct LocalAuthSnapshot: Codable {
    var users: [LocalUserRecord]
    var currentUserID: String?

    static let empty = LocalAuthSnapshot(users: [], currentUserID: nil)
}

/// Gerencia autenticação local (offline/testes) usando `UserDefaults`.
/// Não se comunica com nenhuma API. Usado quando `APP_AUTH_MODE = local`.
final class LocalAuthStore {
    private let defaults: UserDefaults
    private let snapshotKey = "billeasy.local.auth.snapshot.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Interface pública

    /// Retorna a sessão do usuário atualmente autenticado, ou `nil` se ninguém estiver logado.
    func currentSession() -> AuthSession? {
        let snapshot = loadSnapshot()
        guard
            let userID = snapshot.currentUserID,
            let user = snapshot.users.first(where: { $0.id == userID })
        else { return nil }
        return makeSession(from: user)
    }

    /// Cadastra um novo usuário local. Lança erro se o e-mail já estiver registrado.
    /// - Returns: Sessão criada para o novo usuário.
    @discardableResult
    func register(nome: String, email: String, telefone: String, cpfCnpj: String, senha: String) throws -> AuthSession {
        let normalizedEmail = normalizeEmail(email)
        var snapshot = loadSnapshot()

        guard findUser(withNormalizedEmail: normalizedEmail, in: snapshot) == nil else {
            throw AuthServiceError.emailAlreadyRegistered
        }

        let user = LocalUserRecord(
            id: UUID().uuidString,
            nome: nome,
            email: normalizedEmail,
            telefone: telefone,
            cpfCnpj: cpfCnpj,
            senha: Self.makePasswordRecord(for: senha)
        )
        snapshot.users.append(user)
        snapshot.currentUserID = user.id
        saveSnapshot(snapshot)
        return makeSession(from: user)
    }

    /// Autentica um usuário existente com e-mail e senha.
    /// Lança erro se o e-mail não existir ou a senha estiver errada.
    @discardableResult
    func login(email: String, senha: String) throws -> AuthSession {
        let normalizedEmail = normalizeEmail(email)
        var snapshot = loadSnapshot()

        guard let user = findUser(withNormalizedEmail: normalizedEmail, in: snapshot) else {
            throw AuthServiceError.invalidCredentials
        }
        guard Self.verifyPassword(senha, against: user.senha) else {
            throw AuthServiceError.invalidCredentials
        }
        snapshot.currentUserID = user.id
        saveSnapshot(snapshot)
        return makeSession(from: user)
    }

    /// Autentica (ou cria) um usuário via provedor social (Google, Apple).
    /// Se o e-mail já estiver cadastrado, reaproveita a conta existente.
    @discardableResult
    func loginSocial(provider: AuthProvider, email: String, nome: String) throws -> AuthSession {
        let normalizedEmail = normalizeEmail(email)
        var snapshot = loadSnapshot()

        if let existing = findUser(withNormalizedEmail: normalizedEmail, in: snapshot) {
            snapshot.currentUserID = existing.id
            saveSnapshot(snapshot)
            return makeSession(from: existing, provider: provider)
        }

        let newUser = LocalUserRecord(
            id: UUID().uuidString,
            nome: nome,
            email: normalizedEmail,
            telefone: "",
            cpfCnpj: "",
            // Senha aleatória: conta social não usa senha, mas o registro exige o campo.
            senha: Self.makePasswordRecord(for: UUID().uuidString)
        )
        snapshot.users.append(newUser)
        snapshot.currentUserID = newUser.id
        saveSnapshot(snapshot)
        return makeSession(from: newUser, provider: provider)
    }

    /// Verifica se o e-mail existe antes de simular o fluxo local de recuperação de senha.
    /// Lança erro se a conta não for encontrada.
    func requestPasswordReset(email: String) throws {
        let normalizedEmail = normalizeEmail(email)
        let snapshot = loadSnapshot()
        guard findUser(withNormalizedEmail: normalizedEmail, in: snapshot) != nil else {
            throw AuthServiceError.accountNotFound
        }
    }

    /// Remove a sessão atual sem apagar os dados cadastrados do usuário.
    func logout() {
        var snapshot = loadSnapshot()
        snapshot.currentUserID = nil
        saveSnapshot(snapshot)
    }

    /// Anonimiza os dados do usuário atual (fluxo LGPD de exclusão de conta).
    /// Substitui nome, e-mail, telefone e CPF/CNPJ por valores genéricos e encerra a sessão.
    func anonymizeCurrentAccount(reason: String) {
        var snapshot = loadSnapshot()
        guard
            let currentUserID = snapshot.currentUserID,
            let index = snapshot.users.firstIndex(where: { $0.id == currentUserID })
        else { return }

        snapshot.users[index] = LocalUserRecord(
            id: snapshot.users[index].id,
            nome: "Conta Anonimizada",
            email: "anon+\(currentUserID.prefix(8))@billeasy.invalid",
            telefone: "",
            cpfCnpj: "",
            senha: Self.makePasswordRecord(for: UUID().uuidString)
        )
        snapshot.currentUserID = nil
        saveSnapshot(snapshot)
    }

    // MARK: - Segurança de senha

    /// Gera um registro seguro no formato `<salt>$<sha256hex>`.
    /// O salt aleatório garante que duas senhas iguais produzam hashes diferentes.
    private static func makePasswordRecord(for password: String) -> String {
        let salt = UUID().uuidString
        return "\(salt)$\(sha256Hex(salt: salt, password: password))"
    }

    /// Compara a senha informada com o registro armazenado.
    /// Suporta o formato atual `<salt>$<hash>` e aceita texto puro legado para migração transparente.
    private static func verifyPassword(_ password: String, against record: String) -> Bool {
        let parts = record.split(separator: "$", maxSplits: 1)
        guard parts.count == 2 else { return record == password }
        let salt = String(parts[0])
        let storedHash = String(parts[1])
        return sha256Hex(salt: salt, password: password) == storedHash
    }

    /// Calcula SHA-256 de `"<salt>:<senha>"` e retorna em hexadecimal.
    private static func sha256Hex(salt: String, password: String) -> String {
        let digest = SHA256.hash(data: Data("\(salt):\(password)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistência

    /// Carrega o snapshot completo dos dados de autenticação do `UserDefaults`.
    /// Retorna um snapshot vazio se não houver dados salvos ou se a decodificação falhar.
    private func loadSnapshot() -> LocalAuthSnapshot {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(LocalAuthSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// Salva o snapshot completo no `UserDefaults`. Substitui sempre o estado anterior inteiro.
    private func saveSnapshot(_ snapshot: LocalAuthSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    // MARK: - Auxiliares

    /// Normaliza o e-mail para minúsculas e sem espaços, garantindo unicidade independente de capitalização.
    private func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Cria um objeto `AuthSession` a partir de um registro local.
    private func makeSession(from user: LocalUserRecord, provider: AuthProvider = .email) -> AuthSession {
        AuthSession(userID: user.id, displayName: user.nome, email: user.email, provider: provider)
    }

    /// Busca um usuário pelo e-mail já normalizado dentro do snapshot.
    private func findUser(withNormalizedEmail email: String, in snapshot: LocalAuthSnapshot) -> LocalUserRecord? {
        snapshot.users.first(where: { $0.email == email })
    }
}
