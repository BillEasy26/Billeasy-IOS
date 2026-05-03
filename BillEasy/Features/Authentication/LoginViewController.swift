//
//  LoginViewController.swift
//  BillEasy
//
//  Created by Samuel Jammes  on 10/03/26.
//

import AuthenticationServices
import UIKit

final class LoginViewController: UIViewController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, UITextFieldDelegate {
    private struct LoginFormInput {
        let email: String
        let password: String
    }

    var onLoginSuccess: ((AuthSession) -> Void)?
    var prefilledEmail: String?
    var startWithAppleLogin = false
    var startWithGoogleLogin = false

    private let formPanel = UIView()
    private let cardGradientLayer = CAGradientLayer()
    private let neuralBackgroundView = AnimatedNeuralBackgroundView(palette: .authDark)
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .interactive
        sv.contentInsetAdjustmentBehavior = .never
        return sv
    }()
    private let emailUnderline = UIView()
    private let passwordUnderline = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let authService: AuthService
    private let googleOAuthService = GoogleOAuthService()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Entrar no Billeasy.ia"
        label.textColor = .white
        label.applyScaledFont(size: 36, weight: .bold, textStyle: .largeTitle)
        label.numberOfLines = 2
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(systemName: "xmark")
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(hex: "#7F8A98")
        button.accessibilityLabel = "Fechar"
        button.accessibilityHint = "Fecha a tela de login."
        return button
    }()

    private let emailLabel = LoginViewController.makeFieldTitle("Email")
    private let passwordLabel = LoginViewController.makeFieldTitle("Senha")

    private lazy var emailTextField = makeInputField(
        placeholder: "seu@email.com"
    )

    private lazy var passwordTextField: UITextField = {
        let field = makeInputField(placeholder: "Digite sua senha")
        field.isSecureTextEntry = true
        field.textContentType = .password

        let eyeButton = UIButton(type: .system)
        eyeButton.setImage(UIImage(systemName: "eye"), for: .normal)
        eyeButton.tintColor = UIColor(hex: "#60728A")
        eyeButton.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        eyeButton.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        field.rightView = eyeButton
        field.rightViewMode = .always
        return field
    }()

    private lazy var orderedFields: [UITextField] = [
        emailTextField,
        passwordTextField
    ]

    private let loginButton: GradientButton = {
        let button = GradientButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Entrar", for: .normal)
        button.applyScaledTitleFont(size: 18, weight: .semibold, textStyle: .headline)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#5BB5D9", alpha: 0.7).cgColor
        return button
    }()

    private let separatorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "ou continue com"
        label.textColor = UIColor(hex: "#5F6D80")
        label.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)
        return label
    }()

    private let separatorLeftLine = LoginViewController.makeSeparatorLine()
    private let separatorRightLine = LoginViewController.makeSeparatorLine()
    private let signUpStack = UIStackView()

    private let googleButton = LoginViewController.makeSocialLoginButton(
        title: "Fazer login com Google",
        image: UIImage(named: "GoogleLogo"),
        accessibilityHint: "Continua o login com a sua conta Google."
    )

    private let appleButton = LoginViewController.makeSocialLoginButton(
        title: "Fazer login com Apple",
        image: UIImage(systemName: "applelogo"),
        accessibilityHint: "Continua o login com a sua conta Apple.",
        symbolPointSize: 18
    )

    private let forgotPasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Esqueceu sua senha?", for: .normal)
        button.setTitleColor(UIColor(hex: "#3EA8FF"), for: .normal)
        button.applyScaledTitleFont(size: 16, weight: .regular, textStyle: .body)
        return button
    }()

    private let signUpLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Ainda não tem conta?"
        label.textColor = UIColor(hex: "#6F7A89")
        label.applyScaledFont(size: 16, weight: .regular, textStyle: .body)
        return label
    }()

    private let signUpButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Comece grátis", for: .normal)
        button.setTitleColor(UIColor(hex: "#3EA8FF"), for: .normal)
        button.applyScaledTitleFont(size: 16, weight: .semibold, textStyle: .body)
        return button
    }()

    private let footerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(hex: "#0B1B2B", alpha: 0.52)
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor(hex: "#113454", alpha: 0.56).cgColor
        return view
    }()

    private let footerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Bem-vindo de volta! Gerencie seus contratos\ncom facilidade."
        label.textColor = UIColor(hex: "#6E7C8D")
        label.applyScaledFont(size: 14, weight: .regular, textStyle: .footnote)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private var isPasswordHidden = true
    private var isLoading = false
    private var hasAutoStartedAppleLogin = false
    private var hasAutoStartedGoogleLogin = false

    init(authService: AuthService = AuthService()) {
        self.authService = authService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupHierarchy()
        setupConstraints()
        setupActions()
        configureAccessibilityIdentifiers()
        applyPrefilledEmailIfNeeded()
#if DEBUG
        print("Rotas web mapeadas no app nativo: \(AppNavigationCatalog.all.count)")
#endif
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !isLoading else { return }

        if startWithGoogleLogin, !hasAutoStartedGoogleLogin {
            hasAutoStartedGoogleLogin = true
            googleTapped()
            return
        }

        guard startWithAppleLogin, !hasAutoStartedAppleLogin else { return }
        hasAutoStartedAppleLogin = true
        appleTapped()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cardGradientLayer.frame = formPanel.bounds
        if neuralBackgroundView.bounds.size != view.bounds.size {
            neuralBackgroundView.refreshLayout()
        }
    }

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#091A2D")
        configureTextFields()

        cardGradientLayer.colors = [
            UIColor(hex: "#0C1D30").cgColor,
            UIColor(hex: "#081220").cgColor
        ]
        cardGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        cardGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        formPanel.layer.insertSublayer(cardGradientLayer, at: 0)

        formPanel.layer.cornerRadius = 0
        formPanel.layer.borderWidth = 0
        formPanel.layer.borderColor = UIColor.clear.cgColor
        formPanel.layer.masksToBounds = true

        emailUnderline.backgroundColor = UIColor(hex: "#34475F")
        passwordUnderline.backgroundColor = UIColor(hex: "#34475F")
        emailUnderline.translatesAutoresizingMaskIntoConstraints = false
        passwordUnderline.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = UIColor(hex: "#D9E7F7")
        loadingIndicator.hidesWhenStopped = true
    }

    private func configureTextFields() {
        emailTextField.keyboardType = .emailAddress
        emailTextField.textContentType = .username
        passwordTextField.textContentType = .password

        for (index, field) in orderedFields.enumerated() {
            field.delegate = self
            field.tag = index
            field.returnKeyType = index == orderedFields.count - 1 ? .done : .next
        }
    }

    private func applyPrefilledEmailIfNeeded() {
        guard let prefilledEmail, !prefilledEmail.isEmpty else { return }
        emailTextField.text = prefilledEmail
    }

    private func setupHierarchy() {
        formPanel.translatesAutoresizingMaskIntoConstraints = false
        neuralBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(neuralBackgroundView)
        view.addSubview(scrollView)
        scrollView.addSubview(formPanel)

        formPanel.addSubview(titleLabel)
        formPanel.addSubview(closeButton)
        formPanel.addSubview(emailLabel)
        formPanel.addSubview(emailTextField)
        formPanel.addSubview(emailUnderline)
        formPanel.addSubview(passwordLabel)
        formPanel.addSubview(passwordTextField)
        formPanel.addSubview(passwordUnderline)
        formPanel.addSubview(loginButton)
        formPanel.addSubview(separatorLabel)
        formPanel.addSubview(separatorLeftLine)
        formPanel.addSubview(separatorRightLine)
        formPanel.addSubview(googleButton)
        formPanel.addSubview(appleButton)
        formPanel.addSubview(forgotPasswordButton)

        signUpStack.translatesAutoresizingMaskIntoConstraints = false
        signUpStack.axis = .horizontal
        signUpStack.spacing = 6
        signUpStack.alignment = .center
        signUpStack.addArrangedSubview(signUpLabel)
        signUpStack.addArrangedSubview(signUpButton)
        formPanel.addSubview(signUpStack)

        formPanel.addSubview(footerContainer)
        footerContainer.addSubview(footerLabel)
        loginButton.addSubview(loadingIndicator)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            neuralBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            neuralBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            neuralBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            neuralBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            formPanel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            formPanel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            formPanel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            formPanel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            formPanel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            formPanel.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            titleLabel.topAnchor.constraint(equalTo: formPanel.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            emailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            emailLabel.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            emailLabel.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),

            emailTextField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 8),
            emailTextField.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            emailTextField.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            emailTextField.heightAnchor.constraint(equalToConstant: 28),

            emailUnderline.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 7),
            emailUnderline.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            emailUnderline.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            emailUnderline.heightAnchor.constraint(equalToConstant: 1),

            passwordLabel.topAnchor.constraint(equalTo: emailUnderline.bottomAnchor, constant: 22),
            passwordLabel.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            passwordLabel.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),

            passwordTextField.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 8),
            passwordTextField.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            passwordTextField.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            passwordTextField.heightAnchor.constraint(equalToConstant: 28),

            passwordUnderline.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 7),
            passwordUnderline.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            passwordUnderline.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            passwordUnderline.heightAnchor.constraint(equalToConstant: 1),

            loginButton.topAnchor.constraint(equalTo: passwordUnderline.bottomAnchor, constant: 26),
            loginButton.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            loginButton.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            loginButton.heightAnchor.constraint(equalToConstant: 46),

            loadingIndicator.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            loadingIndicator.trailingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: -16),

            separatorLabel.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 18),
            separatorLabel.centerXAnchor.constraint(equalTo: formPanel.centerXAnchor),

            separatorLeftLine.centerYAnchor.constraint(equalTo: separatorLabel.centerYAnchor),
            separatorLeftLine.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            separatorLeftLine.trailingAnchor.constraint(equalTo: separatorLabel.leadingAnchor, constant: -10),
            separatorLeftLine.heightAnchor.constraint(equalToConstant: 1),

            separatorRightLine.centerYAnchor.constraint(equalTo: separatorLabel.centerYAnchor),
            separatorRightLine.leadingAnchor.constraint(equalTo: separatorLabel.trailingAnchor, constant: 10),
            separatorRightLine.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            separatorRightLine.heightAnchor.constraint(equalToConstant: 1),

            googleButton.topAnchor.constraint(equalTo: separatorLabel.bottomAnchor, constant: 16),
            googleButton.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            googleButton.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            googleButton.heightAnchor.constraint(equalToConstant: 46),

            appleButton.topAnchor.constraint(equalTo: googleButton.bottomAnchor, constant: 10),
            appleButton.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            appleButton.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            appleButton.heightAnchor.constraint(equalToConstant: 46),

            forgotPasswordButton.topAnchor.constraint(equalTo: appleButton.bottomAnchor, constant: 16),
            forgotPasswordButton.centerXAnchor.constraint(equalTo: formPanel.centerXAnchor),

            signUpStack.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 10),
            signUpStack.centerXAnchor.constraint(equalTo: formPanel.centerXAnchor),

            footerContainer.topAnchor.constraint(greaterThanOrEqualTo: signUpStack.bottomAnchor, constant: 24),
            footerContainer.leadingAnchor.constraint(equalTo: formPanel.leadingAnchor, constant: 24),
            footerContainer.trailingAnchor.constraint(equalTo: formPanel.trailingAnchor, constant: -24),
            footerContainer.bottomAnchor.constraint(equalTo: formPanel.bottomAnchor, constant: -20),
            footerContainer.heightAnchor.constraint(equalToConstant: 74),

            footerLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 12),
            footerLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -12),
            footerLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor)
        ])
    }

    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        googleButton.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)
        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        signUpButton.addTarget(self, action: #selector(signUpTapped), for: .touchUpInside)
    }

    private func configureAccessibilityIdentifiers() {
        let mappings: [(UIView, String)] = [
            (closeButton, "login.closeButton"),
            (emailTextField, "login.emailField"),
            (passwordTextField, "login.passwordField"),
            (loginButton, "login.submitButton"),
            (googleButton, "login.googleButton"),
            (appleButton, "login.appleButton"),
            (forgotPasswordButton, "login.forgotPasswordButton"),
            (signUpButton, "login.signUpButton")
        ]

        mappings.forEach { view, identifier in
            view.accessibilityIdentifier = identifier
        }

        titleLabel.accessibilityTraits.insert(.header)
        emailTextField.accessibilityLabel = "Email"
        emailTextField.accessibilityHint = "Digite o seu e-mail de acesso."
        passwordTextField.accessibilityLabel = "Senha"
        passwordTextField.accessibilityHint = "Digite a sua senha."
        loginButton.accessibilityHint = "Envia o formulário e tenta autenticar a conta."
        signUpButton.accessibilityHint = "Abre o cadastro no site."
    }

    private func makeInputField(placeholder: String) -> UITextField {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.backgroundColor = .clear
        field.textColor = UIColor(hex: "#DCE6F3")
        field.tintColor = UIColor(hex: "#DCE6F3")
        field.applyScaledFont(size: 16, weight: .regular, textStyle: .body)
        field.borderStyle = .none
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.placeholder = placeholder
        field.setPlaceholderColor(UIColor(hex: "#5E6B7B"))
        return field
    }

    @objc private func closeTapped() {
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
            return
        }

        if presentingViewController != nil {
            dismiss(animated: true)
            return
        }

        view.endEditing(true)
    }

    @objc private func loginTapped() {
        let input = currentFormInput()

        if let validation = validate(input) {
            showAlert(title: validation.title, message: validation.message)
            return
        }

        Task {
            await performEmailLogin(email: input.email, senha: input.password)
        }
    }

    @objc private func googleTapped() {
        Task {
            await performGoogleLogin()
        }
    }

    @objc private func appleTapped() {
        if authService.isLocalMode {
            Task {
                await performAppleLogin(
                    identityToken: "local-token",
                    userIdentifier: UUID().uuidString,
                    email: emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                    fullName: "Conta Apple Local"
                )
            }
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    @objc private func forgotPasswordTapped() {
        let recoveryViewController = PasswordRecoveryViewController(authService: authService)
        recoveryViewController.prefilledEmail = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let navigationController {
            navigationController.pushViewController(recoveryViewController, animated: true)
            return
        }

        recoveryViewController.modalPresentationStyle = .fullScreen
        present(recoveryViewController, animated: true)
    }

    @objc private func signUpTapped() {
        guard let url = FrontendWebRouteBuilder.url(for: .register) else {
            showAlert(title: "Site indisponível", message: "Não encontrei a URL do site para continuar o cadastro.")
            return
        }

        UIApplication.shared.open(url) { [weak self] success in
            guard success == false else { return }
            self?.showAlert(title: "Não consegui abrir o site", message: "Tente novamente em instantes.")
        }
    }

    @objc private func togglePasswordVisibility() {
        isPasswordHidden.toggle()
        passwordTextField.isSecureTextEntry = isPasswordHidden
        if let button = passwordTextField.rightView as? UIButton {
            let imageName = isPasswordHidden ? "eye" : "eye.slash"
            button.setImage(UIImage(systemName: imageName), for: .normal)
        }
    }

    private func currentFormInput() -> LoginFormInput {
        LoginFormInput(
            email: emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            password: passwordTextField.text ?? ""
        )
    }

    private func validate(_ input: LoginFormInput) -> (title: String, message: String)? {
        guard !input.email.isEmpty else {
            return ("Dados incompletos", "Informe seu e-mail para continuar.")
        }

        guard !input.password.isEmpty else {
            return ("Dados incompletos", "Informe sua senha para continuar.")
        }

        return nil
    }

    private func performEmailLogin(email: String, senha: String) async {
        setLoading(true)
        defer { setLoading(false) }

        do {
            let session = try await authService.login(email: email, senha: senha)
            notifyLoginSuccess(session)
        } catch {
            showAlert(title: "Não foi possível entrar", message: error.localizedDescription)
        }
    }

    private func performGoogleLogin() async {
        Self.debugGoogleLogin("Starting Google login from LoginViewController.")
        setLoading(true)
        defer { setLoading(false) }

        var resolvedIdentity: GoogleOAuthIdentity?
        do {
            let identity = try await googleOAuthService.authenticate(presenter: self)
            resolvedIdentity = identity
            Self.debugGoogleLogin("OAuth completed for \(Self.redactedEmail(identity.email)). Calling backend.")
            let session = try await authService.loginWithGoogle(
                googleId: identity.googleID,
                email: identity.email,
                nome: identity.name,
                avatarURL: identity.avatarURL,
                idToken: identity.idToken
            )
            Self.debugGoogleLogin("Backend login completed. userID=\(session.userID)")
            notifyLoginSuccess(session)
        } catch GoogleOAuthServiceError.cancelled {
            Self.debugGoogleLogin("Google login cancelled by user/system.")
            return
        } catch {
            if let identity = resolvedIdentity,
               let authError = error as? AuthServiceError,
               authError.requiresOAuthProfileCompletion {
                Self.debugGoogleLogin("Backend requires OAuth profile completion.")
                presentGoogleProfileCompletion(for: identity)
                return
            }
            Self.debugGoogleLogin("Google login failed: \(error.localizedDescription)")
            showAlert(title: "Login com Google", message: error.localizedDescription)
        }
    }

    private func presentGoogleProfileCompletion(for identity: GoogleOAuthIdentity) {
        let controller = OAuthProfileCompletionViewController()
        controller.onSubmit = { [weak self, weak controller] input in
            guard let self else { return }
            Task {
                await self.completeGoogleProfile(identity: identity, input: input, controller: controller)
            }
        }
        present(controller, animated: true)
    }

    private func completeGoogleProfile(
        identity: GoogleOAuthIdentity,
        input: OAuthProfileCompletionInput,
        controller: OAuthProfileCompletionViewController?
    ) async {
        controller?.setSubmitting(true)
        defer { controller?.setSubmitting(false) }

        do {
            let session = try await authService.loginWithGoogle(
                googleId: identity.googleID,
                email: identity.email,
                nome: identity.name,
                avatarURL: identity.avatarURL,
                idToken: identity.idToken,
                documento: input.documento,
                telefone: input.telefone
            )
            Self.debugGoogleLogin("OAuth profile completed. userID=\(session.userID)")
            controller?.dismiss(animated: true) { [weak self] in
                self?.notifyLoginSuccess(session)
            }
        } catch {
            Self.debugGoogleLogin("OAuth profile completion failed: \(error.localizedDescription)")
            controller?.setError(error.localizedDescription)
        }
    }

    private func performAppleLogin(
        identityToken: String,
        userIdentifier: String,
        email: String?,
        fullName: String?
    ) async {
        setLoading(true)
        defer { setLoading(false) }

        do {
            let session = try await authService.loginWithApple(
                identityToken: identityToken,
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )
            notifyLoginSuccess(session)
        } catch {
            showAlert(title: "Login com Apple", message: error.localizedDescription)
        }
    }

    private func notifyLoginSuccess(_ session: AuthSession) {
        if let onLoginSuccess {
            onLoginSuccess(session)
            return
        }
        showAlert(title: "Login concluído", message: "Sessão autenticada para \(session.email).")
    }

    private func setLoading(_ loading: Bool) {
        guard isLoading != loading else { return }
        isLoading = loading
        loginButton.isEnabled = !loading
        googleButton.isEnabled = !loading
        appleButton.isEnabled = !loading
        forgotPasswordButton.isEnabled = !loading

        if loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func debugGoogleLogin(_ message: String) {
        #if DEBUG
        print("[BillEasy][GoogleLogin] \(message)")
        #endif
    }

    private static func redactedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let firstCharacter = parts[0].first else { return "redacted" }
        return "\(firstCharacter)***@\(parts[1])"
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let nextTag = textField.tag + 1
        if let nextField = view.viewWithTag(nextTag) as? UITextField {
            nextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            loginTapped()
        }
        return true
    }
}

private extension LoginViewController {
    static func makeSocialLoginButton(
        title: String,
        image: UIImage?,
        accessibilityHint: String,
        symbolPointSize: CGFloat? = nil
    ) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = image
        config.imagePlacement = .leading
        config.imagePadding = 10
        config.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 18, bottom: 11, trailing: 18)
        config.baseForegroundColor = UIColor(hex: "#DFE6F2")

        if let symbolPointSize {
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        }

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(hex: "#DFE6F2")
        button.backgroundColor = UIColor(hex: "#0C1D30", alpha: 0.26)
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#214567").cgColor
        button.applyScaledTitleFont(size: 16, weight: .medium, textStyle: .body)
        button.applyStableStateColors(
            normalBackground: UIColor(hex: "#0C1D30", alpha: 0.26),
            normalForeground: UIColor(hex: "#DFE6F2"),
            disabledBackground: UIColor(hex: "#0C1D30", alpha: 0.18),
            disabledForeground: UIColor(hex: "#8CA6BF")
        )
        button.accessibilityHint = accessibilityHint
        return button
    }

    static func makeFieldTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor(hex: "#8E9CAD")
        label.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)
        return label
    }

    static func makeSeparatorLine() -> UIView {
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = UIColor(hex: "#203146", alpha: 0.75)
        return line
    }
}

private final class GradientButton: UIButton {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        gradientLayer.colors = [
            UIColor(hex: "#2398C2").cgColor,
            UIColor(hex: "#1579A0").cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = layer.cornerRadius
    }
}

extension LoginViewController {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        guard
            let tokenData = credential.identityToken,
            let tokenString = String(data: tokenData, encoding: .utf8)
        else {
            showAlert(title: "Login com Apple", message: "Não foi possível ler o token de autenticação da Apple.")
            return
        }

        let userIdentifier = credential.user
        let email = credential.email
        let fullName = credential.fullName?.formatted()

        Task {
            await performAppleLogin(
                identityToken: tokenString,
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        showAlert(title: "Login com Apple", message: error.localizedDescription)
    }
}
