//
//  PaymentsViewController.swift
//  BillEasy
//

import UIKit

final class PaymentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
    private struct PayableEntry {
        enum ActionType {
            case pay
            case regularize
            case reviewTerms
        }

        let debtID: String
        let contractID: String?
        let firstInstallmentID: String?
        let title: String
        let dueDate: String
        let installmentSummary: String?
        let amountCaption: String
        let amount: String
        let amountValue: Decimal
        let status: String
        let statusColor: UIColor
        let statusTextColor: UIColor
        let warning: String?
        let action: String
        let actionColor: UIColor
        let actionType: ActionType
    }

    private struct PaymentsMetrics {
        let totalToPay: Decimal
        let overdueCount: Int
        let paidCount: Int
        let reputationPoints: Int
        let reputationLevel: String
        let progress: Float

        static let empty = PaymentsMetrics(
            totalToPay: .zero,
            overdueCount: 0,
            paidCount: 0,
            reputationPoints: 0,
            reputationLevel: "Sem nível",
            progress: 0
        )
    }

    private enum Layout {
        static let stackSpacing: CGFloat = 14
        static let horizontalMargin: CGFloat = 14
        static let topMargin: CGFloat = 16
        static let bottomMargin: CGFloat = 28
        static let sectionTitleSize: CGFloat = 30
        static let cardCornerRadius: CGFloat = 16
        static let contentInset: CGFloat = 16
    }

    private enum Row {
        case sectionTitle(String)
        case alert
        case reputation
        case achievements
        case total
        case actions
        case initialLoading
        case empty
        case detailLoading
        case payable(PayableEntry)
        case pageLoading
    }

    private let session: AuthSession
    private let dataStore: LocalAppDataStore
    private let portalService: PortalDataService
    private let actionsService: PortalActionsService

    private let tableView = UITableView(frame: .zero, style: .plain)

    private var rows: [Row] = []
    private var entries: [PayableEntry] = []
    private var metrics: PaymentsMetrics = .empty
    private var remoteDebts: [DebtItem] = []
    private var remoteDebtDetails: [String: PortalDebtDetail] = [:]
    private var remoteDetailRequestsInFlight: Set<String> = []
    private var remoteCurrentPage = 0
    private var remoteHasMorePages = true
    private var remoteIsLoadingPage = false
    private var remotePageLoadStartedAt: Date?
    private var remoteRequestGeneration = 0
    private let remotePageSize = 20
    private let remotePageLoadTimeout: TimeInterval = 45
    private var renderDebounceWorkItem: DispatchWorkItem?
    private var lastLoadedAt: Date?
    private let reloadTimeToLive: TimeInterval = 30

    init(
        session: AuthSession,
        dataStore: LocalAppDataStore,
        portalService: PortalDataService = PortalDataService(),
        actionsService: PortalActionsService = PortalActionsService()
    ) {
        self.session = session
        self.dataStore = dataStore
        self.portalService = portalService
        self.actionsService = actionsService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContainer()
        setupLifecycleObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if shouldReloadDataOnAppear {
            reloadData()
        } else {
            renderContent()
        }
    }

    deinit {
        renderDebounceWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupContainer() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 220
        tableView.contentInset = UIEdgeInsets(top: Layout.topMargin, left: 0, bottom: Layout.bottomMargin, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.register(HostedViewTableViewCell.self, forCellReuseIdentifier: HostedViewTableViewCell.reuseIdentifier)

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private var shouldReloadDataOnAppear: Bool {
        if recoverStaleRemoteLoadIfNeeded() {
            return true
        }
        guard !remoteIsLoadingPage else { return false }
        guard let lastLoadedAt else { return true }
        return Date().timeIntervalSince(lastLoadedAt) > reloadTimeToLive
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        guard isViewLoaded, view.window != nil else { return }
        if rows.isEmpty || shouldReloadDataOnAppear {
            reloadData()
        } else {
            renderContent()
        }
    }

    private func reloadData() {
        lastLoadedAt = Date()
        if portalService.isRemoteMode {
            resetRemotePagination()
            applyDebtSnapshot([])
            renderContent()
            refreshRemoteSnapshotIfNeeded()
        } else {
            applyDebtSnapshot(dataStore.fetchDebts().filter { $0.status != .cancelada })
            renderContent()
        }
    }

    private func applyDebtSnapshot(_ debts: [DebtItem], totalToPayOverride: Decimal? = nil) {
        entries = debts.map { debt in
            let status = statusPresentation(for: debt.status)
            let detail = remoteDebtDetails[debt.id]
            let resolvedTitle = detail.map { detail in
                let trimmed = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? nil
            return PayableEntry(
                debtID: debt.id,
                contractID: detail?.contractID ?? debt.contractID,
                firstInstallmentID: debt.firstInstallmentID,
                title: resolvedTitle ?? (debt.titulo.isEmpty ? "Conta sem título" : debt.titulo),
                dueDate: "Vence em \(detail?.dueDateDisplay ?? Formatters.shortDate.string(from: debt.vencimento))",
                installmentSummary: detail?.installmentSummary,
                amountCaption: amountCaption(for: detail),
                amount: detail?.updatedAmountText ?? normalizedCurrency(debt.valor.asCurrency),
                amountValue: detail?.updatedAmount ?? debt.valor,
                status: status.text,
                statusColor: status.background,
                statusTextColor: status.textColor,
                warning: payableWarning(for: detail, fallback: status.warning),
                action: status.actionTitle,
                actionColor: status.actionColor,
                actionType: status.actionType
            )
        }

        metrics = metricsForDebts(debts, totalToPayOverride: totalToPayOverride)
    }

    private func refreshRemoteSnapshotIfNeeded() {
        guard portalService.isRemoteMode else { return }
        guard session.canAccessDebtorWorkspace else { return }
        loadPayablePage(reset: true)
    }

    private func resetRemotePagination() {
        renderDebounceWorkItem?.cancel()
        renderDebounceWorkItem = nil
        remoteDebts = []
        remoteDebtDetails = [:]
        remoteDetailRequestsInFlight = []
        remoteCurrentPage = 0
        remoteHasMorePages = true
        remoteIsLoadingPage = false
        remotePageLoadStartedAt = nil
        remoteRequestGeneration += 1
    }

    private func loadPayablePage(reset: Bool = false) {
        guard portalService.isRemoteMode else { return }
        guard session.canAccessDebtorWorkspace else { return }
        guard remoteIsLoadingPage == false else { return }
        guard reset || remoteHasMorePages else { return }

        let pageToLoad = reset ? 0 : remoteCurrentPage + 1
        remoteIsLoadingPage = true
        remotePageLoadStartedAt = Date()
        let requestGeneration = remoteRequestGeneration
        renderContent()

        Task { [weak self] in
            guard let self else { return }

            do {
                let page = try await self.portalService.fetchPayableDebtPage(page: pageToLoad, size: self.remotePageSize)
                _ = await MainActor.run {
                    guard self.remoteRequestGeneration == requestGeneration else { return }
                    guard self.session.userID.isEmpty == false else { return }
                    if reset {
                        self.remoteDebts = page.debts
                    } else {
                        self.remoteDebts = self.mergeRemoteDebts(self.remoteDebts, with: page.debts)
                    }
                    self.remoteCurrentPage = page.pageNumber
                    self.remoteHasMorePages = page.isLastPage == false
                    self.remoteIsLoadingPage = false
                    self.remotePageLoadStartedAt = nil
                    self.applyDebtSnapshot(self.remoteDebts)
                    self.renderContent()
                    self.preloadDebtDetails(for: page.debts)
                }
            } catch {
                _ = await MainActor.run {
                    guard self.remoteRequestGeneration == requestGeneration else { return }
                    self.remoteIsLoadingPage = false
                    self.remotePageLoadStartedAt = nil
                    self.renderContent()
                }
            }
        }
    }

    @discardableResult
    private func recoverStaleRemoteLoadIfNeeded() -> Bool {
        guard portalService.isRemoteMode, remoteIsLoadingPage else { return false }
        if let remotePageLoadStartedAt,
           Date().timeIntervalSince(remotePageLoadStartedAt) <= remotePageLoadTimeout {
            return false
        }

        remoteIsLoadingPage = false
        remotePageLoadStartedAt = nil
        remoteRequestGeneration += 1
        return true
    }

    private func mergeRemoteDebts(_ current: [DebtItem], with nextPage: [DebtItem]) -> [DebtItem] {
        let currentIDs = Set(current.map(\.id))
        return current + nextPage.filter { currentIDs.contains($0.id) == false }
    }

    private func preloadDebtDetails(for debts: [DebtItem]) {
        guard actionsService.isRemoteMode else { return }

        for debt in debts {
            guard remoteDebtDetails[debt.id] == nil else { continue }
            guard remoteDetailRequestsInFlight.contains(debt.id) == false else { continue }
            remoteDetailRequestsInFlight.insert(debt.id)

            Task { [weak self] in
                guard let self else { return }

                do {
                    let detail = try await self.actionsService.fetchDebtDetail(debtID: debt.id)
                    _ = await MainActor.run {
                        self.remoteDetailRequestsInFlight.remove(debt.id)
                        self.remoteDebtDetails[debt.id] = detail
                        self.scheduleDebounceRender()
                    }
                } catch {
                    _ = await MainActor.run {
                        self.remoteDetailRequestsInFlight.remove(debt.id)
                    }
                }
            }
        }
    }

    private func scheduleDebounceRender() {
        renderDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.applyDebtSnapshot(self.remoteDebts)
            self.renderContent()
        }
        renderDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func amountCaption(for detail: PortalDebtDetail?) -> String {
        guard let detail else { return "VALOR À VISTA" }
        if let installmentTotal = detail.installmentTotal, installmentTotal > 1, detail.updatedAmount <= detail.principalAmount {
            return "VALOR DA PARCELA"
        }
        return detail.updatedAmount > detail.principalAmount ? "VALOR ATUALIZADO" : "VALOR À VISTA"
    }

    private func payableWarning(for detail: PortalDebtDetail?, fallback: String?) -> String? {
        guard let detail else { return fallback }
        guard detail.isOverdue else { return fallback }
        return "\(detail.overdueDays) dias de atraso. Multa e juros aplicados."
    }

    private func renderContent() {
        rows = makeRows()
        tableView.reloadData()
    }

    private func makeRows() -> [Row] {
        var nextRows: [Row] = [.sectionTitle("Quero Pagar")]
        if metrics.overdueCount > 0 {
            nextRows.append(.alert)
        }

        nextRows.append(contentsOf: [
            .reputation,
            .achievements,
            .total,
            .actions,
            .sectionTitle("Suas Contas")
        ])

        if isShowingInitialRemoteLoading {
            nextRows.append(.initialLoading)
            return nextRows
        }

        if entries.isEmpty {
            nextRows.append(.empty)
            return nextRows
        }

        if remoteDetailRequestsInFlight.isEmpty == false {
            nextRows.append(.detailLoading)
        }

        nextRows.append(contentsOf: entries.map(Row.payable))

        if remoteIsLoadingPage {
            nextRows.append(.pageLoading)
        }

        return nextRows
    }

    private func makeLoadingFooter(text: String) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 10
        container.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        container.isLayoutMarginsRelativeArrangement = true

        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        indicator.color = UIColor(hex: "#688097")

        let label = UILabel()
        label.text = text
        label.textColor = UIColor(hex: "#688097")
        label.applyScaledFont(size: 14, weight: .medium, textStyle: .footnote)

        container.addArrangedSubview(indicator)
        container.addArrangedSubview(label)
        return container
    }

    private func makeInitialLoadingCard() -> UIView {
        BrandCardFactory.makeLoadingStateCard(
            title: "Carregando contas",
            subtitle: "Estou buscando sua lista inicial e já vou completar cada card com valor atualizado, atraso e parcelamento do backend."
        )
    }

    private var isShowingInitialRemoteLoading: Bool {
        portalService.isRemoteMode && remoteIsLoadingPage && remoteDebts.isEmpty
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor(hex: "#252E3A")
        label.applyScaledFont(size: Layout.sectionTitleSize, weight: .bold, textStyle: .largeTitle)
        label.accessibilityTraits.insert(.header)
        return label
    }

    private func makeSurfaceCard(
        background: UIColor = UIColor(hex: "#FAFCFF"),
        border: UIColor = UIColor(hex: "#D7DEE8"),
        cornerRadius: CGFloat = Layout.cardCornerRadius
    ) -> UIView {
        ThemedSurfaceView(
            backgroundColor: background,
            borderColor: border,
            cornerRadius: cornerRadius
        )
    }

    private func makeAlertCard() -> UIView {
        let card = makeSurfaceCard(background: UIColor(hex: "#FFF2F0"), border: UIColor(hex: "#F4A5A0"))

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = UIColor(hex: "#FFE1DE")
        iconContainer.layer.cornerRadius = 18
        iconContainer.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#EF4444")

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Atenção: Atraso Detectado"
        title.textColor = UIColor(hex: "#DC2626")
        title.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)

        let overdueText = metrics.overdueCount == 1 ? "1 pendência vencida" : "\(metrics.overdueCount) pendências vencidas"

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.text = "Você tem \(overdueText).\nEvite multa e inclusão no SERASA\nregularizando em até 5 dias."
        body.numberOfLines = 0
        body.textColor = UIColor(hex: "#EF4444")
        body.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        card.addSubview(iconContainer)
        iconContainer.addSubview(icon)
        card.addSubview(title)
        card.addSubview(body)
        card.isAccessibilityElement = true
        card.accessibilityLabel = "Atenção, atraso detectado"
        card.accessibilityValue = body.text

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),

            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconContainer.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36),

            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            body.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12)
        ])

        return card
    }

    private func makeReputationCard() -> UIView {
        let card = makeSurfaceCard(background: UIColor(hex: "#F7FAFD"))

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = UIColor(hex: "#D9E9F6")
        iconContainer.layer.cornerRadius = 18
        iconContainer.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "star"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#2E87C8")

        iconContainer.addSubview(icon)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "SUA REPUTAÇÃO"
        title.textColor = UIColor(hex: "#7D8EA5")
        title.applyScaledFont(size: 14, weight: .bold, textStyle: .caption1)

        let level = UILabel()
        level.translatesAutoresizingMaskIntoConstraints = false
        level.text = metrics.reputationLevel
        level.textColor = UIColor(hex: "#283344")
        level.applyScaledFont(size: 28, weight: .bold, textStyle: .title2)
        level.adjustsFontSizeToFitWidth = true
        level.minimumScaleFactor = 0.7

        let score = UILabel()
        score.translatesAutoresizingMaskIntoConstraints = false
        score.text = "\(metrics.reputationPoints)\npontos"
        score.textAlignment = .right
        score.numberOfLines = 2
        score.textColor = UIColor(hex: "#2F3946")
        score.applyScaledFont(size: 16, weight: .semibold, textStyle: .subheadline)

        card.addSubview(iconContainer)
        card.addSubview(title)
        card.addSubview(level)
        card.addSubview(score)
        card.isAccessibilityElement = true
        card.accessibilityLabel = "Reputação"
        card.accessibilityValue = "\(metrics.reputationLevel), \(metrics.reputationPoints) pontos."

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),

            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            iconContainer.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36),

            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),

            level.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            level.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            level.trailingAnchor.constraint(lessThanOrEqualTo: score.leadingAnchor, constant: -10),
            level.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),

            score.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            score.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        return card
    }

    private func makeAchievementsCard() -> UIView {
        let card = makeSurfaceCard(background: UIColor(hex: "#F7FAFD"))

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "🏆  Minhas Conquistas"
        title.textColor = UIColor(hex: "#283344")
        title.applyScaledFont(size: 16, weight: .bold, textStyle: .headline)
        title.numberOfLines = 1

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = entries.isEmpty ? "Conquistas serão liberadas após os primeiros pagamentos." : "Ganhe benefícios pagando em dia!"
        subtitle.textColor = UIColor(hex: "#7A8B9F")
        subtitle.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)
        subtitle.numberOfLines = 0

        let level = UILabel()
        level.translatesAutoresizingMaskIntoConstraints = false
        level.text = "NÍVEL\n\(metrics.reputationLevel)"
        level.numberOfLines = 2
        level.textAlignment = .right
        level.textColor = UIColor(hex: "#2E87C8")
        level.applyScaledFont(size: 13, weight: .bold, textStyle: .caption1)

        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progress = metrics.progress
        progress.trackTintColor = UIColor(hex: "#E3E9F1")
        progress.progressTintColor = UIColor(hex: "#2D7EA3")

        let badges = UIStackView()
        badges.translatesAutoresizingMaskIntoConstraints = false
        badges.axis = .horizontal
        badges.spacing = 8
        badges.distribution = .fillEqually

        badges.addArrangedSubview(makeBadgeCard(icon: "star", title: "Pagador Pontual", subtitle: metrics.paidCount > 0 ? "desbloqueado" : "bloqueado", disabled: metrics.paidCount == 0))
        badges.addArrangedSubview(makeBadgeCard(icon: "trophy", title: "Conciliador", subtitle: metrics.overdueCount > 0 ? "em progresso" : "bloqueado", disabled: metrics.overdueCount == 0))
        badges.addArrangedSubview(makeBadgeCard(icon: "lock", title: "Mestre da\nEconomia", subtitle: "bloqueado", disabled: true))

        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(level)
        card.addSubview(progress)
        card.addSubview(badges)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            title.trailingAnchor.constraint(lessThanOrEqualTo: level.leadingAnchor, constant: -12),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            subtitle.trailingAnchor.constraint(equalTo: level.leadingAnchor, constant: -12),

            level.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            level.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),

            progress.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            progress.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            progress.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),

            badges.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 12),
            badges.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            badges.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            badges.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            badges.heightAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])

        return card
    }

    private func makeBadgeCard(icon: String, title: String, subtitle: String, disabled: Bool = false) -> UIView {
        let card = makeSurfaceCard(
            background: disabled ? UIColor(hex: "#EEF2F7") : UIColor(hex: "#E8F4FF"),
            border: UIColor(hex: "#C8D6E8"),
            cornerRadius: 10
        )

        let image = UIImageView(image: UIImage(systemName: icon))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.tintColor = disabled ? UIColor(hex: "#AAB6C6") : UIColor(hex: "#2E87C8")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = disabled ? UIColor(hex: "#94A3B8") : UIColor(hex: "#2B3747")
        titleLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = disabled ? UIColor(hex: "#94A3B8") : UIColor(hex: "#1580C4")
        subtitleLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.textAlignment = .center

        card.addSubview(image)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            image.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4)
        ])

        return card
    }

    private func makeTotalCard() -> UIView {
        let card = GradientCardView(
            colors: [
                UIColor(hex: "#B63C3C"),
                UIColor(hex: "#8B1018")
            ],
            cornerRadius: 18
        )

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "TOTAL A PAGAR"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.9)
        subtitle.applyScaledFont(size: 16, weight: .bold, textStyle: .headline)

        let value = UILabel()
        value.text = normalizedCurrency(metrics.totalToPay.asCurrency)
        value.textColor = .white
        value.applyScaledFont(size: 54, weight: .bold, textStyle: .largeTitle)
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7

        let chips = UIStackView()
        chips.axis = .horizontal
        chips.spacing = 8
        chips.alignment = .leading
        chips.addArrangedSubview(makeChip(text: "\(metrics.overdueCount) Atrasados", icon: "clock"))
        chips.addArrangedSubview(makeChip(text: "\(metrics.paidCount) Pagos", icon: "checkmark.circle"))

        content.addArrangedSubview(subtitle)
        content.addArrangedSubview(value)
        content.addArrangedSubview(chips)
        card.isAccessibilityElement = true
        card.accessibilityLabel = "Resumo de pagamentos"
        card.accessibilityValue = "Total a pagar \(normalizedCurrency(metrics.totalToPay.asCurrency)), \(metrics.overdueCount) atrasados e \(metrics.paidCount) pagos."

        card.addSubview(content)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        return card
    }

    private func makeChip(text: String, icon: String) -> UIView {
        let chip = UIView()
        chip.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        chip.layer.cornerRadius = 16

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.applyScaledFont(size: 16, weight: .semibold, textStyle: .subheadline)
        label.translatesAutoresizingMaskIntoConstraints = false

        chip.addSubview(iconView)
        chip.addSubview(label)

        NSLayoutConstraint.activate([
            chip.heightAnchor.constraint(equalToConstant: 32),
            iconView.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: chip.centerYAnchor)
        ])

        return chip
    }

    private func makeActionsCard() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        row.addArrangedSubview(makeActionButton(title: "Ver Agenda", icon: "calendar") { [weak self] in
            (self?.parent as? MainTabBarController)?.navigateToAgenda()
        })
        row.addArrangedSubview(makeActionButton(title: "Negociar Dívida", icon: "bubble.left") { [weak self] in
            guard let self else { return }
            guard let target = self.entries.first(where: { $0.status != "Pago" }) ?? self.entries.first else {
                self.showSimpleToast("Nenhuma dívida cadastrada para negociar.")
                return
            }
            self.presentConciliationPopup(disputeTitle: target.title)
        })

        return row
    }

    private func makeActionButton(title: String, icon: String, action: @escaping () -> Void) -> UIView {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor(hex: "#F8FAFC")
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        button.accessibilityLabel = title
        button.accessibilityHint = "Abre a seção \(title.lowercased())."
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)

        let image = UIImageView(image: UIImage(systemName: icon))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.tintColor = UIColor(hex: "#1A2A3E")

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = UIColor(hex: "#283344")
        label.applyScaledFont(size: 16, weight: .semibold, textStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0

        button.addSubview(image)
        button.addSubview(label)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),

            image.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            image.topAnchor.constraint(equalTo: button.topAnchor, constant: 14),
            image.widthAnchor.constraint(equalToConstant: 24),
            image.heightAnchor.constraint(equalToConstant: 24),

            label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -12)
        ])

        return button
    }

    private func makeEmptyStateCard() -> UIView {
        BrandCardFactory.makeEmptyStateCard(
            title: "Nenhuma conta lançada",
            subtitle: "Quando existirem contratos ou parcelas para pagamento, elas aparecerão aqui com status, valor e próximos passos.",
            iconSystemName: "wallet.pass"
        )
    }

    private func makePayableCard(_ entry: PayableEntry) -> UIView {
        let card = makeSurfaceCard()

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = entry.title
        title.textColor = UIColor(hex: "#283344")
        title.applyScaledFont(size: 20, weight: .bold, textStyle: .title3)

        let due = UILabel()
        due.translatesAutoresizingMaskIntoConstraints = false
        due.text = entry.dueDate
        due.textColor = UIColor(hex: "#7A8B9F")
        due.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)

        let status = UILabel()
        status.translatesAutoresizingMaskIntoConstraints = false
        status.text = entry.status
        status.textColor = entry.statusTextColor
        status.applyScaledFont(size: 14, weight: .bold, textStyle: .caption1)
        status.textAlignment = .center
        status.backgroundColor = entry.statusColor
        status.layer.cornerRadius = 13
        status.layer.cornerCurve = .continuous
        status.layer.masksToBounds = true

        let amountLabel = UILabel()
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.text = entry.amountCaption
        amountLabel.textColor = UIColor(hex: "#7A8B9F")
        amountLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        let amount = UILabel()
        amount.translatesAutoresizingMaskIntoConstraints = false
        amount.text = entry.amount
        amount.textColor = UIColor(hex: "#283344")
        amount.applyScaledFont(size: 24, weight: .bold, textStyle: .title2)

        card.addSubview(title)
        card.addSubview(due)
        card.addSubview(status)

        var lastAnchor = due.bottomAnchor

        if let installmentSummary = entry.installmentSummary {
            let installmentBadge = makeInstallmentBadge(text: installmentSummary)
            installmentBadge.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(installmentBadge)
            NSLayoutConstraint.activate([
                installmentBadge.topAnchor.constraint(equalTo: due.bottomAnchor, constant: 10),
                installmentBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset)
            ])
            lastAnchor = installmentBadge.bottomAnchor
        }

        if let warning = entry.warning {
            let warningView = makeInfoPill(text: warning, background: UIColor(hex: "#FFF0F0"), border: UIColor(hex: "#F6C6C6"), textColor: UIColor(hex: "#F04A4A"), icon: "exclamationmark.triangle")
            warningView.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(warningView)
            NSLayoutConstraint.activate([
                warningView.topAnchor.constraint(equalTo: lastAnchor, constant: 10),
                warningView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                warningView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                warningView.heightAnchor.constraint(equalToConstant: 40)
            ])
            lastAnchor = warningView.bottomAnchor
        }

        card.addSubview(amountLabel)
        card.addSubview(amount)

        let actions = makeActionRow(for: entry)
        actions.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(actions)
        card.shouldGroupAccessibilityChildren = true

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            title.trailingAnchor.constraint(lessThanOrEqualTo: status.leadingAnchor, constant: -8),

            status.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            status.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            status.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            status.heightAnchor.constraint(equalToConstant: 26),

            due.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            due.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            due.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),

            amountLabel.topAnchor.constraint(equalTo: lastAnchor, constant: 12),
            amountLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),

            amount.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 2),
            amount.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),

            actions.topAnchor.constraint(equalTo: amount.bottomAnchor, constant: 12),
            actions.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            actions.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func makeInstallmentBadge(text: String) -> UIView {
        let label = InsetLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text.uppercased()
        label.textColor = UIColor(hex: "#1D75B3")
        label.backgroundColor = UIColor(hex: "#E8F2FA")
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.applyScaledFont(size: 11, weight: .bold, textStyle: .caption1)
        label.contentInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        return label
    }

    private func makeActionRow(for entry: PayableEntry) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        row.addArrangedSubview(makeIconSquare(systemName: "doc.text") { [weak self] in
            self?.presentDebtorContractPopup(for: entry)
        })
        row.addArrangedSubview(makeIconSquare(systemName: "bubble.left") { [weak self] in
            self?.presentConciliationPopup(disputeTitle: entry.title)
        })
        row.addArrangedSubview(makePrimaryButton(title: entry.action, color: entry.actionColor) { [weak self] in
            self?.handlePrimaryAction(for: entry)
        })

        return row
    }

    private func makeInfoPill(text: String, background: UIColor, border: UIColor, textColor: UIColor, icon: String) -> UIView {
        let card = UIView()
        card.backgroundColor = background
        card.layer.cornerRadius = 8
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor

        let image = UIImageView(image: UIImage(systemName: icon))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.tintColor = textColor

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = textColor
        label.applyScaledFont(size: 14, weight: .semibold, textStyle: .footnote)

        card.addSubview(image)
        card.addSubview(label)

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            image.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        return card
    }

    private func makeIconSquare(systemName: String, action: @escaping () -> Void) -> UIView {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D2DBE7").cgColor
        button.applyStableStateColors(
            normalBackground: UIColor(hex: "#F2F6FA"),
            normalForeground: UIColor(hex: "#7A8B9F")
        )
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.accessibilityHint = "Executa uma ação secundária desta conta."
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 38)
        ])
        return button
    }

    private func makePrimaryButton(title: String, color: UIColor, action: @escaping () -> Void) -> UIView {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.applyScaledTitleFont(size: 15, weight: .bold, textStyle: .headline)
        button.layer.cornerRadius = 19
        button.layer.cornerCurve = .continuous
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 7
        button.applyStableStateColors(
            normalBackground: color,
            normalForeground: .white
        )
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.accessibilityHint = "Executa a ação principal desta conta."
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 38),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])
        return button
    }

    private func handlePrimaryAction(for entry: PayableEntry) {
        switch entry.actionType {
        case .pay:
            presentPaymentMethodPopup(for: entry)
        case .regularize, .reviewTerms:
            presentDebtorContractPopup(for: entry)
        }
    }

    private func presentPaymentMethodPopup(for entry: PayableEntry) {
        let pricing = discountedPricing(from: entry.amountValue)
        let popup = PaymentMethodPopupViewController(
            invoiceTitle: entry.title,
            originalPriceText: entry.amount,
            discountedPriceText: pricing.discountedPrice,
            discountBadgeText: "-6% OFF",
            savingsText: "Você economiza \(pricing.savings)!",
            availableMethods: PortalPaymentMethodOption.fallbackOptions
        )
        popup.onSelectMethod = { [weak self, weak popup] method in
            guard let self, let popup else { return }
            self.makePaymentSelectionHandler(
                popup: popup,
                entry: entry,
                method: method
            )()
        }

        present(popup, animated: true)
        hydratePaymentMethodPopup(popup, entry: entry)
    }

    private func makePaymentSelectionHandler(
        popup: PaymentMethodPopupViewController,
        entry: PayableEntry,
        method: PortalPaymentMethod
    ) -> () -> Void {
        { [weak self, weak popup] in
            guard let self else { return }

            popup?.dismiss(animated: true) {
                if self.actionsService.isRemoteMode {
                    self.submitRemotePayment(for: entry, method: method)
                } else {
                    self.dataStore.addPayment(reference: entry.title, method: method.displayName, amount: entry.amountValue)
                    self.showSimpleToast(self.localPaymentSuccessMessage(for: method), style: .success)
                }
            }
        }
    }

    private func presentDebtorContractPopup(for entry: PayableEntry) {
        let contractText = debtorContractText(for: entry)
        var resolvedContractID = entry.contractID
        let popup = ContractDigitalPopupViewController(
            mode: .debtorActions,
            contractTextOverride: contractText
        )
        hydrateDebtorContractPopup(
            popup,
            entry: entry,
            fallbackText: contractText
        ) { contractID in
            resolvedContractID = contractID ?? resolvedContractID
        }
        popup.onDownload = { [weak self, weak popup] in
            self?.downloadContractIfPossible(
                contractID: resolvedContractID,
                fallbackText: popup?.currentContractText ?? contractText,
                title: entry.title,
                presenter: popup
            )
        }
        popup.onSignAsDebtor = { [weak self, weak popup] in
            popup?.dismiss(animated: true) {
                self?.presentGovBrDebtorPopup(
                    entry: entry,
                    contractText: popup?.currentContractText ?? contractText,
                    contractID: resolvedContractID
                )
            }
        }
        present(popup, animated: true)
    }

    private func presentGovBrDebtorPopup(entry: PayableEntry, contractText: String, contractID: String?) {
        let popup = ContractDigitalPopupViewController(
            mode: .govBrDebtor,
            contractTextOverride: contractText
        )
        popup.onDraw = { [weak self] in
            self?.signDebtorContract(contractID: contractID, signatureType: .physical, popup: popup)
        }
        popup.onGovBr = { [weak self, weak popup] in
            guard let popup else { return }
            self?.signDebtorContract(contractID: contractID, signatureType: .govBr, popup: popup)
        }
        present(popup, animated: true)
    }

    private func presentConciliationPopup(disputeTitle: String) {
        let popup = ConciliationPopupViewController(disputeTitle: disputeTitle)
        present(popup, animated: true)
    }

    private func discountedPricing(from amount: Decimal) -> (discountedPrice: String, savings: String) {
        let originalValue = NSDecimalNumber(decimal: amount).doubleValue
        guard originalValue > 0 else {
            return ("R$ 0,00", "R$ 0,00")
        }

        let discounted = originalValue * 0.94
        let savings = originalValue - discounted
        return (formatCurrency(discounted), formatCurrency(savings))
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatted = Formatters.currency.string(from: NSNumber(value: value)) ?? "R$ 0,00"
        return formatted.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func metricsForDebts(_ debts: [DebtItem], totalToPayOverride: Decimal? = nil) -> PaymentsMetrics {
        let payableStatuses: [DebtStatus] = [.pendente, .vencida, .negociada, .parcial]
        let payableDebts = debts.filter { payableStatuses.contains($0.status) }

        let computedTotalToPay = payableDebts.reduce(Decimal.zero) { partialResult, item in
            partialResult + item.valor
        }
        let totalToPay = totalToPayOverride ?? computedTotalToPay
        let overdueCount = debts.filter { $0.status == .vencida }.count
        let paidCount = debts.filter { $0.status == .paga }.count
        let totalRelevant = max(1, debts.count)
        let progress = min(1.0, max(0.0, Float(paidCount) / Float(totalRelevant)))

        let rawScore = max(0, (paidCount * 150) + (debts.count * 15) - (overdueCount * 90))

        return PaymentsMetrics(
            totalToPay: totalToPay,
            overdueCount: overdueCount,
            paidCount: paidCount,
            reputationPoints: rawScore,
            reputationLevel: reputationLevel(for: rawScore, hasDebts: !debts.isEmpty),
            progress: progress
        )
    }

    private func reputationLevel(for points: Int, hasDebts: Bool) -> String {
        guard hasDebts else { return "Sem nível" }
        switch points {
        case 900...: return "Nível Diamante"
        case 650...: return "Nível Ouro"
        case 350...: return "Nível Prata"
        default: return "Nível Inicial"
        }
    }

    private func statusPresentation(for status: DebtStatus) -> (
        text: String,
        background: UIColor,
        textColor: UIColor,
        warning: String?,
        actionTitle: String,
        actionColor: UIColor,
        actionType: PayableEntry.ActionType
    ) {
        switch status {
        case .pendente:
            return (
                "Em Dia",
                UIColor(hex: "#DCECF8"),
                UIColor(hex: "#2886C4"),
                nil,
                "Pagar",
                UIColor(hex: "#2CBF85"),
                .pay
            )
        case .vencida:
            return (
                "Vencido",
                UIColor(hex: "#F8D7DA"),
                UIColor(hex: "#D75C5C"),
                "Cobrança vencida. Multa e juros podem ser aplicados.",
                "Regularizar",
                UIColor(hex: "#1D7C9D"),
                .regularize
            )
        case .negociada:
            return (
                "Resolvendo",
                UIColor(hex: "#DEE6FF"),
                UIColor(hex: "#3560D8"),
                nil,
                "Análise",
                UIColor(hex: "#EAB308"),
                .reviewTerms
            )
        case .parcial:
            return (
                "Parcial",
                UIColor(hex: "#FFF1CC"),
                UIColor(hex: "#C78615"),
                "Pagamento parcial identificado. Você ainda pode quitar o saldo restante.",
                "Pagar",
                UIColor(hex: "#2CBF85"),
                .pay
            )
        case .paga:
            return (
                "Pago",
                UIColor(hex: "#DCFCE7"),
                UIColor(hex: "#169C57"),
                nil,
                "Recibo",
                UIColor(hex: "#64748B"),
                .reviewTerms
            )
        case .cancelada:
            return (
                "Cancelado",
                UIColor(hex: "#E5E7EB"),
                UIColor(hex: "#6B7280"),
                nil,
                "Detalhes",
                UIColor(hex: "#64748B"),
                .reviewTerms
            )
        }
    }

    private func normalizedCurrency(_ value: String) -> String {
        Formatters.normalizeCurrencyDisplay(value)
    }

    private func debtorContractText(for entry: PayableEntry) -> String {
        return """
        INSTRUMENTO PARTICULAR DE CONFISSÃO DE DÍVIDA E OUTRAS AVENÇAS

        Pelo presente INSTRUMENTO PARTICULAR DE CONFISSÃO DE DÍVIDA, as partes reconhecem o título "\(entry.title)" com vencimento em \(entry.dueDate.replacingOccurrences(of: "Vence em ", with: "")).

        VALOR RECONHECIDO
        \(entry.amount)

        CONDIÇÕES GERAIS
        O pagamento será realizado conforme acordo entre credor e devedor, podendo incluir atualização monetária, multa e juros em caso de atraso.

        Este documento foi gerado eletronicamente via BillEasy.ia para validação e assinatura digital.
        """
    }

    private func submitRemotePayment(for entry: PayableEntry, method: PortalPaymentMethod) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let receipt = try await self.actionsService.createPayment(
                    debtID: entry.debtID,
                    preferredInstallmentID: entry.firstInstallmentID,
                    method: method
                )

                _ = await MainActor.run {
                    self.showSimpleToast(self.remotePaymentSuccessMessage(for: receipt), style: .success)
                    self.refreshRemoteSnapshotIfNeeded()
                }
            } catch {
                _ = await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func remotePaymentSuccessMessage(for receipt: PortalPaymentReceipt) -> String {
        if receipt.method == .pix, receipt.pixQRCode?.isEmpty == false {
            return "Pagamento Pix criado no servidor. O QR Code já está disponível."
        }

        if receipt.method == .boleto, receipt.digitableLine?.isEmpty == false {
            return "Boleto gerado no servidor. A linha digitável já está disponível."
        }

        return "Pagamento via \(receipt.method.displayName) registrado com sucesso."
    }

    private func localPaymentSuccessMessage(for method: PortalPaymentMethod) -> String {
        switch method {
        case .pix:
            return "Pagamento via Pix criado (simulação)."
        case .creditCard:
            return "Pagamento no cartão iniciado (simulação)."
        case .debitCard:
            return "Pagamento no débito iniciado (simulação)."
        case .boleto:
            return "Boleto gerado (simulação)."
        }
    }

    private func hydratePaymentMethodPopup(_ popup: PaymentMethodPopupViewController, entry: PayableEntry) {
        guard actionsService.isRemoteMode else { return }

        Task { [weak self, weak popup] in
            guard let self else { return }

            async let detailTask = self.actionsService.fetchDebtDetail(debtID: entry.debtID)
            async let paymentMethodsTask = self.actionsService.fetchPaymentMethods()

            let detailResult: Result<PortalDebtDetail, Error>
            let methodsResult: Result<[PortalPaymentMethodOption], Error>

            do {
                detailResult = .success(try await detailTask)
            } catch {
                detailResult = .failure(error)
            }

            do {
                methodsResult = .success(try await paymentMethodsTask)
            } catch {
                methodsResult = .failure(error)
            }

            _ = await MainActor.run {
                if case let .success(methods) = methodsResult, methods.isEmpty == false {
                    popup?.updateAvailableMethods(methods)
                }

                switch detailResult {
                case let .success(detail):
                    let pricing = self.discountedPricing(from: detail.updatedAmount)
                    popup?.updateSummary(
                        invoiceTitle: detail.title,
                        originalPriceText: detail.updatedAmountText,
                        discountedPriceText: pricing.discountedPrice,
                        savingsText: "Você economiza \(pricing.savings)!"
                    )
                case .failure:
                    self.showSimpleToast("Não consegui atualizar os dados do pagamento agora. Mantive o resumo local.", style: .info)
                }
            }
        }
    }

    private func hydrateDebtorContractPopup(
        _ popup: ContractDigitalPopupViewController,
        entry: PayableEntry,
        fallbackText: String,
        onResolvedContractID: @escaping (String?) -> Void
    ) {
        guard actionsService.isRemoteMode else { return }

        Task { [weak self, weak popup] in
            guard let self else { return }

            do {
                let debtDetail = try await self.actionsService.fetchDebtDetail(debtID: entry.debtID)
                _ = await MainActor.run {
                    popup?.updateContractText(debtDetail.fallbackContractText)
                    onResolvedContractID(debtDetail.contractID ?? entry.contractID)
                }

                guard let resolvedContractID = debtDetail.contractID ?? entry.contractID else { return }
                let contractDetail = try await self.actionsService.fetchContractDetail(contractID: resolvedContractID)
                _ = await MainActor.run {
                    popup?.updateContractText(contractDetail.contractText)
                }
            } catch {
                _ = await MainActor.run {
                    popup?.updateContractText(fallbackText)
                    self.showSimpleToast("Não consegui carregar o detalhe remoto agora. Mantive o conteúdo de apoio.", style: .info)
                }
            }
        }
    }

    private func downloadContractIfPossible(
        contractID: String?,
        fallbackText: String,
        title: String,
        presenter: UIViewController?
    ) {
        guard actionsService.isRemoteMode else {
            do {
                try presentLocalContractDocumentPreview(
                    contractText: fallbackText,
                    title: title,
                    preferredPresenter: presenter
                )
                showSimpleToast("Abri a visualização local do contrato.", style: .info)
            } catch {
                showSimpleToast("Não consegui gerar a visualização local do contrato.", style: .error)
            }
            return
        }

        guard let contractID else {
            do {
                try presentLocalContractDocumentPreview(
                    contractText: fallbackText,
                    title: title,
                    preferredPresenter: presenter
                )
                showSimpleToast("Essa dívida ainda não possui contrato remoto vinculado. Abri a visualização local do contrato.", style: .info)
            } catch {
                showSimpleToast("Essa dívida ainda não possui contrato remoto vinculado e eu não consegui gerar a visualização local do contrato.", style: .error)
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                let fileURL = try await self.actionsService.downloadContractDocumentWithShortRetry(contractID: contractID)
                _ = await MainActor.run {
                    self.presentContractDocumentPreview(
                        fileURL: fileURL,
                        title: title,
                        preferredPresenter: presenter
                    )
                }
            } catch let remoteError {
                _ = await MainActor.run {
                    do {
                        try self.presentLocalContractDocumentPreview(
                            contractText: fallbackText,
                            title: title,
                            preferredPresenter: presenter
                        )
                        self.showSimpleToast("Não consegui abrir o contrato remoto agora. Abri a visualização local do contrato.", style: .info)
                    } catch {
                        self.showSimpleToast(remoteError.localizedDescription, style: .error)
                    }
                }
            }
        }
    }

    private func signDebtorContract(
        contractID: String?,
        signatureType: PortalContractSignatureType,
        popup: UIViewController
    ) {
        guard actionsService.isRemoteMode else {
            popup.dismiss(animated: true) { [weak self] in
                self?.showSimpleToast("Assinatura iniciada (simulação).")
            }
            return
        }

        guard let contractID else {
            popup.dismiss(animated: true) { [weak self] in
                self?.showSimpleToast("Essa dívida ainda não possui contrato remoto vinculado.", style: .info)
            }
            return
        }

        Task { [weak self, weak popup] in
            guard let self else { return }

            do {
                _ = try await self.actionsService.signContractAsDebtor(
                    contractID: contractID,
                    signatureType: signatureType
                )

                _ = await MainActor.run {
                    popup?.dismiss(animated: true) {
                        self.showSimpleToast("Contrato assinado com sucesso pelo devedor.", style: .success)
                        self.refreshRemoteSnapshotIfNeeded()
                    }
                }
            } catch {
                _ = await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        renderContent()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: HostedViewTableViewCell.reuseIdentifier,
            for: indexPath
        ) as? HostedViewTableViewCell ?? HostedViewTableViewCell(
            style: .default,
            reuseIdentifier: HostedViewTableViewCell.reuseIdentifier
        )
        cell.host(view(for: rows[indexPath.row]), insets: insets(for: rows[indexPath.row]))
        return cell
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        guard portalService.isRemoteMode else { return }
        guard entries.isEmpty == false else { return }
        guard remoteHasMorePages else { return }

        let triggerIndex = max(0, rows.count - 4)
        if indexPaths.contains(where: { $0.row >= triggerIndex }) {
            loadPayablePage()
        }
    }

    private func view(for row: Row) -> UIView {
        switch row {
        case let .sectionTitle(title):
            return makeSectionTitle(title)
        case .alert:
            return makeAlertCard()
        case .reputation:
            return makeReputationCard()
        case .achievements:
            return makeAchievementsCard()
        case .total:
            return makeTotalCard()
        case .actions:
            return makeActionsCard()
        case .initialLoading:
            return makeInitialLoadingCard()
        case .empty:
            return makeEmptyStateCard()
        case .detailLoading:
            return makeLoadingFooter(text: "Atualizando valores, vencimentos e parcelamento...")
        case let .payable(entry):
            return makePayableCard(entry)
        case .pageLoading:
            return makeLoadingFooter(text: "Carregando mais contas...")
        }
    }

    private func insets(for row: Row) -> UIEdgeInsets {
        UIEdgeInsets(
            top: Layout.stackSpacing / 2,
            left: Layout.horizontalMargin,
            bottom: Layout.stackSpacing / 2,
            right: Layout.horizontalMargin
        )
    }
}
