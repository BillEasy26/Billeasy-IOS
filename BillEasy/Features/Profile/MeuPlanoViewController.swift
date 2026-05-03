import UIKit

/// Aqui eu entrego a tela de assinatura no padrão do app Kotlin, mas respeitando a arquitetura UIKit já existente.
final class MeuPlanoViewController: UIViewController {
    private let session: AuthSession
    private let dataStore: LocalAppDataStore
    private let subscriptionService: PortalSubscriptionService
    private let webHandoffService: PortalWebHandoffService

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let loadingView = UIActivityIndicatorView(style: .large)
    private let emptyStateContainer = UIView()

    private var loadTask: Task<Void, Never>?
    private var currentDashboard: PortalSubscriptionDashboard?

    init(
        session: AuthSession,
        dataStore: LocalAppDataStore,
        subscriptionService: PortalSubscriptionService? = nil,
        webHandoffService: PortalWebHandoffService = PortalWebHandoffService()
    ) {
        self.session = session
        self.dataStore = dataStore
        self.subscriptionService = subscriptionService ?? PortalSubscriptionService(dataStore: dataStore)
        self.webHandoffService = webHandoffService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupLayout()
        loadDashboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
        if let dashboard = currentDashboard {
            renderContent(with: dashboard)
        }
    }

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16

        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.hidesWhenStopped = true
        loadingView.color = UIColor(hex: "#1579A8")

        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.isHidden = true

        view.addSubview(scrollView)
        view.addSubview(loadingView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)
        view.addSubview(emptyStateContainer)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),

            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyStateContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyStateContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func applyTheme() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        scrollView.backgroundColor = .clear
        contentView.backgroundColor = .clear
        loadingView.color = UIColor(hex: "#1579A8")
    }

    /// Aqui eu recarrego a assinatura inteira para garantir que a UI reflita o backend e não um cache quebrado.
    private func loadDashboard() {
        loadTask?.cancel()
        setLoading(true)
        hideEmptyState()

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let dashboard = try await self.subscriptionService.fetchDashboard()

                await MainActor.run {
                    self.currentDashboard = dashboard
                    self.setLoading(false)
                    self.renderContent(with: dashboard)
                }
            } catch {
                await MainActor.run {
                    self.currentDashboard = nil
                    self.setLoading(false)
                    self.renderError(error.localizedDescription)
                }
            }
        }
    }

    private func setLoading(_ isLoading: Bool) {
        scrollView.isHidden = isLoading
        emptyStateContainer.isHidden = true
        if isLoading {
            loadingView.startAnimating()
        } else {
            loadingView.stopAnimating()
        }
    }

    private func hideEmptyState() {
        emptyStateContainer.subviews.forEach { $0.removeFromSuperview() }
        emptyStateContainer.isHidden = true
    }

    private func renderError(_ message: String) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        emptyStateContainer.subviews.forEach { $0.removeFromSuperview() }

        let card = BrandCardFactory.makeEmptyStateCard(
            title: "Não consegui carregar seu plano",
            subtitle: message,
            iconSystemName: "exclamationmark.triangle"
        )
        card.translatesAutoresizingMaskIntoConstraints = false

        let retryButton = makePrimaryButton(title: "Tentar novamente")
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [card, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14

        emptyStateContainer.addSubview(stack)
        emptyStateContainer.isHidden = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: emptyStateContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: emptyStateContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: emptyStateContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: emptyStateContainer.bottomAnchor),
            retryButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func renderContent(with dashboard: PortalSubscriptionDashboard) {
        emptyStateContainer.isHidden = true
        scrollView.isHidden = false
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let subscription = dashboard.current
        contentStack.addArrangedSubview(makeHeader(for: subscription))

        if subscription.status.uppercased() == "INADIMPLENTE" {
            contentStack.addArrangedSubview(
                makeBanner(
                    icon: "exclamationmark.triangle.fill",
                    title: "Pagamento pendente",
                    message: "Sua assinatura está inadimplente. Regularize para manter acesso total aos recursos.",
                    background: UIColor(hex: "#FEF3C7"),
                    border: UIColor(hex: "#F0DCA5"),
                    titleColor: UIColor(hex: "#B45309"),
                    messageColor: UIColor(hex: "#B45309")
                )
            )
        }

        if subscription.status.uppercased() == "CANCELADA" {
            contentStack.addArrangedSubview(
                makeBanner(
                    icon: "info.circle.fill",
                    title: "Assinatura cancelada",
                    message: "Você voltou ao plano Free. Seus limites atuais já refletem essa mudança.",
                    background: UIColor(hex: "#F3F4F6"),
                    border: UIColor(hex: "#D7DEE8"),
                    titleColor: UIColor(hex: "#6B7280"),
                    messageColor: UIColor(hex: "#6E7F95")
                )
            )
        } else if subscription.status.uppercased() == "EXPIRADA" {
            contentStack.addArrangedSubview(
                makeBanner(
                    icon: "clock.arrow.circlepath",
                    title: "Assinatura expirada",
                    message: "Abra a web para reativar seu plano e voltar a usar os limites completos do Standard.",
                    background: UIColor(hex: "#F3F4F6"),
                    border: UIColor(hex: "#D7DEE8"),
                    titleColor: UIColor(hex: "#6B7280"),
                    messageColor: UIColor(hex: "#6E7F95")
                )
            )
        }

        contentStack.addArrangedSubview(makeCurrentPlanCard(subscription))
        contentStack.addArrangedSubview(makeQuotaRow(subscription))

        if subscription.isStandardPlan {
            contentStack.addArrangedSubview(makeAddonsCard(subscription))
            contentStack.addArrangedSubview(makeCancelCard(subscription))
        }

        if subscription.isFreePlan {
            contentStack.addArrangedSubview(makeUpgradeCard(dashboard))
        }
    }

    private func makeHeader(for subscription: PortalSubscriptionSnapshot) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Meu Plano"
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 24, weight: .bold, textStyle: .largeTitle)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Gerencie sua assinatura e cotas"
        subtitleLabel.textColor = UIColor(hex: "#6E7F95")
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)

        let badge = StatusBadgeView(text: subscription.statusTitle, style: badgeStyle(for: subscription.status))
        badge.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(badge)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),

            badge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeCurrentPlanCard(_ subscription: PortalSubscriptionSnapshot) -> UIView {
        let card = makeSurfaceCard()
        let contentInset: CGFloat = 24

        let crownView = UIImageView(image: UIImage(systemName: "crown.fill"))
        crownView.translatesAutoresizingMaskIntoConstraints = false
        crownView.tintColor = UIColor(hex: "#1579A8")
        crownView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)

        let planNameLabel = UILabel()
        planNameLabel.translatesAutoresizingMaskIntoConstraints = false
        planNameLabel.text = subscription.plan.name
        planNameLabel.textColor = UIColor(hex: "#283344")
        planNameLabel.applyScaledFont(size: 16, weight: .semibold, textStyle: .headline)

        let priceLabel = UILabel()
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.textAlignment = .right
        priceLabel.textColor = UIColor(hex: "#283344")
        priceLabel.applyScaledFont(size: 18, weight: .bold, textStyle: .title2)
        priceLabel.text = subscription.plan.monthlyPrice > 0 ? Formatters.currencyText(from: subscription.plan.monthlyPrice) : "Grátis"

        let perMonthLabel = UILabel()
        perMonthLabel.translatesAutoresizingMaskIntoConstraints = false
        perMonthLabel.textColor = UIColor(hex: "#6E7F95")
        perMonthLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .caption1)
        perMonthLabel.text = subscription.plan.monthlyPrice > 0 ? "/mês" : nil
        perMonthLabel.isHidden = subscription.plan.monthlyPrice <= 0

        let priceStack = UIStackView(arrangedSubviews: [priceLabel, perMonthLabel])
        priceStack.translatesAutoresizingMaskIntoConstraints = false
        priceStack.axis = .horizontal
        priceStack.alignment = .lastBaseline
        priceStack.spacing = 4

        let topRow = UIStackView(arrangedSubviews: [crownView, planNameLabel, UIView(), priceStack])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 8

        card.addSubview(topRow)

        var lastBottomAnchor = topRow.bottomAnchor

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: card.topAnchor, constant: contentInset),
            topRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
            topRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset)
        ])

        if subscription.status.uppercased() == "TRIAL", let trialEndsAt = subscription.trialEndsAt {
            let banner = makeBanner(
                icon: "clock.fill",
                title: "Trial ativo até \(Formatters.fullNumericDate.string(from: trialEndsAt))",
                message: nil,
                background: UIColor(hex: "#FEF3C7"),
                border: UIColor(hex: "#F0DCA5"),
                titleColor: UIColor(hex: "#B45309"),
                messageColor: UIColor(hex: "#B45309")
            )
            banner.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
                banner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
                banner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset)
            ])
            lastBottomAnchor = banner.bottomAnchor
        }

        if let cycleText = cycleText(for: subscription) {
            let cycleLabel = UILabel()
            cycleLabel.translatesAutoresizingMaskIntoConstraints = false
            cycleLabel.text = cycleText
            cycleLabel.textColor = UIColor(hex: "#6E7F95")
            cycleLabel.numberOfLines = 0
            cycleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)
            card.addSubview(cycleLabel)

            NSLayoutConstraint.activate([
                cycleLabel.topAnchor.constraint(equalTo: lastBottomAnchor, constant: 8),
                cycleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
                cycleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset),
                cycleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -contentInset)
            ])
        } else {
            NSLayoutConstraint.activate([
                lastBottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -contentInset)
            ])
        }

        return card
    }

    private func makeQuotaRow(_ subscription: PortalSubscriptionSnapshot) -> UIView {
        let row = UIStackView(arrangedSubviews: [
            QuotaCardView(snapshot: subscription.contractQuota),
            QuotaCardView(snapshot: subscription.debtorQueryQuota)
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 16
        return row
    }

    private func makeUpgradeCard(_ dashboard: PortalSubscriptionDashboard) -> UIView {
        let card = makeSurfaceCard(background: UIColor(hex: "#E8F2FA"), border: UIColor(hex: "#C8D6E8"), borderWidth: 2)
        let contentInset: CGFloat = 24

        let badge = makeIconBadge(systemName: "bolt.fill", background: UIColor(hex: "#E1EEF8"), tint: UIColor(hex: "#1579A8"))
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Plano Standard"
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 16, weight: .semibold, textStyle: .headline)

        let standardPlan = dashboard.standardPlan
        let descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = UIColor(hex: "#607993")
        descriptionLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        let planPrice = standardPlan.map { Formatters.currencyText(from: $0.monthlyPrice) } ?? "R$ 19,90"
        let contracts = standardPlan?.maxContracts ?? 10
        let queries = standardPlan?.maxDebtorQueries ?? 2
        descriptionLabel.text = "\(contracts) contratos, \(queries) consultas/ciclo, add-ons disponíveis — \(planPrice)/mês"

        let trialLabel = UILabel()
        trialLabel.translatesAutoresizingMaskIntoConstraints = false
        trialLabel.numberOfLines = 0
        trialLabel.textColor = UIColor(hex: "#607993")
        trialLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)
        trialLabel.text = "Você será redirecionado ao portal para ativar sua conta."

        let button = makePrimaryButton(title: "Ver detalhes no portal")
        button.addTarget(self, action: #selector(openWebBillingTapped), for: .touchUpInside)
        button.isEnabled = webHandoffService.isAvailable

        card.addSubview(badge)
        card.addSubview(titleLabel)
        card.addSubview(descriptionLabel)
        card.addSubview(trialLabel)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: contentInset),
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
            badge.widthAnchor.constraint(equalToConstant: 40),
            badge.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: contentInset),
            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset),

            trialLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 4),
            trialLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            trialLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset),

            button.topAnchor.constraint(equalTo: trialLabel.bottomAnchor, constant: 16),
            button.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset),
            button.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -contentInset),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        return card
    }

    private func makeAddonsCard(_ subscription: PortalSubscriptionSnapshot) -> UIView {
        let card = makeSurfaceCard()
        let contentInset: CGFloat = 24
        let titleRow = makeSectionTitleRow(icon: "shippingbox.fill", title: "Serviços Adicionais")
        card.addSubview(titleRow)

        NSLayoutConstraint.activate([
            titleRow.topAnchor.constraint(equalTo: card.topAnchor, constant: contentInset),
            titleRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
            titleRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset)
        ])

        var lastAnchor = titleRow.bottomAnchor

        if subscription.addons.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.numberOfLines = 0
            emptyLabel.text = "Nenhum serviço adicional ativo."
            emptyLabel.textColor = UIColor(hex: "#6E7F95")
            emptyLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
            card.addSubview(emptyLabel)

            NSLayoutConstraint.activate([
                emptyLabel.topAnchor.constraint(equalTo: lastAnchor, constant: 16),
                emptyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
                emptyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset)
            ])
            lastAnchor = emptyLabel.bottomAnchor
        } else {
            for addon in subscription.addons {
                let row = AddonItemView(addon: addon)
                card.addSubview(row)
                NSLayoutConstraint.activate([
                    row.topAnchor.constraint(equalTo: lastAnchor, constant: 8),
                    row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
                    row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset)
                ])
                lastAnchor = row.bottomAnchor
            }
        }

        let helperLabel = UILabel()
        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        helperLabel.numberOfLines = 0
        helperLabel.text = "Serviços adicionais são gerenciados no portal web."
        helperLabel.textColor = UIColor(hex: "#6E7F95")
        helperLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)
        card.addSubview(helperLabel)

        let manageButton = makeOutlineButton(title: "Gerenciar no portal", action: #selector(openWebBillingTapped))
        manageButton.isEnabled = webHandoffService.isAvailable
        card.addSubview(manageButton)

        NSLayoutConstraint.activate([
            helperLabel.topAnchor.constraint(equalTo: lastAnchor, constant: 4),
            helperLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
            helperLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset),

            manageButton.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 16),
            manageButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: contentInset),
            manageButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -contentInset),
            manageButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -contentInset)
        ])

        return card
    }

    private func makeCancelCard(_ subscription: PortalSubscriptionSnapshot) -> UIView {
        let card = makeSurfaceCard(background: UIColor(hex: "#FFFFFF"), border: UIColor(hex: "#D7DEE8"))
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Gerenciar Assinatura"
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Mudança de plano e cancelamento são gerenciados no portal."
        subtitleLabel.textColor = UIColor(hex: "#6E7F95")
        subtitleLabel.numberOfLines = 0
        subtitleLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)

        let button = makeOutlineButton(title: "Gerenciar na web", action: #selector(openWebBillingTapped))
        button.isEnabled = webHandoffService.isAvailable

        let copyStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        copyStack.translatesAutoresizingMaskIntoConstraints = false
        copyStack.axis = .vertical
        copyStack.spacing = 4

        card.addSubview(copyStack)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            copyStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            copyStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            copyStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),

            button.leadingAnchor.constraint(greaterThanOrEqualTo: copyStack.trailingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            button.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 40),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 148)
        ])

        return card
    }

    private func makeSurfaceCard(
        background: UIColor = UIColor(hex: "#FFFFFF"),
        border: UIColor = UIColor(hex: "#D7DEE8"),
        borderWidth: CGFloat = 1
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = background
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = borderWidth
        card.layer.borderColor = border.cgColor
        return card
    }

    private func makeSectionTitleRow(icon: String, title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(hex: "#1579A8")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = UIColor(hex: "#283344")
        label.applyScaledFont(size: 17, weight: .bold, textStyle: .headline)

        container.addSubview(iconView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    private func makeIconBadge(systemName: String, background: UIColor, tint: UIColor) -> UIView {
        let badge = UIView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.backgroundColor = background
        badge.layer.cornerRadius = 12
        badge.layer.cornerCurve = .continuous

        let imageView = UIImageView(image: UIImage(systemName: systemName))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = tint
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        badge.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])

        return badge
    }

    private func makeBanner(
        icon: String,
        title: String,
        message: String?,
        background: UIColor,
        border: UIColor,
        titleColor: UIColor,
        messageColor: UIColor
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = background
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = titleColor
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = titleColor
        titleLabel.numberOfLines = 0
        titleLabel.applyScaledFont(size: 14, weight: .bold, textStyle: .subheadline)

        card.addSubview(iconView)
        card.addSubview(titleLabel)

        var constraints = [
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14)
        ]

        if let message, message.isEmpty == false {
            let messageLabel = UILabel()
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.text = message
            messageLabel.textColor = messageColor
            messageLabel.numberOfLines = 0
            messageLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)
            card.addSubview(messageLabel)

            constraints += [
                messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
                messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                messageLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
            ]
        } else {
            constraints += [
                titleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return card
    }

    private func makePrimaryButton(title: String) -> UIButton {
        let button = StableSubscriptionButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.automaticallyUpdatesConfiguration = false
        button.configuration = nil
        button.backgroundColor = UIColor(hex: "#1579A8")
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.setDisplayTitle(title)
        button.setDisplayTitleColor(.white, disabled: UIColor.white.withAlphaComponent(0.75))
        button.setDisplayBackgroundColor(UIColor(hex: "#1579A8"), disabled: UIColor(hex: "#A9C9E6"))
        button.contentHorizontalAlignment = .center
        button.applyScaledTitleFont(size: 16, weight: .bold, textStyle: .headline)
        button.applyVisibleTitleFont(size: 16, weight: .bold, textStyle: .headline)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        return button
    }

    private func makeOutlineButton(title: String, action: Selector) -> UIButton {
        let button = StableSubscriptionButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.automaticallyUpdatesConfiguration = false
        button.configuration = nil
        button.setDisplayTitle(title)
        button.backgroundColor = UIColor(hex: "#FFFFFF")
        button.layer.cornerRadius = 8
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        button.tintColor = UIColor(hex: "#1579A8")
        button.setDisplayTitleColor(UIColor(hex: "#1579A8"), disabled: UIColor(hex: "#8AA0B6"))
        button.setDisplayBackgroundColor(UIColor(hex: "#FFFFFF"), disabled: UIColor(hex: "#F3F7FB"))
        button.applyScaledTitleFont(size: 15, weight: .semibold, textStyle: .subheadline)
        button.applyVisibleTitleFont(size: 15, weight: .semibold, textStyle: .subheadline)
        button.contentHorizontalAlignment = .center
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func badgeStyle(for status: String) -> StatusBadgeStyle {
        switch status.uppercased() {
        case "ATIVA", "TRIAL":
            return StatusBadgeStyle(
                backgroundColor: UIColor(hex: "#DCFCE7"),
                borderColor: UIColor(hex: "#BEE5CB"),
                textColor: UIColor(hex: "#15803D")
            )
        case "INADIMPLENTE":
            return StatusBadgeStyle(
                backgroundColor: UIColor(hex: "#FEF3C7"),
                borderColor: UIColor(hex: "#F0DCA5"),
                textColor: UIColor(hex: "#B45309")
            )
        default:
            return StatusBadgeStyle(
                backgroundColor: UIColor(hex: "#F3F4F6"),
                borderColor: UIColor(hex: "#D7DEE8"),
                textColor: UIColor(hex: "#6B7280")
            )
        }
    }

    private func cycleText(for subscription: PortalSubscriptionSnapshot) -> String? {
        guard let cycleStartsAt = subscription.cycleStartsAt, let cycleEndsAt = subscription.cycleEndsAt else {
            return nil
        }
        return "Ciclo atual: \(Formatters.fullNumericDate.string(from: cycleStartsAt)) — \(Formatters.fullNumericDate.string(from: cycleEndsAt))"
    }

    @objc private func retryTapped() {
        loadDashboard()
    }

    @objc private func openWebBillingTapped() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let url = try await webHandoffService.fetchURL(for: .myPlan)
                await MainActor.run {
                    UIApplication.shared.open(url) { [weak self] success in
                        guard success == false else { return }
                        self?.showSimpleToast("Não consegui abrir o site agora.", style: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }
}

private struct StatusBadgeStyle {
    let backgroundColor: UIColor
    let borderColor: UIColor
    let textColor: UIColor
}

private final class StatusBadgeView: UIView {
    private let label = UILabel()

    init(text: String, style: StatusBadgeStyle) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = style.backgroundColor
        layer.cornerRadius = 999
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = style.borderColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = style.textColor
        label.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)

        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class QuotaCardView: UIView {
    private let snapshot: PortalQuotaSnapshot
    private let progressContainer = UIView()
    private let progressFill = UIView()
    private var progressWidthConstraint: NSLayoutConstraint?

    init(snapshot: PortalQuotaSnapshot) {
        self.snapshot = snapshot
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        layoutIfNeeded()
        progressWidthConstraint?.isActive = false
        progressWidthConstraint = progressFill.widthAnchor.constraint(equalTo: progressContainer.widthAnchor, multiplier: max(snapshot.progressFraction, 0.02))
        progressWidthConstraint?.isActive = true
        UIView.animate(withDuration: 0.35) {
            self.layoutIfNeeded()
        }
    }

    private func build() {
        backgroundColor = UIColor(hex: "#FFFFFF")
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = snapshot.label
        titleLabel.textColor = UIColor(hex: "#6E7F95")
        titleLabel.numberOfLines = 2
        titleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = "\(snapshot.used) / \(snapshot.limit)"
        valueLabel.textColor = UIColor(hex: "#283344")
        valueLabel.applyScaledFont(size: 14, weight: .semibold, textStyle: .headline)

        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.backgroundColor = UIColor(hex: "#F3F4F6")
        progressContainer.layer.cornerRadius = 999
        progressContainer.layer.cornerCurve = .continuous

        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.backgroundColor = progressColor(for: snapshot.progressState)
        progressFill.layer.cornerRadius = 999
        progressFill.layer.cornerCurve = .continuous

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(progressContainer)
        progressContainer.addSubview(progressFill)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            progressContainer.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 8),
            progressContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            progressContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            progressContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            progressContainer.heightAnchor.constraint(equalToConstant: 10),

            progressFill.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor)
        ])
        progressWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true
    }

    private func progressColor(for state: PortalQuotaProgressState) -> UIColor {
        switch state {
        case .normal:
            return UIColor(hex: "#1579A8")
        case .warning:
            return UIColor(hex: "#F59E0B")
        case .critical:
            return UIColor(hex: "#EF4444")
        }
    }
}

private final class AddonItemView: UIView {
    init(addon: PortalSubscriptionAddon) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(hex: "#F3F7FB")
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "\(addon.label) ×\(addon.quantity)"
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "\(addon.availableQuantity) disponível · \(addon.consumedQuantity) utilizados"
        subtitleLabel.textColor = UIColor(hex: "#6E7F95")
        subtitleLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)

        let totalPriceLabel = UILabel()
        totalPriceLabel.translatesAutoresizingMaskIntoConstraints = false
        totalPriceLabel.textAlignment = .right
        totalPriceLabel.textColor = UIColor(hex: "#6E7F95")
        totalPriceLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)
        let totalPrice = addon.unitPrice * Decimal(addon.quantity)
        totalPriceLabel.text = addon.unitPrice > 0 ? "\(Formatters.currencyText(from: totalPrice)) (único)" : nil
        totalPriceLabel.isHidden = addon.unitPrice <= 0

        let badge = StatusBadgeView(text: addonStatusLabel(addon.paymentStatus), style: addonStatusStyle(addon.paymentStatus))
        badge.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(totalPriceLabel)
        addSubview(badge)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: totalPriceLabel.leadingAnchor, constant: -10),

            totalPriceLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            totalPriceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            totalPriceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -10),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badge.topAnchor.constraint(equalTo: totalPriceLabel.bottomAnchor, constant: 8),
            badge.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addonStatusLabel(_ status: String) -> String {
        switch status.uppercased() {
        case "APROVADO", "PAGO":
            return "Aprovado"
        case "PENDENTE":
            return "Aguardando pagamento"
        case "FALHOU":
            return "Pagamento falhou"
        default:
            return status.capitalized
        }
    }

    private func addonStatusStyle(_ status: String) -> StatusBadgeStyle {
        switch status.uppercased() {
        case "APROVADO", "PAGO":
            return StatusBadgeStyle(
                backgroundColor: UIColor(hex: "#DCFCE7"),
                borderColor: UIColor(hex: "#BEE5CB"),
                textColor: UIColor(hex: "#15803D")
            )
        case "PENDENTE":
            return StatusBadgeStyle(
                backgroundColor: UIColor(hex: "#FEF3C7"),
                borderColor: UIColor(hex: "#F0DCA5"),
                textColor: UIColor(hex: "#B45309")
            )
        case "FALHOU":
            return StatusBadgeStyle(
                backgroundColor: UIColor(hex: "#FFF0F0"),
                borderColor: UIColor(hex: "#F6C6C6"),
                textColor: UIColor(hex: "#B91C1C")
            )
        default:
            return StatusBadgeStyle(
                backgroundColor: UIColor(hex: "#F3F4F6"),
                borderColor: UIColor(hex: "#D7DEE8"),
                textColor: UIColor(hex: "#6B7280")
            )
        }
    }
}

private final class StableSubscriptionButton: UIButton {
    private var normalTitleColor: UIColor = .white
    private var disabledTitleColor: UIColor = UIColor.white.withAlphaComponent(0.75)
    private var normalBackgroundColor: UIColor?
    private var disabledBackgroundColor: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet { updateRenderedState() }
    }

    override var isHighlighted: Bool {
        didSet { updateRenderedState() }
    }

    func setDisplayTitle(_ title: String) {
        super.setTitle(title, for: .normal)
        super.setTitle(title, for: .highlighted)
        super.setTitle(title, for: .selected)
        accessibilityLabel = title
    }

    func setDisplayTitleColor(_ color: UIColor, disabled: UIColor) {
        normalTitleColor = color
        disabledTitleColor = disabled
        setTitleColor(color, for: .normal)
        setTitleColor(color, for: .highlighted)
        setTitleColor(color, for: .selected)
        setTitleColor(disabled, for: .disabled)
        updateRenderedState()
    }

    func setDisplayBackgroundColor(_ color: UIColor?, disabled: UIColor?) {
        normalBackgroundColor = color
        disabledBackgroundColor = disabled
        updateRenderedState()
    }

    func applyVisibleTitleFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) {
        applyScaledTitleFont(size: size, weight: weight, textStyle: textStyle)
    }

    private func configure() {
        titleLabel?.numberOfLines = 2
        titleLabel?.textAlignment = .center
        titleLabel?.lineBreakMode = .byWordWrapping

        updateRenderedState()
    }

    private func updateRenderedState() {
        let resolvedTitleColor = isEnabled ? normalTitleColor : disabledTitleColor
        setTitleColor(resolvedTitleColor, for: .normal)
        setTitleColor(resolvedTitleColor, for: .highlighted)
        setTitleColor(resolvedTitleColor, for: .selected)
        setTitleColor(disabledTitleColor, for: .disabled)
        backgroundColor = isEnabled ? normalBackgroundColor : (disabledBackgroundColor ?? normalBackgroundColor)
        alpha = isEnabled ? (isHighlighted ? 0.92 : 1) : 0.72
    }
}
