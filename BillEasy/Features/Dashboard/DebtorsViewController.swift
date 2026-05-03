//
//  DebtorsViewController.swift
//  BillEasy
//

import UIKit

final class DebtorsViewController: UIViewController, UITextFieldDelegate {
    private enum Layout {
        static let stackSpacing: CGFloat = 16
        static let horizontalMargin: CGFloat = 16
        static let topMargin: CGFloat = 16
        static let bottomMargin: CGFloat = 28
        static let sectionTitleSize: CGFloat = 30
        static let cardCornerRadius: CGFloat = 16
        static let contentInset: CGFloat = 16
        static let fieldHeight: CGFloat = 48
        static let actionHeight: CGFloat = 44
    }

    private struct InfoField {
        let title: String
        let value: String
    }

    private let session: AuthSession
    private let dataStore: LocalAppDataStore
    private let exatoService: ExatoService
    private let webHandoffService: PortalWebHandoffService

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let searchTextField = UITextField()
    private let searchButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let resultsContainer = UIStackView()
    private var currentSearchTask: Task<Void, Never>?

    init(
        session: AuthSession,
        dataStore: LocalAppDataStore,
        exatoService: ExatoService = ExatoService(),
        webHandoffService: PortalWebHandoffService = PortalWebHandoffService()
    ) {
        self.session = session
        self.dataStore = dataStore
        self.exatoService = exatoService
        self.webHandoffService = webHandoffService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        currentSearchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        refreshSearchButton(isLoading: false)
        renderIdleState()
    }

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        view.accessibilityIdentifier = "debtors.screen"

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Layout.stackSpacing
        stack.layoutMargins = UIEdgeInsets(
            top: Layout.topMargin,
            left: Layout.horizontalMargin,
            bottom: Layout.bottomMargin,
            right: Layout.horizontalMargin
        )
        stack.isLayoutMarginsRelativeArrangement = true

        resultsContainer.translatesAutoresizingMaskIntoConstraints = false
        resultsContainer.axis = .vertical
        resultsContainer.spacing = 16

        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let header = makeHeader()
        let cardsRow = makeInfoCardsRow()
        let searchCard = makeSearchCard()

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(cardsRow)
        stack.addArrangedSubview(searchCard)
        stack.addArrangedSubview(resultsContainer)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func makeHeader() -> UIView {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Localizar Devedor"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: Layout.sectionTitleSize, weight: .bold, textStyle: .largeTitle)
        titleLabel.accessibilityTraits = [.header]

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Consulte dados cadastrais e análise de crédito por CPF"
        subtitleLabel.textColor = UIColor(hex: "#688097")
        subtitleLabel.numberOfLines = 0
        subtitleLabel.applyScaledFont(size: 15, weight: .medium, textStyle: .body)

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeInfoCardsRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually

        row.addArrangedSubview(
            makeInfoCard(
                title: "Dados Completos",
                subtitle: "Dados cadastrais, endereços, telefones e situação fiscal",
                iconName: "doc.text",
                accentColor: UIColor(hex: "#10317F")
            )
        )

        row.addArrangedSubview(
            makeInfoCard(
                title: "Análise de Crédito",
                subtitle: "Score, risco, empresas vinculadas e protestos",
                iconName: "chart.line.uptrend.xyaxis",
                accentColor: UIColor(hex: "#1FA468")
            )
        )

        return row
    }

    private func makeInfoCard(title: String, subtitle: String, iconName: String, accentColor: UIColor) -> UIView {
        let card = makeSurfaceCard()

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12

        let iconBackground = UIView()
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = accentColor.withAlphaComponent(0.12)
        iconBackground.layer.cornerRadius = 10
        iconBackground.layer.cornerCurve = .continuous
        iconBackground.widthAnchor.constraint(equalToConstant: 36).isActive = true
        iconBackground.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let iconView = UIImageView(image: UIImage(systemName: iconName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = accentColor
        iconBackground.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor)
        ])

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 4

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.numberOfLines = 2
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 15, weight: .bold, textStyle: .headline)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = UIColor(hex: "#688097")
        subtitleLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .footnote)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        row.addArrangedSubview(iconBackground)
        row.addArrangedSubview(textStack)

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        return card
    }

    private func makeSearchCard() -> UIView {
        let card = makeSurfaceCard()

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14

        let fieldLabel = UILabel()
        fieldLabel.text = "CPF"
        fieldLabel.textColor = UIColor(hex: "#283344")
        fieldLabel.applyScaledFont(size: 14, weight: .semibold, textStyle: .headline)

        configureSearchField()

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.spacing = 12
        row.addArrangedSubview(searchTextField)
        row.addArrangedSubview(searchButton)

        searchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        searchButton.setContentHuggingPriority(.required, for: .horizontal)
        searchButton.heightAnchor.constraint(equalToConstant: Layout.actionHeight).isActive = true

        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        errorLabel.textColor = UIColor(hex: "#DC2626")
        errorLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .footnote)
        errorLabel.accessibilityIdentifier = "debtors.errorLabel"

        contentStack.addArrangedSubview(fieldLabel)
        contentStack.addArrangedSubview(row)
        contentStack.addArrangedSubview(errorLabel)
        contentStack.addArrangedSubview(makeLegalCard())

        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        return card
    }

    private func configureSearchField() {
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.placeholder = "000.000.000-00"
        searchTextField.setPlaceholderColor(UIColor(hex: "#7A8B9F"))
        searchTextField.textColor = UIColor(hex: "#2B3747")
        searchTextField.backgroundColor = UIColor(hex: "#F8FAFC")
        searchTextField.layer.cornerRadius = 12
        searchTextField.layer.cornerCurve = .continuous
        searchTextField.layer.borderWidth = 1
        searchTextField.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        searchTextField.heightAnchor.constraint(equalToConstant: Layout.fieldHeight).isActive = true
        searchTextField.setLeftPadding(14)
        searchTextField.delegate = self
        searchTextField.keyboardType = .numberPad
        searchTextField.returnKeyType = .search
        searchTextField.accessibilityIdentifier = "debtors.searchField"
        searchTextField.accessibilityLabel = "CPF"
        searchTextField.accessibilityHint = "Digite o CPF para consultar dados completos e análise de crédito."
        searchTextField.applyScaledFont(size: 16, weight: .regular, textStyle: .body)
        searchTextField.addTarget(self, action: #selector(searchFieldChanged), for: .editingChanged)
    }

    private func refreshSearchButton(isLoading: Bool) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        configuration.imagePlacement = .leading
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        configuration.title = isLoading ? "Consultando..." : "Consultar"
        configuration.baseBackgroundColor = UIColor(hex: "#10317F")
        configuration.baseForegroundColor = .white
        configuration.showsActivityIndicator = isLoading
        configuration.image = isLoading ? nil : UIImage(systemName: "magnifyingglass")
        searchButton.configuration = configuration
        searchButton.isEnabled = !isLoading
        searchButton.accessibilityIdentifier = "debtors.searchButton"
        searchButton.accessibilityLabel = configuration.title
        searchButton.updateAction(self, action: #selector(searchTapped))
    }

    private func makeLegalCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(hex: "#FFFBEF")
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#F0DCA5").cgColor

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 10

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.tintColor = UIColor(hex: "#C78615")
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = UIColor(hex: "#9B6210")
        label.applyScaledFont(size: 12, weight: .medium, textStyle: .footnote)
        label.text = "Aviso LGPD: Esta consulta acessa dados pessoais protegidos pela Lei 13.709/2018. Utilize apenas para finalidades legítimas de cobrança. O acesso é registrado para fins de auditoria."

        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func makeSurfaceCard(
        background: UIColor = UIColor(hex: "#F8FAFC"),
        border: UIColor = UIColor(hex: "#D7DEE8"),
        cornerRadius: CGFloat = Layout.cardCornerRadius
    ) -> UIView {
        let card = UIView()
        card.backgroundColor = background
        card.layer.cornerRadius = cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor
        return card
    }

    @objc private func searchTapped() {
        let cpfDigits = Formatters.digitsOnly(searchTextField.text ?? "")

        guard isValidCPF(cpfDigits) else {
            setInlineError("CPF inválido. Verifique os dígitos e tente novamente.")
            return
        }

        guard exatoService.isRemoteIntegrationEnabled else {
            setInlineError("Consulta Exato disponível apenas no modo remoto autenticado.")
            renderStatusCard(
                title: "Consulta indisponível",
                subtitle: "Faça login no ambiente remoto para consultar CPF com dados completos e análise de crédito.",
                iconName: "lock.shield"
            )
            return
        }

        view.endEditing(true)
        setInlineError(nil)
        currentSearchTask?.cancel()
        renderLoadingState()
        refreshSearchButton(isLoading: true)

        currentSearchTask = Task { [weak self] in
            guard let self else { return }

            async let pessoaResult: Result<ExatoPessoaFisicaResult, Error> = settledResult {
                try await self.exatoService.consultarPessoaFisica(cpf: cpfDigits)
            }
            async let creditoResult: Result<ExatoAnaliseCreditoResult, Error> = settledResult {
                try await self.exatoService.analisarCredito(cpf: cpfDigits)
            }

            let (pessoa, credito) = await (pessoaResult, creditoResult)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.refreshSearchButton(isLoading: false)
                self.handleSettledResults(pessoa: pessoa, credito: credito)
            }
        }
    }

    private func handleSettledResults(
        pessoa: Result<ExatoPessoaFisicaResult, Error>,
        credito: Result<ExatoAnaliseCreditoResult, Error>
    ) {
        let pessoaValue = try? pessoa.get()
        let creditoValue = try? credito.get()

        let genericError = "Erro ao consultar CPF. Verifique e tente novamente."
        let limitMessage = [pessoa.failure, credito.failure]
            .compactMap(extractPlanLimitMessage)
            .first

        if let limitMessage {
            setInlineError(nil)

            if pessoaValue == nil, creditoValue == nil {
                renderPlanLimitState(message: limitMessage)
            } else {
                renderResults(pessoa: pessoaValue, credito: creditoValue)
                appendResultView(
                    makePlanLimitCard(message: limitMessage) { [weak self] in
                        self?.removePlanLimitCards()
                    }
                )
            }
            return
        }

        if pessoaValue == nil, creditoValue == nil {
            setInlineError(genericError)
            renderStatusCard(
                title: "Não foi possível concluir a consulta",
                subtitle: genericError,
                iconName: "exclamationmark.triangle",
                background: UIColor(hex: "#FFF2F0"),
                border: UIColor(hex: "#F6C6C6"),
                accentColor: UIColor(hex: "#DC2626"),
                titleColor: UIColor(hex: "#2F3946"),
                subtitleColor: UIColor(hex: "#B63C3C")
            )
            return
        }

        renderResults(pessoa: pessoaValue, credito: creditoValue)
    }

    private func renderIdleState() {
        replaceResultViews(with: [])
    }

    private func renderLoadingState() {
        let card = makeSurfaceCard()

        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        indicator.color = UIColor(hex: "#10317F")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Consultando CPF"
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 17, weight: .bold, textStyle: .headline)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "Buscando dados cadastrais e análise de crédito."
        subtitleLabel.textColor = UIColor(hex: "#6E7F95")
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        card.addSubview(indicator)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            indicator.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        replaceResultViews(with: [card])
    }

    private func renderPlanLimitState(message: String) {
        replaceResultViews(with: [
            makePlanLimitCard(message: message) { [weak self] in
                self?.renderIdleState()
            }
        ])
    }

    private func renderStatusCard(
        title: String,
        subtitle: String,
        iconName: String,
        background: UIColor = UIColor(hex: "#F7FAFD"),
        border: UIColor = UIColor(hex: "#D7DEE8"),
        accentColor: UIColor = UIColor(hex: "#2E87C8"),
        titleColor: UIColor = UIColor(hex: "#283344"),
        subtitleColor: UIColor = UIColor(hex: "#6E7F95")
    ) {
        replaceResultViews(with: [
            BrandCardFactory.makeEmptyStateCard(
                title: title,
                subtitle: subtitle,
                iconSystemName: iconName,
                background: background,
                border: border,
                iconBackground: accentColor.withAlphaComponent(0.12),
                accentColor: accentColor,
                titleColor: titleColor,
                subtitleColor: subtitleColor
            )
        ])
    }

    private func makePlanLimitCard(message: String, onClose: @escaping () -> Void) -> UIView {
        let card = makeSurfaceCard(
            background: UIColor(hex: "#FFFBEF"),
            border: UIColor(hex: "#F0DCA5"),
            cornerRadius: 18
        )
        card.accessibilityIdentifier = "debtors.planLimitCard"

        let iconBackground = UIView()
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = UIColor(hex: "#C78615").withAlphaComponent(0.14)
        iconBackground.layer.cornerRadius = 18
        iconBackground.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(hex: "#C78615")
        iconBackground.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Continue sua experiência"
        titleLabel.textColor = UIColor(hex: "#2F3946")
        titleLabel.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = message
        messageLabel.textColor = UIColor(hex: "#9B6210")
        messageLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        messageLabel.numberOfLines = 0

        let buttonsRow = UIStackView()
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = 10
        buttonsRow.distribution = .fillEqually

        let closeButton = makePlanLimitActionButton(
            title: "Agora não",
            background: UIColor(hex: "#FFFFFF"),
            titleColor: UIColor(hex: "#6E7F95"),
            borderColor: UIColor(hex: "#D7DEE8")
        ) {
            onClose()
        }

        let plansButton = makePlanLimitActionButton(
            title: "Continuar na web",
            background: UIColor(hex: "#10317F"),
            titleColor: .white,
            borderColor: UIColor(hex: "#10317F")
        ) { [weak self] in
            self?.openMyPlanInBrowser()
        }

        buttonsRow.addArrangedSubview(closeButton)
        buttonsRow.addArrangedSubview(plansButton)

        card.addSubview(iconBackground)
        card.addSubview(titleLabel)
        card.addSubview(messageLabel)
        card.addSubview(buttonsRow)

        NSLayoutConstraint.activate([
            iconBackground.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconBackground.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconBackground.widthAnchor.constraint(equalToConstant: 36),
            iconBackground.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            buttonsRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            buttonsRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            buttonsRow.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            buttonsRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            buttonsRow.heightAnchor.constraint(equalToConstant: 44)
        ])

        return card
    }

    private func makePlanLimitActionButton(
        title: String,
        background: UIColor,
        titleColor: UIColor,
        borderColor: UIColor,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = background
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = borderColor.cgColor
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.applyScaledTitleFont(size: 15, weight: .semibold, textStyle: .headline)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func renderResults(pessoa: ExatoPessoaFisicaResult?, credito: ExatoAnaliseCreditoResult?) {
        var views: [UIView] = []

        if let pessoa {
            let personalFields: [InfoField] = [
                .init(title: "Nome", value: pessoa.nome),
                .init(title: "CPF", value: pessoa.cpf.formattedCPF),
                .init(title: "Idade", value: pessoa.idade.map { "\($0) anos" } ?? "—"),
                .init(title: "Sexo", value: pessoa.sexo ?? "—"),
                .init(title: "Data de Nascimento", value: pessoa.dataNascimento ?? "—"),
                .init(title: "Nome da Mãe", value: pessoa.nomeMae ?? "—"),
                .init(title: "Situação Receita", value: pessoa.situacaoCadastralReceita ?? "—")
            ].filter { $0.value != "—" }

            if !personalFields.isEmpty || pessoa.obitoRegistrado {
                views.append(makePersonalDataSection(result: pessoa, fields: personalFields))
            }

            if !pessoa.enderecos.isEmpty {
                views.append(makeAddressesSection(addresses: pessoa.enderecos))
            }

            if !pessoa.celulares.isEmpty {
                views.append(makePhonesSection(phones: pessoa.celulares))
            }
        }

        if let credito {
            if let score = credito.score, score.hasVisibleContent {
                views.append(makeCreditScoreSection(score: score))
            }

            if !credito.empresasVinculadas.isEmpty {
                views.append(makeCompaniesSection(companies: credito.empresasVinculadas))
            }

            views.append(makeProtestsSection(protests: credito.protestos))
        }

        replaceResultViews(with: views)
    }

    private func makePersonalDataSection(result: ExatoPessoaFisicaResult, fields: [InfoField]) -> UIView {
        let card = makeSectionCard(
            title: "Dados Pessoais",
            iconName: "person.crop.circle",
            accentColor: UIColor(hex: "#10317F")
        )

        let contentStack = sectionContentStack(in: card)

        if result.obitoRegistrado {
            contentStack.addArrangedSubview(
                makePill(
                    text: "Óbito registrado",
                    iconName: "exclamationmark.triangle",
                    background: UIColor(hex: "#FFF0F0"),
                    border: UIColor(hex: "#F6C6C6"),
                    foreground: UIColor(hex: "#DC2626")
                )
            )
        }

        contentStack.addArrangedSubview(makeFieldsGrid(fields))
        return card
    }

    private func makeAddressesSection(addresses: [ExatoAddress]) -> UIView {
        let card = makeSectionCard(
            title: "Endereços",
            iconName: "map",
            accentColor: UIColor(hex: "#10317F"),
            countText: "(\(addresses.count))"
        )

        let contentStack = sectionContentStack(in: card)
        addresses.forEach { address in
            let miniCard = makeMiniCard()

            let primaryLabel = UILabel()
            primaryLabel.numberOfLines = 0
            primaryLabel.textColor = UIColor(hex: "#283344")
            primaryLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
            primaryLabel.text = address.primaryLine

            let secondaryLabel = UILabel()
            secondaryLabel.numberOfLines = 0
            secondaryLabel.textColor = UIColor(hex: "#688097")
            secondaryLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .footnote)
            secondaryLabel.text = address.secondaryLine

            let stack = UIStackView(arrangedSubviews: [primaryLabel, secondaryLabel])
            stack.axis = .vertical
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            miniCard.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: miniCard.topAnchor, constant: 12),
                stack.leadingAnchor.constraint(equalTo: miniCard.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: miniCard.trailingAnchor, constant: -12),
                stack.bottomAnchor.constraint(equalTo: miniCard.bottomAnchor, constant: -12)
            ])

            contentStack.addArrangedSubview(miniCard)
        }

        return card
    }

    private func makePhonesSection(phones: [ExatoPhone]) -> UIView {
        let card = makeSectionCard(
            title: "Telefones",
            iconName: "phone",
            accentColor: UIColor(hex: "#10317F"),
            countText: "(\(phones.count))"
        )

        let fields = phones.map {
            InfoField(title: $0.type?.nilIfEmpty ?? "Telefone", value: $0.number)
        }

        sectionContentStack(in: card).addArrangedSubview(makeFieldsGrid(fields))
        return card
    }

    private func makeCreditScoreSection(score: ExatoCreditScore) -> UIView {
        let card = makeSectionCard(
            title: "Score de Crédito",
            iconName: "chart.line.uptrend.xyaxis",
            accentColor: UIColor(hex: "#1FA468")
        )

        let contentStack = sectionContentStack(in: card)
        let summaryRow = UIStackView()
        summaryRow.axis = .horizontal
        summaryRow.alignment = .center
        summaryRow.spacing = 18

        let scoreValueLabel = UILabel()
        scoreValueLabel.textAlignment = .center
        scoreValueLabel.numberOfLines = 0
        scoreValueLabel.textColor = scoreColor(for: score.pontuacao)
        scoreValueLabel.applyScaledFont(size: 42, weight: .bold, textStyle: .largeTitle)
        scoreValueLabel.text = score.pontuacao.map(String.init) ?? "—"
        scoreValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        scoreValueLabel.widthAnchor.constraint(equalToConstant: 88).isActive = true

        let scoreSuffixLabel = UILabel()
        scoreSuffixLabel.text = "de 1000"
        scoreSuffixLabel.textAlignment = .center
        scoreSuffixLabel.textColor = UIColor(hex: "#688097")
        scoreSuffixLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption1)

        let scoreStack = UIStackView(arrangedSubviews: [scoreValueLabel, scoreSuffixLabel])
        scoreStack.axis = .vertical
        scoreStack.spacing = 4

        let barStack = UIStackView()
        barStack.axis = .vertical
        barStack.spacing = 8

        let track = UIView()
        track.backgroundColor = UIColor(hex: "#E7F0F9")
        track.layer.cornerRadius = 6
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let fill = UIView()
        fill.backgroundColor = scoreColor(for: score.pontuacao)
        fill.layer.cornerRadius = 6
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        let progress = max(0, min(CGFloat(score.pontuacao ?? 0) / 1000, 1))
        if progress > 0 {
            NSLayoutConstraint.activate([
                fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
                fill.topAnchor.constraint(equalTo: track.topAnchor),
                fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
                fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: progress)
            ])
        } else {
            NSLayoutConstraint.activate([
                fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
                fill.topAnchor.constraint(equalTo: track.topAnchor),
                fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
                fill.widthAnchor.constraint(equalToConstant: 0)
            ])
        }

        let markers = UIStackView()
        markers.axis = .horizontal
        markers.distribution = .equalSpacing
        ["0", "250", "500", "750", "1000"].forEach { marker in
            let label = UILabel()
            label.text = marker
            label.textColor = UIColor(hex: "#688097")
            label.applyScaledFont(size: 10, weight: .medium, textStyle: .caption2)
            markers.addArrangedSubview(label)
        }

        barStack.addArrangedSubview(track)
        barStack.addArrangedSubview(markers)

        summaryRow.addArrangedSubview(scoreStack)
        summaryRow.addArrangedSubview(barStack)
        contentStack.addArrangedSubview(summaryRow)

        let metricRow = UIStackView()
        metricRow.axis = .horizontal
        metricRow.spacing = 12
        metricRow.distribution = .fillEqually
        metricRow.addArrangedSubview(
            makeMetricCard(
                title: "Nível de Risco",
                value: score.riscoNivel ?? score.faixa ?? "—",
                subtitle: score.riscoDescricao
            )
        )
        metricRow.addArrangedSubview(
            makeMetricCard(
                title: "Comprometimento de Pagamento",
                value: score.comprometimentoPagamento ?? "—",
                subtitle: score.descricaoComprometimentoPagamento
            )
        )
        metricRow.addArrangedSubview(
            makeMetricCard(
                title: "Pontuação de Perfil",
                value: score.pontuacaoPerfil ?? "—",
                subtitle: score.descricaoPontuacaoPerfil
            )
        )
        contentStack.addArrangedSubview(metricRow)

        return card
    }

    private func makeCompaniesSection(companies: [ExatoCompanyLink]) -> UIView {
        let card = makeSectionCard(
            title: "Empresas Vinculadas",
            iconName: "building.2",
            accentColor: UIColor(hex: "#7C4DFF"),
            countText: "(\(companies.count))"
        )

        let contentStack = sectionContentStack(in: card)
        companies.forEach { company in
            let fields = [
                InfoField(title: "Empresa", value: company.nomeEmpresa ?? "—"),
                InfoField(title: "CNPJ", value: company.cnpj.map { Formatters.formatCPFOrCNPJ($0) } ?? "—"),
                InfoField(title: "Tipo", value: company.tipo ?? "—"),
                InfoField(title: "Participação", value: company.percentualParticipacao.map { "\($0)%" } ?? "—"),
                InfoField(title: "Status CNPJ", value: company.statusCNPJ ?? "—"),
                InfoField(title: "Data de Início", value: company.dataInicio ?? "—")
            ].filter { $0.value != "—" }

            let miniCard = makeMiniCard()
            let grid = makeFieldsGrid(fields)
            miniCard.addSubview(grid)
            grid.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                grid.topAnchor.constraint(equalTo: miniCard.topAnchor, constant: 12),
                grid.leadingAnchor.constraint(equalTo: miniCard.leadingAnchor, constant: 12),
                grid.trailingAnchor.constraint(equalTo: miniCard.trailingAnchor, constant: -12),
                grid.bottomAnchor.constraint(equalTo: miniCard.bottomAnchor, constant: -12)
            ])
            contentStack.addArrangedSubview(miniCard)
        }

        return card
    }

    private func makeProtestsSection(protests: [ExatoProtest]) -> UIView {
        let card = makeSectionCard(
            title: "Protestos",
            iconName: "exclamationmark.triangle",
            accentColor: UIColor(hex: "#C78615")
        )

        let contentStack = sectionContentStack(in: card)

        if protests.isEmpty {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center

            let icon = UIImageView(image: UIImage(systemName: "checkmark.circle"))
            icon.tintColor = UIColor(hex: "#1FA468")

            let label = UILabel()
            label.text = "Nenhum protesto encontrado"
            label.textColor = UIColor(hex: "#1FA468")
            label.applyScaledFont(size: 14, weight: .semibold, textStyle: .body)

            row.addArrangedSubview(icon)
            row.addArrangedSubview(label)
            contentStack.addArrangedSubview(row)
        } else {
            protests.forEach { protest in
                let fields = [
                    InfoField(title: "Data da Consulta", value: protest.dataConsulta ?? "—"),
                    InfoField(title: "Cartório", value: protest.cartorio ?? "—"),
                    InfoField(title: "Valor", value: protest.valor.map { Formatters.normalizeCurrencyDisplay($0) } ?? "—"),
                    InfoField(title: "Cidade/UF", value: protest.cityState ?? "—")
                ].filter { $0.value != "—" }

                let miniCard = makeMiniCard(
                    background: UIColor(hex: "#FFFBEF"),
                    border: UIColor(hex: "#F0DCA5")
                )
                let grid = makeFieldsGrid(fields)
                miniCard.addSubview(grid)
                grid.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    grid.topAnchor.constraint(equalTo: miniCard.topAnchor, constant: 12),
                    grid.leadingAnchor.constraint(equalTo: miniCard.leadingAnchor, constant: 12),
                    grid.trailingAnchor.constraint(equalTo: miniCard.trailingAnchor, constant: -12),
                    grid.bottomAnchor.constraint(equalTo: miniCard.bottomAnchor, constant: -12)
                ])
                contentStack.addArrangedSubview(miniCard)
            }
        }

        return card
    }

    private func makeSectionCard(title: String, iconName: String, accentColor: UIColor, countText: String? = nil) -> UIView {
        let card = makeSurfaceCard()

        let container = UIStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 14

        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 10

        let iconBackground = UIView()
        iconBackground.backgroundColor = accentColor.withAlphaComponent(0.12)
        iconBackground.layer.cornerRadius = 10
        iconBackground.layer.cornerCurve = .continuous
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.widthAnchor.constraint(equalToConstant: 34).isActive = true
        iconBackground.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let iconView = UIImageView(image: UIImage(systemName: iconName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = accentColor
        iconBackground.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 16, weight: .bold, textStyle: .headline)

        headerRow.addArrangedSubview(iconBackground)
        headerRow.addArrangedSubview(titleLabel)

        if let countText {
            let countLabel = UILabel()
            countLabel.text = countText
            countLabel.textColor = UIColor(hex: "#688097")
            countLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption1)
            headerRow.addArrangedSubview(countLabel)
        }

        headerRow.addArrangedSubview(UIView())

        container.addArrangedSubview(headerRow)
        card.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            container.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        card.accessibilityLabel = title
        return card
    }

    private func sectionContentStack(in card: UIView) -> UIStackView {
        guard let container = card.subviews.compactMap({ $0 as? UIStackView }).first else {
            let fallback = UIStackView()
            fallback.axis = .vertical
            fallback.spacing = 14
            return fallback
        }
        return container
    }

    private func makeFieldsGrid(_ fields: [InfoField]) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        for rowItems in fields.chunked(into: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.alignment = .fill
            row.spacing = 12

            for item in rowItems {
                row.addArrangedSubview(makeFieldView(title: item.title, value: item.value))
            }

            if rowItems.count == 1 {
                row.addArrangedSubview(UIView())
            }

            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func makeFieldView(title: String, value: String) -> UIView {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = UIColor(hex: "#688097")
        titleLabel.applyScaledFont(size: 11, weight: .semibold, textStyle: .caption1)

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = value
        valueLabel.numberOfLines = 0
        valueLabel.textColor = UIColor(hex: "#283344")
        valueLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            valueLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeMetricCard(title: String, value: String, subtitle: String?) -> UIView {
        let card = makeMiniCard()

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.textColor = UIColor(hex: "#688097")
        titleLabel.applyScaledFont(size: 11, weight: .semibold, textStyle: .caption1)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.numberOfLines = 0
        valueLabel.textColor = UIColor(hex: "#283344")
        valueLabel.applyScaledFont(size: 14, weight: .bold, textStyle: .body)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)

        if let subtitle = subtitle?.nilIfEmpty {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.numberOfLines = 0
            subtitleLabel.textColor = UIColor(hex: "#688097")
            subtitleLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption1)
            stack.addArrangedSubview(subtitleLabel)
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func makeMiniCard(
        background: UIColor = UIColor(hex: "#F3F7FB"),
        border: UIColor = UIColor(hex: "#D7DEE8")
    ) -> UIView {
        let card = UIView()
        card.backgroundColor = background
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor
        return card
    }

    private func makePill(text: String, iconName: String, background: UIColor, border: UIColor, foreground: UIColor) -> UIView {
        let container = UIView()
        container.backgroundColor = background
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = border.cgColor

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.tintColor = foreground
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let label = UILabel()
        label.text = text
        label.textColor = foreground
        label.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func replaceResultViews(with views: [UIView]) {
        resultsContainer.arrangedSubviews.forEach { view in
            resultsContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        views.forEach { resultsContainer.addArrangedSubview($0) }
    }

    private func appendResultView(_ view: UIView) {
        resultsContainer.addArrangedSubview(view)
    }

    private func removePlanLimitCards() {
        let cards = resultsContainer.arrangedSubviews.filter { $0.accessibilityIdentifier == "debtors.planLimitCard" }
        cards.forEach { card in
            resultsContainer.removeArrangedSubview(card)
            card.removeFromSuperview()
        }
    }

    private func setInlineError(_ message: String?) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        errorLabel.text = trimmed
        errorLabel.isHidden = trimmed?.isEmpty != false
    }

    private func scoreColor(for score: Int?) -> UIColor {
        let value = score ?? 0
        if value >= 700 { return UIColor(hex: "#1FA468") }
        if value >= 400 { return UIColor(hex: "#C78615") }
        return UIColor(hex: "#DC2626")
    }

    private func extractPlanLimitMessage(from error: Error?) -> String? {
        guard let error = error else { return nil }
        guard case let RemoteAPIClientError.server(statusCode, _) = error, statusCode == 402 else {
            return nil
        }
        return "Para acessar todos os recursos da sua conta, continue pela versão web."
    }

    private func openMyPlanInBrowser() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let url = try await webHandoffService.fetchURL(for: .myPlan)
                await MainActor.run {
                    UIApplication.shared.open(url) { [weak self] success in
                        guard success == false else { return }
                        self?.setInlineError("Não consegui abrir a versão web agora.")
                    }
                }
            } catch {
                await MainActor.run {
                    self.setInlineError(error.localizedDescription)
                }
            }
        }
    }

    private func isValidCPF(_ cpf: String) -> Bool {
        guard cpf.count == 11 else { return false }
        guard Set(cpf).count > 1 else { return false }

        let digits = cpf.compactMap { $0.wholeNumberValue }
        guard digits.count == 11 else { return false }

        let firstVerifier = cpfVerifierDigit(for: Array(digits.prefix(9)))
        let secondVerifier = cpfVerifierDigit(for: Array(digits.prefix(10)))
        return digits[9] == firstVerifier && digits[10] == secondVerifier
    }

    private func cpfVerifierDigit(for digits: [Int]) -> Int {
        let factorStart = digits.count + 1
        let total = digits.enumerated().reduce(0) { partial, entry in
            let factor = factorStart - entry.offset
            return partial + (entry.element * factor)
        }

        let remainder = (total * 10) % 11
        return remainder == 10 ? 0 : remainder
    }

    private func settledResult<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    @objc private func searchFieldChanged() {
        searchTextField.text = Formatters.formatCPF(searchTextField.text ?? "")
        if errorLabel.isHidden == false {
            setInlineError(nil)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        searchTapped()
        return true
    }
}

private extension UIButton {
    func updateAction(_ target: Any?, action: Selector) {
        removeTarget(nil, action: nil, for: .touchUpInside)
        addTarget(target, action: action, for: .touchUpInside)
    }
}

private extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftView = spacer
        leftViewMode = .always
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var formattedCPF: String {
        let digits = filter(\.isNumber)
        guard digits.count == 11 else { return self }

        var formatted = ""
        for (index, char) in digits.enumerated() {
            switch index {
            case 3, 6: formatted.append(".")
            case 9: formatted.append("-")
            default: break
            }
            formatted.append(char)
        }
        return formatted
    }
}

private extension ExatoCreditScore {
    var hasVisibleContent: Bool {
        pontuacao != nil ||
        faixa?.nilIfEmpty != nil ||
        riscoNivel?.nilIfEmpty != nil ||
        riscoDescricao?.nilIfEmpty != nil ||
        comprometimentoPagamento?.nilIfEmpty != nil ||
        descricaoComprometimentoPagamento?.nilIfEmpty != nil ||
        pontuacaoPerfil?.nilIfEmpty != nil ||
        descricaoPontuacaoPerfil?.nilIfEmpty != nil
    }
}

private extension ExatoProtest {
    var cityState: String? {
        let city = cidade?.nilIfEmpty
        let state = uf?.nilIfEmpty

        switch (city, state) {
        case let (.some(city), .some(state)):
            return "\(city)/\(state)"
        case let (.some(city), .none):
            return city
        case let (.none, .some(state)):
            return state
        default:
            return nil
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case let .failure(error) = self {
            return error
        }
        return nil
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { index in
            Array(self[index ..< Swift.min(index + size, count)])
        }
    }
}
