import Testing
@testable import BillEasy

struct LocalAuthStoreTests {

    @Test("Register normalizes email and creates current session")
    func registerCreatesCurrentSession() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let store = LocalAuthStore(defaults: helper.defaults)
        let session = try store.register(
            nome: "Teste",
            email: "  USER@Example.COM  ",
            telefone: "11999999999",
            cpfCnpj: "12345678901",
            senha: "123456"
        )

        #expect(session.email == "user@example.com")
        #expect(store.currentSession()?.userID == session.userID)
    }

    @Test("Duplicate register with same email is blocked")
    func registerDuplicateEmailThrows() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let store = LocalAuthStore(defaults: helper.defaults)
        _ = try store.register(nome: "Primeiro", email: "dup@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        do {
            _ = try store.register(nome: "Segundo", email: " DUP@teste.com ", telefone: "", cpfCnpj: "", senha: "123")
            Issue.record("Expected emailAlreadyRegistered to be thrown.")
        } catch AuthServiceError.emailAlreadyRegistered {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Login accepts normalized email and valid password")
    func loginWithNormalizedEmailSucceeds() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let store = LocalAuthStore(defaults: helper.defaults)
        let registered = try store.register(nome: "Usuario", email: "login@teste.com", telefone: "", cpfCnpj: "", senha: "senha123")

        let session = try store.login(email: "  LOGIN@teste.com ", senha: "senha123")
        #expect(session.userID == registered.userID)
        #expect(store.currentSession()?.email == "login@teste.com")
    }

    @Test("Login fails with invalid password")
    func loginInvalidPasswordThrows() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let store = LocalAuthStore(defaults: helper.defaults)
        _ = try store.register(nome: "Usuario", email: "senha@teste.com", telefone: "", cpfCnpj: "", senha: "correta")

        do {
            _ = try store.login(email: "senha@teste.com", senha: "errada")
            Issue.record("Expected invalidCredentials to be thrown.")
        } catch AuthServiceError.invalidCredentials {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Social login reuses existing account by email")
    func socialLoginReusesExistingAccount() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let store = LocalAuthStore(defaults: helper.defaults)
        let registered = try store.register(nome: "Conta Base", email: "social@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        let social = try store.loginSocial(provider: .google, email: "SOCIAL@teste.com", nome: "Google Nome")
        #expect(social.userID == registered.userID)
        #expect(social.provider == .google)
    }

    @Test("Password reset fails for unknown account")
    func passwordResetUnknownEmailThrows() {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let store = LocalAuthStore(defaults: helper.defaults)

        do {
            try store.requestPasswordReset(email: "naoexiste@teste.com")
            Issue.record("Expected accountNotFound to be thrown.")
        } catch AuthServiceError.accountNotFound {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Logout clears current session")
    func logoutClearsSession() throws {
        let helper = TestDefaultsHelper()
        defer { helper.cleanup() }

        let store = LocalAuthStore(defaults: helper.defaults)
        _ = try store.register(nome: "Sessao", email: "sessao@teste.com", telefone: "", cpfCnpj: "", senha: "123")

        store.logout()
        #expect(store.currentSession() == nil)
    }
}
