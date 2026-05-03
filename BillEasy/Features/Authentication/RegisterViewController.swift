//
//  RegisterViewController.swift
//  BillEasy
//

import AuthenticationServices
import UIKit

/// Aqui eu concentro o fluxo de criacao de conta local/remota e a validacao inicial do formulario.
final class RegisterViewController: UIViewController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, UITextFieldDelegate {
    /// Aqui eu devolvo a sessao criada para o fluxo local, que ainda nao depende de verificacao por email.
    var onRegisterSuccess: ((AuthSession) -> Void)?
    /// Aqui eu aviso o fluxo pai quando o cadastro remoto precisa seguir para a confirmação de e-mail.
    var onEmailConfirmationRequired: ((String) -> Void)?

    private let authService = AuthService()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let formStack = UIStackView()
    private let neuralBackgroundView = AnimatedNeuralBackgroundView(palette: .authDark)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let googleOAuthService = GoogleOAuthService()

    /// Aqui eu agrupo os dados do formulario para validar e registrar sem ficar lendo campo por campo toda hora.
    private struct RegisterFormInput {
        let nome: String
        let email: String
        let telefone: String
        let cpfCnpj: String
        let senha: String
        let confirmarSenha: String
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Criar conta Billeasy.ia"
        label.textColor = .white
        label.applyScaledFont(size: 30, weight: .bold, textStyle: .largeTitle)
        label.numberOfLines = 2
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = UIColor(hex: "#7F8A98")
        button.accessibilityLabel = "Fechar"
        button.accessibilityHint = "Fecha a tela de cadastro."
        return button
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Preencha os dados abaixo para criar sua conta."
        label.textColor = UIColor(hex: "#8EA1B8")
        label.applyScaledFont(size: 14, weight: .regular, textStyle: .body)
        label.numberOfLines = 0
        return label
    }()

    private let nomeField = RegisterViewController.makeField(
        placeholder: "Seu nome completo",
        keyboardType: .default,
        secure: false
    )

    private let emailField = RegisterViewController.makeField(
        placeholder: "seu@email.com",
        keyboardType: .emailAddress,
        secure: false
    )

    private let telefoneField = RegisterViewController.makeField(
        placeholder: "(00) 00000-0000",
        keyboardType: .numberPad,
        secure: false
    )

    private let cpfCnpjField = RegisterViewController.makeField(
        placeholder: "000.000.000-00 ou 00.000.000/0000-00",
        keyboardType: .numberPad,
        secure: false
    )

    private let senhaField = RegisterViewController.makeField(
        placeholder: "Digite sua senha",
        keyboardType: .default,
        secure: true
    )

    private let confirmarSenhaField = RegisterViewController.makeField(
        placeholder: "Confirme sua senha",
        keyboardType: .default,
        secure: true
    )

    /// Aqui eu mantenho a ordem oficial de navegacao entre campos para reaproveitar em foco e configuracao.
    private lazy var orderedFields: [UITextField] = [
        nomeField,
        emailField,
        telefoneField,
        cpfCnpjField,
        senhaField,
        confirmarSenhaField
    ]

    /// Aqui eu descrevo as secoes do formulario em um unico lugar para evitar repeticao no layout.
    private lazy var formSections: [(title: String, field: UITextField)] = [
        ("Nome completo", nomeField),
        ("Email", emailField),
        ("Telefone", telefoneField),
        ("CPF/CNPJ", cpfCnpjField),
        ("Senha", senhaField),
        ("Confirmar senha", confirmarSenhaField)
    ]

    private let errorLabel: InsetLabel = {
        let label = InsetLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = UIColor(hex: "#F7FBFF")
        label.backgroundColor = UIColor(hex: "#8B1018", alpha: 0.92)
        label.layer.cornerRadius = 12
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.layer.borderWidth = 1
        label.layer.borderColor = UIColor(hex: "#CE5B5B", alpha: 0.78).cgColor
        label.applyScaledFont(size: 13, weight: .semibold, textStyle: .callout)
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityTraits = [.staticText]
        return label
    }()

    private let registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Criar conta", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.applyScaledTitleFont(size: 17, weight: .semibold, textStyle: .headline)
        button.backgroundColor = UIColor(hex: "#2398C2")
        button.layer.cornerRadius = 22
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#5BB5D9", alpha: 0.7).cgColor
        return button
    }()

    private let separatorContainer = UIView()
    private let separatorLeftLine = UIView()
    private let separatorRightLine = UIView()

    private let separatorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "ou"
        label.textColor = UIColor(hex: "#5F6D80")
        label.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)
        return label
    }()

    private let googleButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Entrar com Google"
        configuration.image = UIImage(named: "GoogleLogo")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        configuration.baseForegroundColor = .white

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(fixedHex: "#000000")
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(fixedHex: "#FFFFFF", alpha: 0.88).cgColor
        button.applyScaledTitleFont(size: 16, weight: .semibold, textStyle: .body)
        button.applyStableStateColors(
            normalBackground: UIColor(fixedHex: "#000000"),
            normalForeground: UIColor(fixedHex: "#FFFFFF"),
            disabledBackground: UIColor(fixedHex: "#111111"),
            disabledForeground: UIColor(fixedHex: "#B7CBE3")
        )
        button.accessibilityHint = "Continua o cadastro com a sua conta Google."
        return button
    }()

    private let appleButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Entrar com Apple"
        configuration.image = UIImage(systemName: "applelogo")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        configuration.baseForegroundColor = .white
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(fixedHex: "#000000")
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(fixedHex: "#FFFFFF", alpha: 0.88).cgColor
        button.applyScaledTitleFont(size: 16, weight: .semibold, textStyle: .body)
        button.applyStableStateColors(
            normalBackground: UIColor(fixedHex: "#000000"),
            normalForeground: UIColor(fixedHex: "#FFFFFF"),
            disabledBackground: UIColor(fixedHex: "#111111"),
            disabledForeground: UIColor(fixedHex: "#B7CBE3")
        )
        button.accessibilityHint = "Continua o cadastro com a sua conta Apple."
        return button
    }()

    private let backToLoginButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Já tem conta? Entrar", for: .normal)
        button.setTitleColor(UIColor(hex: "#3EA8FF"), for: .normal)
        button.applyScaledTitleFont(size: 14, weight: .regular, textStyle: .body)
        return button
    }()

    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupHierarchy()
        setupConstraints()
        setupActions()
        configureAccessibilityIdentifiers()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        neuralBackgroundView.refreshLayout()
    }

    /// Aqui eu configuro o visual base da tela antes de inserir qualquer subview.
    private func setupView() {
        view.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive

        contentView.translatesAutoresizingMaskIntoConstraints = false

        formStack.translatesAutoresizingMaskIntoConstraints = false
        formStack.axis = .vertical
        formStack.spacing = 14
    }

    /// Aqui eu monto a hierarquia uma vez e reaproveito a lista de secoes para nao duplicar layout.
    private func setupHierarchy() {
        neuralBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(neuralBackgroundView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(titleLabel)
        contentView.addSubview(closeButton)
        contentView.addSubview(formStack)

        formStack.addArrangedSubview(subtitleLabel)
        formSections.forEach { section in
            formStack.addArrangedSubview(makeSection(title: section.title, field: section.field))
        }
        formStack.addArrangedSubview(errorLabel)
        formStack.addArrangedSubview(registerButton)
        formStack.addArrangedSubview(separatorContainer)
        formStack.addArrangedSubview(googleButton)
        formStack.addArrangedSubview(appleButton)
        formStack.addArrangedSubview(backToLoginButton)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        registerButton.addSubview(loadingIndicator)

        separatorContainer.translatesAutoresizingMaskIntoConstraints = false
        separatorLeftLine.translatesAutoresizingMaskIntoConstraints = false
        separatorRightLine.translatesAutoresizingMaskIntoConstraints = false
        separatorLeftLine.backgroundColor = UIColor(hex: "#203146", alpha: 0.75)
        separatorRightLine.backgroundColor = UIColor(hex: "#203146", alpha: 0.75)
        separatorContainer.addSubview(separatorLeftLine)
        separatorContainer.addSubview(separatorLabel)
        separatorContainer.addSubview(separatorRightLine)
    }

    /// Aqui eu prendo as principais constraints da tela para manter scroll e formulario consistentes.
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            neuralBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            neuralBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            neuralBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            neuralBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            formStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            formStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            formStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            formStack.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            registerButton.heightAnchor.constraint(equalToConstant: 46),
            separatorContainer.heightAnchor.constraint(equalToConstant: 20),
            googleButton.heightAnchor.constraint(equalToConstant: 46),
            appleButton.heightAnchor.constraint(equalToConstant: 46),
            backToLoginButton.heightAnchor.constraint(equalToConstant: 34),

            loadingIndicator.centerYAnchor.constraint(equalTo: registerButton.centerYAnchor),
            loadingIndicator.trailingAnchor.constraint(equalTo: registerButton.trailingAnchor, constant: -16),

            separatorLabel.centerXAnchor.constraint(equalTo: separatorContainer.centerXAnchor),
            separatorLabel.centerYAnchor.constraint(equalTo: separatorContainer.centerYAnchor),

            separatorLeftLine.leadingAnchor.constraint(equalTo: separatorContainer.leadingAnchor),
            separatorLeftLine.trailingAnchor.constraint(equalTo: separatorLabel.leadingAnchor, constant: -12),
            separatorLeftLine.centerYAnchor.constraint(equalTo: separatorContainer.centerYAnchor),
            separatorLeftLine.heightAnchor.constraint(equalToConstant: 1),

            separatorRightLine.leadingAnchor.constraint(equalTo: separatorLabel.trailingAnchor, constant: 12),
            separatorRightLine.trailingAnchor.constraint(equalTo: separatorContainer.trailingAnchor),
            separatorRightLine.centerYAnchor.constraint(equalTo: separatorContainer.centerYAnchor),
            separatorRightLine.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    /// Aqui eu ligo eventos e preparo o comportamento padrao de teclado de todos os campos.
    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        registerButton.addTarget(self, action: #selector(registerTapped), for: .touchUpInside)
        googleButton.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)
        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
        backToLoginButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        telefoneField.addTarget(self, action: #selector(telefoneChanged), for: .editingChanged)
        cpfCnpjField.addTarget(self, action: #selector(cpfCnpjChanged), for: .editingChanged)

        for (index, field) in orderedFields.enumerated() {
            field.delegate = self
            field.tag = index
            field.returnKeyType = index == orderedFields.count - 1 ? .done : .next
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
    }

    /// Aqui eu deixo os ids de acessibilidade centralizados para teste e manutencao.
    private func configureAccessibilityIdentifiers() {
        let mappings: [(UIView, String)] = [
            (closeButton, "register.closeButton"),
            (nomeField, "register.nameField"),
            (emailField, "register.emailField"),
            (telefoneField, "register.phoneField"),
            (cpfCnpjField, "register.documentField"),
            (senhaField, "register.passwordField"),
            (confirmarSenhaField, "register.confirmPasswordField"),
            (registerButton, "register.submitButton"),
            (googleButton, "register.googleButton"),
            (appleButton, "register.appleButton"),
            (backToLoginButton, "register.backToLoginButton"),
            (errorLabel, "register.errorLabel")
        ]

        mappings.forEach { view, identifier in
            view.accessibilityIdentifier = identifier
        }

        titleLabel.accessibilityTraits.insert(.header)
        nomeField.accessibilityLabel = "Nome completo"
        emailField.accessibilityLabel = "Email"
        telefoneField.accessibilityLabel = "Telefone"
        cpfCnpjField.accessibilityLabel = "CPF ou CNPJ"
        senhaField.accessibilityLabel = "Senha"
        confirmarSenhaField.accessibilityLabel = "Confirmar senha"
        registerButton.accessibilityHint = "Valida os dados e cria uma nova conta local."
    }

    /// Aqui eu encapsulo o bloco visual de titulo + campo + linha para todas as secoes ficarem iguais.
    private func makeSection(title: String, field: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.textColor = UIColor(hex: "#8E9CAD")
        label.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)

        let underline = UIView()
        underline.backgroundColor = UIColor(hex: "#34475F")
        underline.translatesAutoresizingMaskIntoConstraints = false
        underline.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let stack = UIStackView(arrangedSubviews: [label, field, underline])
        stack.axis = .vertical
        stack.spacing = 7
        return stack
    }

    /// Aqui eu apenas fecho a tela sem alterar o fluxo pai.
    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    /// Aqui eu disparo o cadastro ja garantindo que o teclado saia da frente antes.
    @objc private func registerTapped() {
        view.endEditing(true)
        Task {
            await performRegister()
        }
    }

    /// Aqui eu reaproveito o mesmo callback do web para cadastro/login com Google a partir da tela de criar conta.
    @objc private func googleTapped() {
        view.endEditing(true)
        Task {
            await performGoogleRegister()
        }
    }

    /// Aqui eu formato telefone em tempo real para manter o input legivel.
    @objc private func telefoneChanged() {
        let digits = Formatters.digitsOnly(telefoneField.text ?? "")
        if digits.count <= 10 {
            telefoneField.text = formatAsPhone10(digits)
        } else {
            telefoneField.text = formatAsPhone11(digits)
        }
    }

    /// Aqui eu alterno automaticamente entre mascara de CPF e CNPJ conforme a quantidade de digitos.
    @objc private func cpfCnpjChanged() {
        cpfCnpjField.text = Formatters.formatCPFOrCNPJ(cpfCnpjField.text ?? "")
    }

    /// Aqui eu orquestro validacao, loading e feedback final do cadastro em um unico lugar.
    private func performRegister() async {
        let input = currentFormInput()

        if let validationMessage = validateForm(input) {
            setError(validationMessage)
            return
        }

        setError(nil)
        setLoading(true)
        defer { setLoading(false) }

        do {
            let session = try await authService.register(
                nome: input.nome,
                email: input.email,
                telefone: input.telefone,
                cpfCnpj: input.cpfCnpj,
                senha: input.senha
            )

            if authService.isLocalMode {
                dismiss(animated: true) { [weak self] in
                    self?.onRegisterSuccess?(session)
                }
                return
            }

            dismiss(animated: true) { [weak self] in
                self?.onEmailConfirmationRequired?(session.email)
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    /// Aqui eu reutilizo o OAuth real do Google para cadastro social sem duplicar regra entre login e registro.
    private func performGoogleRegister() async {
        setError(nil)
        setLoading(true)
        defer { setLoading(false) }

        var resolvedIdentity: GoogleOAuthIdentity?
        let prefill = currentGoogleCompletionPrefill()
        do {
            let identity = try await googleOAuthService.authenticate(presenter: self)
            resolvedIdentity = identity
            let session = try await authService.loginWithGoogle(
                googleId: identity.googleID,
                email: identity.email,
                nome: identity.name,
                avatarURL: identity.avatarURL,
                idToken: identity.idToken,
                documento: prefill?.documento,
                telefone: prefill?.telefone
            )

            dismiss(animated: true) { [weak self] in
                self?.onRegisterSuccess?(session)
            }
        } catch GoogleOAuthServiceError.cancelled {
            return
        } catch {
            if let identity = resolvedIdentity,
               let authError = error as? AuthServiceError,
               authError.requiresOAuthProfileCompletion {
                presentGoogleProfileCompletion(for: identity, prefill: prefill)
                return
            }
            setError(error.localizedDescription)
        }
    }

    private func currentGoogleCompletionPrefill() -> OAuthProfileCompletionInput? {
        let input = currentFormInput()
        guard !input.cpfCnpj.isEmpty || !input.telefone.isEmpty else { return nil }
        guard isValidCPFOrCNPJ(input.cpfCnpj), input.telefone.count == 10 || input.telefone.count == 11 else {
            return nil
        }
        return OAuthProfileCompletionInput(documento: input.cpfCnpj, telefone: input.telefone)
    }

    private func presentGoogleProfileCompletion(
        for identity: GoogleOAuthIdentity,
        prefill: OAuthProfileCompletionInput?
    ) {
        let controller = OAuthProfileCompletionViewController(
            initialDocumento: prefill?.documento,
            initialTelefone: prefill?.telefone
        )
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
            controller?.dismiss(animated: true) { [weak self] in
                self?.dismiss(animated: true) {
                    self?.onRegisterSuccess?(session)
                }
            }
        } catch {
            controller?.setError(error.localizedDescription)
        }
    }

    /// Aqui eu reutilizo o mesmo fluxo Apple do login para cadastro social sem abrir uma etapa paralela fora da autenticacao oficial.
    private func performAppleRegister(
        identityToken: String,
        userIdentifier: String,
        email: String?,
        fullName: String?
    ) async {
        setError(nil)
        setLoading(true)
        defer { setLoading(false) }

        do {
            let session = try await authService.loginWithApple(
                identityToken: identityToken,
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )

            dismiss(animated: true) { [weak self] in
                self?.onRegisterSuccess?(session)
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    /// Aqui eu tiro um snapshot do formulario para trabalhar com dados consistentes durante o submit.
    private func currentFormInput() -> RegisterFormInput {
        RegisterFormInput(
            nome: nomeField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            email: emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            telefone: Formatters.digitsOnly(telefoneField.text ?? ""),
            cpfCnpj: Formatters.digitsOnly(cpfCnpjField.text ?? ""),
            senha: senhaField.text ?? "",
            confirmarSenha: confirmarSenhaField.text ?? ""
        )
    }

    /// Aqui eu concentro as regras minimas de validacao para a tela nao vazar regra duplicada.
    private func validateForm(_ input: RegisterFormInput) -> String? {
        if input.nome.isEmpty || input.email.isEmpty || input.telefone.isEmpty || input.cpfCnpj.isEmpty || input.senha.isEmpty || input.confirmarSenha.isEmpty {
            return "Preencha todos os campos."
        }

        if !input.email.contains("@") || !input.email.contains(".") {
            return "Informe um e-mail válido."
        }

        if input.telefone.count < 10 {
            return "Informe um telefone válido."
        }

        if !isValidCPFOrCNPJ(input.cpfCnpj) {
            return "CPF/CNPJ inválido."
        }

        if input.senha != input.confirmarSenha {
            return "As senhas não coincidem."
        }

        if !isValidPasswordPolicy(input.senha) {
            return "A senha precisa ter 8+ caracteres, maiúscula, minúscula, número e especial."
        }

        return nil
    }

    /// Aqui eu sincronizo estado visual do loading para evitar multiplos submits acidentais.
    private func setLoading(_ loading: Bool) {
        guard isLoading != loading else { return }
        isLoading = loading
        registerButton.isEnabled = !loading
        googleButton.isEnabled = !loading
        appleButton.isEnabled = !loading
        closeButton.isEnabled = !loading
        backToLoginButton.isEnabled = !loading

        if loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    /// Aqui eu centralizo a mensagem de erro para a tela inteira seguir o mesmo comportamento.
    private func setError(_ message: String?) {
        if let message, !message.isEmpty {
            errorLabel.text = message
            errorLabel.isHidden = false
            errorLabel.accessibilityValue = message
        } else {
            errorLabel.text = nil
            errorLabel.isHidden = true
            errorLabel.accessibilityValue = nil
        }
    }

    /// Aqui eu navego para o proximo campo por tag e finalizo no ultimo.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let nextTag = textField.tag + 1
        if let nextField = view.viewWithTag(nextTag) as? UITextField {
            nextField.becomeFirstResponder()
            return true
        }
        textField.resignFirstResponder()
        return true
    }

    /// Aqui eu inicio o cadastro social com Apple usando o mesmo backend de autenticacao do app.
    @objc private func appleTapped() {
        view.endEditing(true)

        if authService.isLocalMode {
            let localFullName = nomeField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task {
                await performAppleRegister(
                    identityToken: "local-token",
                    userIdentifier: UUID().uuidString,
                    email: emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                    fullName: localFullName.isEmpty ? "Conta Apple Local" : localFullName
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

    /// Aqui eu entrego a janela atual para a folha nativa de autenticacao Apple.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }

    /// Aqui eu traduzco o retorno da Apple para o mesmo fluxo social ja usado no backend.
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        guard
            let tokenData = credential.identityToken,
            let tokenString = String(data: tokenData, encoding: .utf8)
        else {
            setError("Não foi possível ler o token de autenticação da Apple.")
            return
        }

        let userIdentifier = credential.user
        let email = credential.email
        let fullName = credential.fullName?.formatted()

        Task {
            await performAppleRegister(
                identityToken: tokenString,
                userIdentifier: userIdentifier,
                email: email,
                fullName: fullName
            )
        }
    }

    /// Aqui eu trato falhas da Apple na propria tela de cadastro social.
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        setError(error.localizedDescription)
    }
}

private extension RegisterViewController {
    /// Aqui eu crio o estilo base de todos os campos para a tela ficar consistente.
    static func makeField(placeholder: String, keyboardType: UIKeyboardType, secure: Bool) -> UITextField {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.textColor = UIColor(hex: "#DCE6F3")
        field.tintColor = UIColor(hex: "#DCE6F3")
        field.applyScaledFont(size: 16, weight: .regular, textStyle: .body)
        field.placeholder = placeholder
        field.setPlaceholderColor(UIColor(hex: "#5E6B7B"))
        field.keyboardType = keyboardType
        field.isSecureTextEntry = secure
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return field
    }

    /// Aqui eu limpo qualquer caractere que nao seja numero antes de validar ou aplicar mascara.
    /// Aqui eu formato telefone de 10 digitos para numeros fixos ou celulares antigos.
    func formatAsPhone10(_ value: String) -> String {
        let limited = String(value.prefix(10))
        var result = ""

        for (index, character) in limited.enumerated() {
            if index == 0 { result.append("(") }
            if index == 2 { result.append(") ") }
            if index == 6 { result.append("-") }
            result.append(character)
        }
        return result
    }

    /// Aqui eu formato telefone de 11 digitos para o padrao atual de celular.
    func formatAsPhone11(_ value: String) -> String {
        let limited = String(value.prefix(11))
        var result = ""

        for (index, character) in limited.enumerated() {
            if index == 0 { result.append("(") }
            if index == 2 { result.append(") ") }
            if index == 7 { result.append("-") }
            result.append(character)
        }
        return result
    }

    /// Aqui eu valido apenas o tamanho minimo esperado porque a regra completa ainda nao foi integrada.
    func isValidCPFOrCNPJ(_ value: String) -> Bool {
        value.count == 11 || value.count == 14
    }

    /// Aqui eu aplico a politica minima de senha da fase atual do app.
    func isValidPasswordPolicy(_ password: String) -> Bool {
        let minLength = password.count >= 8
        let hasUpperCase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowerCase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecial = password.rangeOfCharacter(from: CharacterSet(charactersIn: "@#$%^&*()_+-=[]{};':\"\\|,.<>/?")) != nil
        return minLength && hasUpperCase && hasLowerCase && hasNumber && hasSpecial
    }

}
