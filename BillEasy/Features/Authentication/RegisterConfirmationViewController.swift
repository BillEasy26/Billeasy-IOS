//
//  RegisterConfirmationViewController.swift
//  BillEasy
//

import UIKit

/// Aqui eu mostro a confirmação de cadastro remoto e deixo claro que o próximo passo é validar o e-mail.
final class RegisterConfirmationViewController: UIViewController {
    private let authService: AuthService
    private let email: String

    private let neuralBackgroundView = AnimatedNeuralBackgroundView(palette: .authDark)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let headlineLabel = UILabel()
    private let messageLabel = UILabel()
    private let stepsCard = UIView()
    private let stepsTitleLabel = UILabel()
    private let stepsLabel = UILabel()
    private let resendButton = RegisterConfirmationPrimaryButton(frame: .zero)
    private let homeButton = UIButton(type: .system)
    private let resendIndicator = UIActivityIndicatorView(style: .medium)

    private var isResending = false {
        didSet {
            updateButtonsState()
        }
    }

    init(email: String, authService: AuthService = AuthService()) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
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
        applyContent()
        updateButtonsState()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        neuralBackgroundView.refreshLayout()
    }

    /// Aqui eu monto a base visual da tela no mesmo idioma visual do login e da recuperação de senha.
    private func setupView() {
        view.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        contentView.translatesAutoresizingMaskIntoConstraints = false

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#8895A8")
        closeButton.accessibilityIdentifier = "registerConfirmation.closeButton"

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Cadastro Realizado!"
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.applyScaledFont(size: 32, weight: .bold, textStyle: .largeTitle)
        titleLabel.accessibilityIdentifier = "registerConfirmation.titleLabel"

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = UIColor(hex: "#162340")
        iconContainer.layer.cornerRadius = 66
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.layer.borderWidth = 2
        iconContainer.layer.borderColor = UIColor(hex: "#47B8FF").cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "envelope")
        iconView.tintColor = UIColor(hex: "#47B8FF")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)

        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        headlineLabel.text = "Verifique seu Email"
        headlineLabel.textColor = .white
        headlineLabel.textAlignment = .center
        headlineLabel.applyScaledFont(size: 28, weight: .bold, textStyle: .title1)
        headlineLabel.accessibilityIdentifier = "registerConfirmation.headlineLabel"

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = UIColor(hex: "#C2CBD8")
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.applyScaledFont(size: 16, weight: .regular, textStyle: .body)

        stepsCard.translatesAutoresizingMaskIntoConstraints = false
        stepsCard.backgroundColor = UIColor(hex: "#182334")
        stepsCard.layer.cornerRadius = 26
        stepsCard.layer.cornerCurve = .continuous

        stepsTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        stepsTitleLabel.text = "Próximos Passos:"
        stepsTitleLabel.textColor = .white
        stepsTitleLabel.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)

        stepsLabel.translatesAutoresizingMaskIntoConstraints = false
        stepsLabel.numberOfLines = 0
        stepsLabel.textColor = UIColor(hex: "#AEBBCE")
        stepsLabel.applyScaledFont(size: 15, weight: .regular, textStyle: .body)

        resendButton.translatesAutoresizingMaskIntoConstraints = false
        resendButton.setContent(title: "Não Recebeu? Reenviar Email", iconSystemName: "envelope")
        resendButton.accessibilityIdentifier = "registerConfirmation.resendButton"

        homeButton.translatesAutoresizingMaskIntoConstraints = false
        homeButton.setTitle("Voltar para página inicial", for: .normal)
        homeButton.setTitleColor(UIColor(hex: "#B1BDCC"), for: .normal)
        homeButton.applyScaledTitleFont(size: 18, weight: .medium, textStyle: .body)
        homeButton.accessibilityIdentifier = "registerConfirmation.homeButton"

        resendIndicator.translatesAutoresizingMaskIntoConstraints = false
        resendIndicator.hidesWhenStopped = true
        resendIndicator.color = .white
    }

    /// Aqui eu organizo a hierarquia em um único fluxo vertical, sem reconstruir a tela a cada ação.
    private func setupHierarchy() {
        neuralBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(neuralBackgroundView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(closeButton)
        contentView.addSubview(titleLabel)
        contentView.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        contentView.addSubview(headlineLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(stepsCard)
        stepsCard.addSubview(stepsTitleLabel)
        stepsCard.addSubview(stepsLabel)
        contentView.addSubview(resendButton)
        resendButton.addSubview(resendIndicator)
        contentView.addSubview(homeButton)
    }

    /// Aqui eu prendo o layout para ficar fiel ao print, mas ainda adaptável a telas menores.
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

            closeButton.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -16),

            iconContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 30),
            iconContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 132),
            iconContainer.heightAnchor.constraint(equalToConstant: 132),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            headlineLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 32),
            headlineLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            headlineLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30),

            messageLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 14),
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            stepsCard.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 28),
            stepsCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stepsCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),

            stepsTitleLabel.topAnchor.constraint(equalTo: stepsCard.topAnchor, constant: 26),
            stepsTitleLabel.leadingAnchor.constraint(equalTo: stepsCard.leadingAnchor, constant: 24),
            stepsTitleLabel.trailingAnchor.constraint(equalTo: stepsCard.trailingAnchor, constant: -24),

            stepsLabel.topAnchor.constraint(equalTo: stepsTitleLabel.bottomAnchor, constant: 12),
            stepsLabel.leadingAnchor.constraint(equalTo: stepsCard.leadingAnchor, constant: 24),
            stepsLabel.trailingAnchor.constraint(equalTo: stepsCard.trailingAnchor, constant: -24),
            stepsLabel.bottomAnchor.constraint(equalTo: stepsCard.bottomAnchor, constant: -24),

            resendButton.topAnchor.constraint(equalTo: stepsCard.bottomAnchor, constant: 30),
            resendButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            resendButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            resendButton.heightAnchor.constraint(equalToConstant: 68),

            resendIndicator.centerYAnchor.constraint(equalTo: resendButton.centerYAnchor),
            resendIndicator.trailingAnchor.constraint(equalTo: resendButton.trailingAnchor, constant: -22),

            homeButton.topAnchor.constraint(equalTo: resendButton.bottomAnchor, constant: 30),
            homeButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            homeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -34)
        ])
    }

    /// Aqui eu conecto as ações em um único ponto para não espalhar navegação pela tela.
    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        resendButton.addTarget(self, action: #selector(resendTapped), for: .touchUpInside)
        homeButton.addTarget(self, action: #selector(backHomeTapped), for: .touchUpInside)
    }

    /// Aqui eu monto os textos com destaque no e-mail da conta recém-criada.
    private func applyContent() {
        let fullText = "Enviamos um link de verificação para \(email). Clique no link para ativar sua conta."
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 5
        let attributed = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .foregroundColor: UIColor(hex: "#C2CBD8"),
                .font: UIFont.billeasyScaledFont(size: 16, weight: .regular, textStyle: .body),
                .paragraphStyle: paragraphStyle
            ]
        )

        let emailRange = (fullText as NSString).range(of: email)
        if emailRange.location != NSNotFound {
            attributed.addAttributes(
                [
                    .foregroundColor: UIColor.white,
                    .font: UIFont.billeasyScaledFont(size: 16, weight: .bold, textStyle: .body)
                ],
                range: emailRange
            )
        }

        messageLabel.attributedText = attributed
        stepsLabel.attributedText = makeStepsText()
    }

    /// Aqui eu deixo os passos com numeração destacada para a leitura bater com o layout de referência.
    private func makeStepsText() -> NSAttributedString {
        let fullText = "1. Verifique sua caixa de entrada\n\n2. Clique no link de verificação\n\n3. Faça login e comece a usar!\n\nNão se esqueça de verificar a pasta de spam!"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        let attributed = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .foregroundColor: UIColor(hex: "#AEBBCE"),
                .font: UIFont.billeasyScaledFont(size: 15, weight: .regular, textStyle: .body),
                .paragraphStyle: paragraphStyle
            ]
        )

        ["1.", "2.", "3."].forEach { marker in
            let range = (fullText as NSString).range(of: marker)
            if range.location != NSNotFound {
                attributed.addAttributes(
                    [
                        .foregroundColor: UIColor(hex: "#47B8FF"),
                        .font: UIFont.billeasyScaledFont(size: 15, weight: .bold, textStyle: .body)
                    ],
                    range: range
                )
            }
        }

        return attributed
    }

    /// Aqui eu sincronizo loading e estado clicável dos botões para evitar múltiplos reenvios em sequência.
    private func updateButtonsState() {
        resendButton.isEnabled = !isResending
        homeButton.isEnabled = !isResending
        closeButton.isEnabled = !isResending

        if isResending {
            resendIndicator.startAnimating()
        } else {
            resendIndicator.stopAnimating()
        }
    }

    @objc
    private func resendTapped() {
        guard !email.isEmpty else { return }

        Task { @MainActor in
            isResending = true
            defer { isResending = false }

            do {
                let message = try await authService.resendVerification(email: email)
                showSimpleToast(message, style: .success)
            } catch {
                showSimpleToast(error.localizedDescription, style: .error)
            }
        }
    }

    @objc
    private func closeTapped() {
        returnToHome()
    }

    @objc
    private func backHomeTapped() {
        returnToHome()
    }

    /// Aqui eu retorno sempre para a home pública, que é o destino natural depois do cadastro pendente de verificação.
    private func returnToHome() {
        if let navigationController {
            navigationController.popToRootViewController(animated: true)
            return
        }

        presentingViewController?.dismiss(animated: true)
    }
}

/// Aqui eu isolo o CTA principal para manter o gradiente, o ícone e o texto alinhados sem depender de configuração frágil do UIButton.
private final class RegisterConfirmationPrimaryButton: UIButton {
    private let gradientLayer = CAGradientLayer()
    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabelView = UILabel()

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
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
    }

    func setContent(title: String, iconSystemName: String) {
        titleLabelView.text = title
        iconView.image = UIImage(systemName: iconSystemName)
    }

    private func setup() {
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = false
        layer.shadowColor = UIColor(hex: "#3EB6FF", alpha: 0.55).cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 8)

        gradientLayer.colors = [
            UIColor(hex: "#58C8FF").cgColor,
            UIColor(hex: "#1D7CB8").cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.cornerRadius = 22
        layer.insertSublayer(gradientLayer, at: 0)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.isUserInteractionEnabled = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .white
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)

        titleLabelView.translatesAutoresizingMaskIntoConstraints = false
        titleLabelView.textColor = .white
        titleLabelView.applyScaledFont(size: 17, weight: .semibold, textStyle: .headline)

        addSubview(stack)
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabelView)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

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
        titleLabelView.textColor = isEnabled ? .white : UIColor(hex: "#7E8797")
        iconView.tintColor = isEnabled ? .white : UIColor(hex: "#7E8797")
        alpha = isEnabled ? 1 : 0.72
    }
}
