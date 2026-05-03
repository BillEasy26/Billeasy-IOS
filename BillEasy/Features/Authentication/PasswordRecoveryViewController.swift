//
//  PasswordRecoveryViewController.swift
//  BillEasy
//

import UIKit

/// Aqui eu mantenho a solicitação de recuperação totalmente no mobile, mas deixo a validação do token e a troca final de senha no web.
final class PasswordRecoveryViewController: UIViewController, UITextFieldDelegate {
    private enum State {
        case request
        case sent(email: String)
    }

    private let authService: AuthService
    private let neuralBackgroundView = AnimatedNeuralBackgroundView(palette: .authDark)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emailFieldContainer = UIView()
    private let emailIconView = UIImageView()
    private let emailTextField = UITextField()
    private let securityCard = UIView()
    private let securityLabel = UILabel()
    private let primaryButton = RecoveryPrimaryButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let successIconContainer = UIView()
    private let successIconView = UIImageView()
    private let successTitleLabel = UILabel()
    private let successMessageLabel = UILabel()
    private let inboxCard = UIView()
    private let inboxTitleLabel = UILabel()
    private let inboxSubtitleLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var state: State = .request {
        didSet {
            applyState()
        }
    }

    private var isSubmitting = false {
        didSet {
            updatePrimaryButtonState()
        }
    }

    var prefilledEmail: String?

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
        applyPrefilledEmail()
        applyState()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        neuralBackgroundView.refreshLayout()
    }

    /// Aqui eu monto a base visual das duas telas usando a mesma linguagem do login.
    private func setupView() {
        view.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive

        contentView.translatesAutoresizingMaskIntoConstraints = false

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#8895A8")
        closeButton.accessibilityIdentifier = "passwordRecovery.closeButton"

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Recuperar Senha"
        titleLabel.textColor = .white
        titleLabel.applyScaledFont(size: 34, weight: .bold, textStyle: .largeTitle)
        titleLabel.numberOfLines = 2
        titleLabel.accessibilityIdentifier = "passwordRecovery.titleLabel"

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textColor = UIColor(hex: "#7F8DA3")
        subtitleLabel.applyScaledFont(size: 16, weight: .regular, textStyle: .body)
        subtitleLabel.numberOfLines = 0

        emailFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        emailFieldContainer.backgroundColor = UIColor(hex: "#0E192C")
        emailFieldContainer.layer.cornerRadius = 12
        emailFieldContainer.layer.cornerCurve = .continuous
        emailFieldContainer.layer.borderWidth = 1
        emailFieldContainer.layer.borderColor = UIColor(hex: "#223450").cgColor

        emailIconView.translatesAutoresizingMaskIntoConstraints = false
        emailIconView.image = UIImage(systemName: "envelope.fill")
        emailIconView.tintColor = UIColor(hex: "#B6C4D8")
        emailIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        emailTextField.translatesAutoresizingMaskIntoConstraints = false
        emailTextField.attributedPlaceholder = NSAttributedString(
            string: "E-mail",
            attributes: [
                .foregroundColor: UIColor(hex: "#8C99AC")
            ]
        )
        emailTextField.textColor = .white
        emailTextField.keyboardType = .emailAddress
        emailTextField.autocapitalizationType = .none
        emailTextField.autocorrectionType = .no
        emailTextField.textContentType = .username
        emailTextField.returnKeyType = .send
        emailTextField.delegate = self
        emailTextField.applyScaledFont(size: 18, weight: .medium, textStyle: .body)
        emailTextField.accessibilityIdentifier = "passwordRecovery.emailField"

        securityCard.translatesAutoresizingMaskIntoConstraints = false
        securityCard.backgroundColor = UIColor(hex: "#182541")
        securityCard.layer.cornerRadius = 14
        securityCard.layer.cornerCurve = .continuous
        securityCard.layer.borderWidth = 1.5
        securityCard.layer.borderColor = UIColor(hex: "#2BA4F7", alpha: 0.8).cgColor

        securityLabel.translatesAutoresizingMaskIntoConstraints = false
        securityLabel.text = "Por motivos de segurança, sempre informaremos que enviamos o email, mesmo que o endereço não esteja cadastrado."
        securityLabel.textColor = UIColor(hex: "#B4C1D4")
        securityLabel.numberOfLines = 0
        securityLabel.textAlignment = .center
        securityLabel.applyScaledFont(size: 15, weight: .regular, textStyle: .body)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.setTitleColor(UIColor(hex: "#1E9CFF"), for: .normal)
        secondaryButton.applyScaledTitleFont(size: 18, weight: .medium, textStyle: .body)
        secondaryButton.accessibilityIdentifier = "passwordRecovery.secondaryButton"

        successIconContainer.translatesAutoresizingMaskIntoConstraints = false
        successIconContainer.backgroundColor = UIColor(hex: "#162340")
        successIconContainer.layer.cornerRadius = 82
        successIconContainer.layer.cornerCurve = .continuous
        successIconContainer.layer.borderWidth = 3
        successIconContainer.layer.borderColor = UIColor(hex: "#47B8FF").cgColor

        successIconView.translatesAutoresizingMaskIntoConstraints = false
        successIconView.image = UIImage(systemName: "envelope")
        successIconView.tintColor = UIColor(hex: "#47B8FF")
        successIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 54, weight: .medium)

        successTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        successTitleLabel.text = "Email Enviado!"
        successTitleLabel.textColor = .white
        successTitleLabel.textAlignment = .center
        successTitleLabel.applyScaledFont(size: 28, weight: .bold, textStyle: .title1)
        successTitleLabel.accessibilityIdentifier = "passwordRecovery.successTitleLabel"

        successMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        successMessageLabel.textColor = UIColor(hex: "#C2CBD8")
        successMessageLabel.numberOfLines = 0
        successMessageLabel.textAlignment = .center
        successMessageLabel.applyScaledFont(size: 16, weight: .regular, textStyle: .body)

        inboxCard.translatesAutoresizingMaskIntoConstraints = false
        inboxCard.backgroundColor = UIColor(hex: "#182233")
        inboxCard.layer.cornerRadius = 24
        inboxCard.layer.cornerCurve = .continuous

        inboxTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        inboxTitleLabel.text = "Verifique sua caixa de entrada"
        inboxTitleLabel.textColor = .white
        inboxTitleLabel.numberOfLines = 0
        inboxTitleLabel.applyScaledFont(size: 18, weight: .semibold, textStyle: .headline)

        inboxSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        inboxSubtitleLabel.text = "O email pode levar alguns minutos para chegar. Não esqueça de verificar a pasta de spam!"
        inboxSubtitleLabel.textColor = UIColor(hex: "#8F9CB0")
        inboxSubtitleLabel.numberOfLines = 0
        inboxSubtitleLabel.applyScaledFont(size: 15, weight: .regular, textStyle: .body)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .white
    }

    /// Aqui eu concentro todos os elementos em um layout simples para alternar entre os dois estados sem recriar view.
    private func setupHierarchy() {
        neuralBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(neuralBackgroundView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(closeButton)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(emailFieldContainer)
        emailFieldContainer.addSubview(emailIconView)
        emailFieldContainer.addSubview(emailTextField)
        contentView.addSubview(securityCard)
        securityCard.addSubview(securityLabel)
        contentView.addSubview(successIconContainer)
        successIconContainer.addSubview(successIconView)
        contentView.addSubview(successTitleLabel)
        contentView.addSubview(successMessageLabel)
        contentView.addSubview(inboxCard)
        inboxCard.addSubview(inboxTitleLabel)
        inboxCard.addSubview(inboxSubtitleLabel)
        contentView.addSubview(primaryButton)
        contentView.addSubview(secondaryButton)
        primaryButton.addSubview(activityIndicator)
    }

    /// Aqui eu prendo o layout nas mesmas proporções do print, preservando respiro em telas menores.
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            neuralBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            neuralBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            neuralBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            neuralBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 42),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            emailFieldContainer.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 36),
            emailFieldContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            emailFieldContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            emailFieldContainer.heightAnchor.constraint(equalToConstant: 80),

            emailIconView.leadingAnchor.constraint(equalTo: emailFieldContainer.leadingAnchor, constant: 18),
            emailIconView.centerYAnchor.constraint(equalTo: emailFieldContainer.centerYAnchor),
            emailIconView.widthAnchor.constraint(equalToConstant: 26),
            emailIconView.heightAnchor.constraint(equalToConstant: 26),

            emailTextField.leadingAnchor.constraint(equalTo: emailIconView.trailingAnchor, constant: 16),
            emailTextField.trailingAnchor.constraint(equalTo: emailFieldContainer.trailingAnchor, constant: -18),
            emailTextField.centerYAnchor.constraint(equalTo: emailFieldContainer.centerYAnchor),

            securityCard.topAnchor.constraint(equalTo: emailFieldContainer.bottomAnchor, constant: 24),
            securityCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            securityCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            securityLabel.topAnchor.constraint(equalTo: securityCard.topAnchor, constant: 20),
            securityLabel.leadingAnchor.constraint(equalTo: securityCard.leadingAnchor, constant: 20),
            securityLabel.trailingAnchor.constraint(equalTo: securityCard.trailingAnchor, constant: -20),
            securityLabel.bottomAnchor.constraint(equalTo: securityCard.bottomAnchor, constant: -20),

            successIconContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 46),
            successIconContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            successIconContainer.widthAnchor.constraint(equalToConstant: 164),
            successIconContainer.heightAnchor.constraint(equalToConstant: 164),

            successIconView.centerXAnchor.constraint(equalTo: successIconContainer.centerXAnchor),
            successIconView.centerYAnchor.constraint(equalTo: successIconContainer.centerYAnchor),

            successTitleLabel.topAnchor.constraint(equalTo: successIconContainer.bottomAnchor, constant: 38),
            successTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            successTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            successMessageLabel.topAnchor.constraint(equalTo: successTitleLabel.bottomAnchor, constant: 20),
            successMessageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 48),
            successMessageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -48),

            inboxCard.topAnchor.constraint(equalTo: successMessageLabel.bottomAnchor, constant: 34),
            inboxCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            inboxCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            inboxTitleLabel.topAnchor.constraint(equalTo: inboxCard.topAnchor, constant: 24),
            inboxTitleLabel.leadingAnchor.constraint(equalTo: inboxCard.leadingAnchor, constant: 24),
            inboxTitleLabel.trailingAnchor.constraint(equalTo: inboxCard.trailingAnchor, constant: -24),

            inboxSubtitleLabel.topAnchor.constraint(equalTo: inboxTitleLabel.bottomAnchor, constant: 10),
            inboxSubtitleLabel.leadingAnchor.constraint(equalTo: inboxCard.leadingAnchor, constant: 24),
            inboxSubtitleLabel.trailingAnchor.constraint(equalTo: inboxCard.trailingAnchor, constant: -24),
            inboxSubtitleLabel.bottomAnchor.constraint(equalTo: inboxCard.bottomAnchor, constant: -24),

            primaryButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            primaryButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            primaryButton.heightAnchor.constraint(equalToConstant: 64),

            secondaryButton.topAnchor.constraint(equalTo: primaryButton.bottomAnchor, constant: 26),
            secondaryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            secondaryButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -40),

            activityIndicator.centerXAnchor.constraint(equalTo: primaryButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor)
        ])

        primaryButtonBottomConstraintRequest = primaryButton.topAnchor.constraint(equalTo: securityCard.bottomAnchor, constant: 24)
        primaryButtonBottomConstraintSuccess = primaryButton.topAnchor.constraint(equalTo: inboxCard.bottomAnchor, constant: 38)
        primaryButtonBottomConstraintRequest?.isActive = true
    }

    private var primaryButtonBottomConstraintRequest: NSLayoutConstraint?
    private var primaryButtonBottomConstraintSuccess: NSLayoutConstraint?

    /// Aqui eu concentro as ações para não espalhar regra de navegação em vários pontos da tela.
    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        primaryButton.addTarget(self, action: #selector(primaryActionTapped), for: .touchUpInside)
        secondaryButton.addTarget(self, action: #selector(secondaryActionTapped), for: .touchUpInside)
        emailTextField.addTarget(self, action: #selector(emailChanged), for: .editingChanged)
    }

    /// Aqui eu reaproveito o e-mail já digitado no login sem obrigar o usuário a começar de novo.
    private func applyPrefilledEmail() {
        emailTextField.text = prefilledEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        updatePrimaryButtonState()
    }

    /// Aqui eu alterno o conteúdo entre pedido de envio e confirmação, mantendo o controller simples.
    private func applyState() {
        let isRequestState: Bool

        switch state {
        case .request:
            isRequestState = true
            subtitleLabel.text = "Digite seu email e enviaremos um link para redefinir sua senha."
            primaryButton.setTitle("Enviar link", for: .normal)
            primaryButton.accessibilityIdentifier = "passwordRecovery.sendButton"
            secondaryButton.setTitle("Voltar para login", for: .normal)
            updateSuccessMessage(email: nil)
        case let .sent(email):
            isRequestState = false
            subtitleLabel.text = nil
            primaryButton.setTitle("Voltar para o início", for: .normal)
            primaryButton.accessibilityIdentifier = "passwordRecovery.homeButton"
            secondaryButton.setTitle(nil, for: .normal)
            updateSuccessMessage(email: email)
        }

        subtitleLabel.isHidden = !isRequestState
        emailFieldContainer.isHidden = !isRequestState
        securityCard.isHidden = !isRequestState

        successIconContainer.isHidden = isRequestState
        successTitleLabel.isHidden = isRequestState
        successMessageLabel.isHidden = isRequestState
        inboxCard.isHidden = isRequestState
        secondaryButton.isHidden = !isRequestState

        primaryButtonBottomConstraintRequest?.isActive = isRequestState
        primaryButtonBottomConstraintSuccess?.isActive = !isRequestState
        updatePrimaryButtonState()
        view.layoutIfNeeded()
    }

    /// Aqui eu reforço o e-mail usado no texto de sucesso, porque é a informação que o usuário precisa conferir.
    private func updateSuccessMessage(email: String?) {
        guard let email else {
            successMessageLabel.attributedText = nil
            return
        }

        let fullText = "Se o email \(email)\nestiver cadastrado, você receberá um link\npara redefinir sua senha."
        let attributed = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .foregroundColor: UIColor(hex: "#C2CBD8"),
                .font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
            ]
        )

        let emailRange = (fullText as NSString).range(of: email)
        if emailRange.location != NSNotFound {
            attributed.addAttributes(
                [
                    .foregroundColor: UIColor.white,
                    .font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .bold),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: emailRange
            )
        }

        successMessageLabel.attributedText = attributed
    }

    /// Aqui eu mantenho o CTA principal habilitado só quando a ação pode ser executada.
    private func updatePrimaryButtonState() {
        let isEnabled: Bool

        switch state {
        case .request:
            isEnabled = isSubmitting == false && isValidEmail(emailTextField.text)
        case .sent:
            isEnabled = isSubmitting == false
        }

        primaryButton.isEnabled = isEnabled
        emailTextField.isEnabled = !isSubmitting

        if isSubmitting {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    @objc
    private func closeTapped() {
        closeOrReturnToLogin()
    }

    @objc
    private func secondaryActionTapped() {
        closeOrReturnToLogin()
    }

    /// Aqui eu diferencio o comportamento do CTA entre solicitar o link e voltar para a home pública.
    @objc
    private func primaryActionTapped() {
        switch state {
        case .request:
            requestRecoveryLink()
        case .sent:
            returnToHome()
        }
    }

    @objc
    private func emailChanged() {
        updatePrimaryButtonState()
    }

    /// Aqui eu envio o pedido ao backend e trato o modo local com a mesma política de não revelar cadastro.
    private func requestRecoveryLink() {
        let email = (emailTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else { return }

        Task { @MainActor in
            isSubmitting = true
            defer { isSubmitting = false }

            do {
                try await authService.requestPasswordReset(email: email)
                state = .sent(email: email)
            } catch AuthServiceError.accountNotFound {
                state = .sent(email: email)
            } catch {
                showAlert(title: "Não foi possível enviar o link", message: error.localizedDescription)
            }
        }
    }

    /// Aqui eu mantenho a volta para a tela anterior simples, seja via push ou apresentação modal.
    private func closeOrReturnToLogin() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
            return
        }

        dismiss(animated: true)
    }

    /// Aqui eu devolvo o usuário para a home pública depois que o e-mail já foi solicitado.
    private func returnToHome() {
        if let navigationController {
            navigationController.popToRootViewController(animated: true)
            return
        }

        presentingViewController?.dismiss(animated: true)
    }

    /// Aqui eu valido só o mínimo necessário para habilitar o envio do link.
    private func isValidEmail(_ rawValue: String?) -> Bool {
        guard let rawValue else { return false }
        let email = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.contains("@") && email.contains(".")
    }

    /// Aqui eu reaproveito o teclado para disparar a solicitação quando o formulário já estiver válido.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if primaryButton.isEnabled {
            primaryActionTapped()
        }
        return true
    }

    /// Aqui eu mantenho o feedback remoto simples e previsível como nas outras telas de autenticação.
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// Aqui eu concentro o estilo do CTA principal da recuperação para manter os estados claro/escuro consistentes.
private final class RecoveryPrimaryButton: UIButton {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    private func setup() {
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setTitleColor(.white, for: .normal)
        applyScaledTitleFont(size: 18, weight: .semibold, textStyle: .headline)

        gradientLayer.colors = [
            UIColor(hex: "#58C8FF").cgColor,
            UIColor(hex: "#1D7CB8").cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)

        backgroundColor = UIColor(hex: "#2A3243")
        updateAppearance()
    }

    override var isEnabled: Bool {
        didSet {
            updateAppearance()
        }
    }

    private func updateAppearance() {
        gradientLayer.isHidden = !isEnabled
        backgroundColor = isEnabled ? .clear : UIColor(hex: "#2A3243")
        setTitleColor(isEnabled ? .white : UIColor(hex: "#7E8797"), for: .normal)
    }
}
