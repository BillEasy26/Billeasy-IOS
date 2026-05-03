//
//  RoutePlaceholderViewController.swift
//  BillEasy
//

import UIKit

/// Aqui eu mantenho placeholders leves para rotas web que ainda não ganharam uma tela nativa final.
final class RoutePlaceholderViewController: UIViewController {
    private let route: WebAppRoute
    private let displayTitle: String

    init(route: WebAppRoute, displayTitle: String) {
        self.route = route
        self.displayTitle = displayTitle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = displayTitle
        view.backgroundColor = UIColor.systemBackground
        setupContent()
    }

    /// Aqui eu explico ao time qual rota web corresponde a esta tela nativa provisória.
    private func setupContent() {
        let card = BrandCardFactory.makeEmptyStateCard(
            title: displayTitle,
            subtitle: "Fluxo local ativo. Esta rota continua ligada ao app nativo e corresponde à rota web \(route.rawValue).",
            iconSystemName: "square.stack.3d.up"
        )
        card.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
}

/// Aqui eu concentro a home pública local com fundo de rede, marca oficial e atalhos para login e início do fluxo na web.
final class PublicHomeViewController: UIViewController {
    var onLoginRequested: (() -> Void)?
    var onRegisterRequested: (() -> Void)?
    var onGoogleLoginRequested: (() -> Void)?
    var onAppleLoginRequested: (() -> Void)?

    private let neuralBackgroundView = AnimatedNeuralBackgroundView(palette: .landingLight)
    private let contentStack = UIStackView()
    private let brandImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let registerButton = UIButton(type: .custom)
    private let loginButton = UIButton(type: .custom)
    private let googleButton = UIButton(type: .custom)
    private let appleButton = UIButton(type: .custom)
    private let footerLabel = UILabel()
    private let registerButtonTitle = "COMECE GRÁTIS"
    private let loginButtonTitle = "ENTRAR"
    private let googleButtonTitle = "Entrar com Google"
    private let appleButtonTitle = "Entrar com Apple"

    private var isDarkModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "billeasy.theme.dark_mode_enabled")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        neuralBackgroundView.refreshLayout()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        isDarkModeEnabled ? .lightContent : .darkContent
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        neuralBackgroundView.refreshLayout()
    }

    /// Aqui eu preparo a base da landing pública usando a marca do frontend e a mesma preferência de tema do app.
    private func setupView() {
        view.backgroundColor = .clear

        neuralBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 12

        brandImageView.translatesAutoresizingMaskIntoConstraints = false
        brandImageView.image = UIImage(named: "BrandLogo")
        brandImageView.contentMode = .scaleAspectFit
        brandImageView.setContentCompressionResistancePriority(.required, for: .vertical)
        brandImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        brandImageView.isAccessibilityElement = true
        brandImageView.accessibilityLabel = "BillEasy ponto ia"
        brandImageView.accessibilityValue = "Gestão inteligente, cobrança eficiente e recebimento seguro."

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        subtitleLabel.text = "Centralize contratos, automatize pagamentos e organize seus recebíveis com facilidade."

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.text = "© 2026 BillEasy.ia"
        footerLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption2)

        configurePrimaryButton(
            registerButton,
            title: "CRIAR CONTA GRÁTIS",
            accessibilityIdentifier: "home.registerButton",
            action: #selector(registerTapped)
        )
        configureOutlineButton(
            loginButton,
            title: "ENTRAR",
            accessibilityIdentifier: "home.loginButton",
            action: #selector(loginTapped)
        )
        configureGoogleButton()
        configureAppleButton()
        applyTheme()
    }

    /// Aqui eu monto o conteúdo central seguindo o grid do print de referência no mobile.
    private func setupLayout() {
        view.addSubview(neuralBackgroundView)
        view.addSubview(contentStack)
        view.addSubview(footerLabel)

        contentStack.addArrangedSubview(brandImageView)
        contentStack.setCustomSpacing(26, after: brandImageView)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.setCustomSpacing(16, after: titleLabel)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.setCustomSpacing(26, after: subtitleLabel)
        contentStack.addArrangedSubview(registerButton)
        contentStack.setCustomSpacing(12, after: registerButton)
        contentStack.addArrangedSubview(loginButton)
        contentStack.setCustomSpacing(14, after: loginButton)
        contentStack.addArrangedSubview(appleButton)
        contentStack.setCustomSpacing(12, after: appleButton)
        contentStack.addArrangedSubview(googleButton)

        NSLayoutConstraint.activate([
            neuralBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            neuralBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            neuralBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            neuralBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            contentStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -34),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: footerLabel.topAnchor, constant: -28),

            brandImageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            brandImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 72),

            registerButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            loginButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            appleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            googleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            footerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    /// Aqui eu mantenho o botão principal fiel ao layout do print e consistente no tema escuro.
    private func configurePrimaryButton(
        _ button: UIButton,
        title: String,
        accessibilityIdentifier: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.automaticallyUpdatesConfiguration = false
        button.configuration = nil
        button.setTitle(title, for: .normal)
        button.setTitle(title, for: .highlighted)
        button.setTitle(title, for: .selected)
        button.applyScaledTitleFont(size: 17, weight: .bold, textStyle: .headline)
        button.contentHorizontalAlignment = .center
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityHint = "Abre o cadastro no site."
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// Aqui eu monto o CTA secundário com borda leve para refletir o botão de entrar do layout original.
    private func configureOutlineButton(
        _ button: UIButton,
        title: String,
        accessibilityIdentifier: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.automaticallyUpdatesConfiguration = false
        button.configuration = nil
        button.setTitle(title, for: .normal)
        button.setTitle(title, for: .highlighted)
        button.setTitle(title, for: .selected)
        button.applyScaledTitleFont(size: 17, weight: .bold, textStyle: .headline)
        button.contentHorizontalAlignment = .center
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityHint = "Abre a tela de login."
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// Aqui eu preservo o Apple Sign In como atalho direto na home pública.
    private func configureAppleButton() {
        appleButton.translatesAutoresizingMaskIntoConstraints = false
        appleButton.automaticallyUpdatesConfiguration = false
        appleButton.configuration = nil
        setSocialButtonTitle(appleButton, title: appleButtonTitle, leadingSpaces: 2)
        appleButton.setImage(
            UIImage(systemName: "applelogo", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)),
            for: .normal
        )
        appleButton.setImage(
            UIImage(systemName: "applelogo", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)),
            for: .highlighted
        )
        appleButton.applyScaledTitleFont(size: 15, weight: .semibold, textStyle: .body)
        appleButton.semanticContentAttribute = .forceLeftToRight
        appleButton.contentHorizontalAlignment = .center
        appleButton.imageView?.contentMode = .scaleAspectFit
        appleButton.layer.cornerRadius = 16
        appleButton.layer.cornerCurve = .continuous
        appleButton.layer.borderWidth = 1
        appleButton.accessibilityIdentifier = "home.appleButton"
        appleButton.accessibilityHint = "Inicia o login com a sua conta Apple."
        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
    }

    /// Aqui eu reaproveito o CTA do Google na home pública com o mesmo visual do cadastro e com toque direto no OAuth.
    private func configureGoogleButton() {
        googleButton.translatesAutoresizingMaskIntoConstraints = false
        googleButton.automaticallyUpdatesConfiguration = false
        googleButton.configuration = nil
        let googleLogo = UIImage(named: "GoogleLogo")?.withRenderingMode(.alwaysOriginal)
        setSocialButtonTitle(googleButton, title: googleButtonTitle, leadingSpaces: 2)
        googleButton.setImage(googleLogo, for: .normal)
        googleButton.setImage(googleLogo, for: .highlighted)
        googleButton.setImage(googleLogo, for: .selected)
        googleButton.applyScaledTitleFont(size: 15, weight: .semibold, textStyle: .body)
        googleButton.semanticContentAttribute = .forceLeftToRight
        googleButton.contentHorizontalAlignment = .center
        googleButton.imageView?.contentMode = .scaleAspectFit
        googleButton.layer.cornerRadius = 16
        googleButton.layer.cornerCurve = .continuous
        googleButton.layer.borderWidth = 1
        googleButton.accessibilityIdentifier = "home.googleButton"
        googleButton.accessibilityHint = "Inicia o login com a sua conta Google."
        googleButton.addTarget(self, action: #selector(googleTapped), for: .touchUpInside)
    }

    /// Aqui eu monto o título com o mesmo destaque visual do print e preservo a legibilidade no escuro.
    private func makeTitleText(baseColor: UIColor, accentColor: UIColor) -> NSAttributedString {
        let full = NSMutableAttributedString(
            string: "Gestão de Contratos e\nRecebíveis",
            attributes: [
                .font: UIFont.billeasyScaledFont(size: 28, weight: .bold, textStyle: .largeTitle),
                .foregroundColor: baseColor
            ]
        )

        full.addAttribute(
            .foregroundColor,
            value: accentColor,
            range: (full.string as NSString).range(of: "Contratos")
        )
        full.addAttribute(
            .foregroundColor,
            value: accentColor,
            range: (full.string as NSString).range(of: "Recebíveis")
        )

        return full
    }

    private func setSocialButtonTitle(_ button: UIButton, title: String, leadingSpaces: Int) {
        let displayTitle = "\(String(repeating: " ", count: leadingSpaces))\(title)"
        button.setTitle(displayTitle, for: .normal)
        button.setTitle(displayTitle, for: .highlighted)
        button.setTitle(displayTitle, for: .selected)
        button.accessibilityLabel = title
    }

    /// Aqui eu reaplico todas as cores da landing considerando o tema salvo pelo usuário.
    private func applyTheme() {
        let backgroundColor = isDarkModeEnabled ? UIColor(fixedHex: "#081220") : UIColor(fixedHex: "#FFFFFF")
        let baseTitleColor = isDarkModeEnabled ? UIColor(fixedHex: "#F2F7FF") : UIColor(fixedHex: "#252E3A")
        let accentTitleColor = isDarkModeEnabled ? UIColor(fixedHex: "#62C4FF") : UIColor(fixedHex: "#147FB3")
        let subtitleColor = isDarkModeEnabled ? UIColor(fixedHex: "#B7CBE3") : UIColor(fixedHex: "#73849B")
        let footerColor = isDarkModeEnabled ? UIColor(fixedHex: "#8FA8C3", alpha: 0.72) : UIColor(fixedHex: "#A0AEC0")
        let outlineColor = isDarkModeEnabled ? UIColor(fixedHex: "#234A6A") : UIColor(fixedHex: "#D4DCE7")
        let actionForeground = isDarkModeEnabled ? UIColor(fixedHex: "#F2F7FF") : UIColor(fixedHex: "#252E3A")

        view.backgroundColor = backgroundColor
        neuralBackgroundView.applyPalette(isDarkModeEnabled ? .landingDark : .landingLight)

        titleLabel.attributedText = makeTitleText(baseColor: baseTitleColor, accentColor: accentTitleColor)
        subtitleLabel.textColor = subtitleColor
        footerLabel.textColor = footerColor

        registerButton.layer.borderWidth = 0
        registerButton.configurationUpdateHandler = nil
        registerButton.backgroundColor = UIColor(fixedHex: "#1579A8")
        registerButton.setTitle(registerButtonTitle, for: .normal)
        registerButton.setTitle(registerButtonTitle, for: .highlighted)
        registerButton.setTitle(registerButtonTitle, for: .selected)
        registerButton.setTitleColor(.white, for: .normal)
        registerButton.setTitleColor(.white, for: .highlighted)
        registerButton.setTitleColor(.white, for: .selected)
        registerButton.setTitleColor(UIColor.white.withAlphaComponent(0.72), for: .disabled)

        loginButton.layer.borderColor = outlineColor.cgColor
        loginButton.configurationUpdateHandler = nil
        loginButton.backgroundColor = .clear
        loginButton.setTitle(loginButtonTitle, for: .normal)
        loginButton.setTitle(loginButtonTitle, for: .highlighted)
        loginButton.setTitle(loginButtonTitle, for: .selected)
        loginButton.setTitleColor(actionForeground, for: .normal)
        loginButton.setTitleColor(actionForeground, for: .highlighted)
        loginButton.setTitleColor(actionForeground, for: .selected)
        loginButton.setTitleColor(actionForeground.withAlphaComponent(0.72), for: .disabled)

        appleButton.layer.borderColor = outlineColor.cgColor
        appleButton.configurationUpdateHandler = nil
        appleButton.backgroundColor = .clear
        setSocialButtonTitle(appleButton, title: appleButtonTitle, leadingSpaces: 2)
        appleButton.setTitleColor(actionForeground, for: .normal)
        appleButton.setTitleColor(actionForeground, for: .highlighted)
        appleButton.setTitleColor(actionForeground, for: .selected)
        appleButton.setTitleColor(actionForeground.withAlphaComponent(0.72), for: .disabled)
        appleButton.tintColor = actionForeground

        googleButton.layer.borderColor = outlineColor.cgColor
        googleButton.configurationUpdateHandler = nil
        googleButton.backgroundColor = .clear
        setSocialButtonTitle(googleButton, title: googleButtonTitle, leadingSpaces: 2)
        googleButton.setTitleColor(actionForeground, for: .normal)
        googleButton.setTitleColor(actionForeground, for: .highlighted)
        googleButton.setTitleColor(actionForeground, for: .selected)
        googleButton.setTitleColor(actionForeground.withAlphaComponent(0.72), for: .disabled)
        googleButton.tintColor = actionForeground

        brandImageView.alpha = isDarkModeEnabled ? 0.98 : 1
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Aqui eu encaminho o toque de login para o coordenador da aplicação.
    @objc private func loginTapped() {
        onLoginRequested?()
    }

    /// Aqui eu encaminho o toque de cadastro para o coordenador da aplicação.
    @objc private func registerTapped() {
        onRegisterRequested?()
    }

    /// Aqui eu mantenho o login Apple como atalho direto na home pública.
    @objc private func appleTapped() {
        onAppleLoginRequested?()
    }

    /// Aqui eu deixo o Google tão direto quanto o Apple na home pública, mas reaproveitando o mesmo fluxo seguro do login.
    @objc private func googleTapped() {
        onGoogleLoginRequested?()
    }
}
