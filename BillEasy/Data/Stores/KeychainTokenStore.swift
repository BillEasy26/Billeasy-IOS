//
//  KeychainTokenStore.swift
//  BillEasy
//

import Foundation
import Security

/// Persiste os tokens de acesso e refresh no Keychain do iOS.
/// Os tokens sobrevivem ao encerramento do app e só são acessíveis após o primeiro desbloqueio do dispositivo.
final class KeychainTokenStore {

    /// Chaves usadas para identificar cada token no Keychain.
    private enum Key {
        static let accessToken = "billeasy.token.access"
        static let refreshToken = "billeasy.token.refresh"
    }

    static let shared = KeychainTokenStore()
    private init() {}

    // MARK: - Escrita

    /// Salva o token de acesso (JWT de curta duração) no Keychain.
    func saveAccessToken(_ token: String) {
        save(token, forKey: Key.accessToken)
    }

    /// Salva o token de refresh (longa duração) no Keychain.
    func saveRefreshToken(_ token: String) {
        save(token, forKey: Key.refreshToken)
    }

    // MARK: - Leitura

    /// Retorna o token de acesso salvo, ou `nil` se não houver nenhum.
    func loadAccessToken() -> String? {
        load(forKey: Key.accessToken)
    }

    /// Retorna o token de refresh salvo, ou `nil` se não houver nenhum.
    func loadRefreshToken() -> String? {
        load(forKey: Key.refreshToken)
    }

    // MARK: - Limpeza

    /// Remove ambos os tokens do Keychain (usado no logout).
    func clear() {
        delete(forKey: Key.accessToken)
        delete(forKey: Key.refreshToken)
    }

    // MARK: - Privado

    /// Grava um valor no Keychain. Se o valor for vazio, apaga a entrada existente.
    private func save(_ value: String, forKey key: String) {
        guard !value.isEmpty else {
            delete(forKey: key)
            return
        }
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "billeasy",
            kSecValueData: data,
            // Acessível após o primeiro desbloqueio; não migra via iCloud Backup.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Lê um valor do Keychain. Retorna `nil` se a chave não existir.
    private func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "billeasy",
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Apaga uma entrada do Keychain pela chave.
    private func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: "billeasy"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
