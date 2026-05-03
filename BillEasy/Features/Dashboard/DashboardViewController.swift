//
//  DashboardViewController.swift
//  BillEasy
//

import UIKit
import UniformTypeIdentifiers

final class DashboardViewController: UIViewController, UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
    private struct ReceivableEntry {
        let debtID: String
        let contractID: String?
        let title: String
        let dueDate: String
        let installmentSummary: String?
        let amountCaption: String
        let amount: String
        let status: String
        let statusColor: UIColor
        let statusTextColor: UIColor
        let warning: String?
        let debtorDocument: String?
    }

    private struct ReceivableMetrics {
        let totalOpen: Decimal
        let overdueCount: Int
        let paidCount: Int
        let reputationPoints: Int
        let reputationLevel: String

        static let empty = ReceivableMetrics(
            totalOpen: .zero,
            overdueCount: 0,
            paidCount: 0,
            reputationPoints: 0,
            reputationLevel: "Sem nível"
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
        case total
        case reputation
        case actions
        case initialLoading
        case empty
        case detailLoading
        case receivable(ReceivableEntry)
        case pageLoading
        case spacer
    }

    private let session: AuthSession
    private let dataStore: LocalAppDataStore
    private let portalService: PortalDataService
    private let actionsService: PortalActionsService

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var attachmentDebtTitle: String?

    private var rows: [Row] = []
    private var entries: [ReceivableEntry] = []
    private var metrics: ReceivableMetrics = .empty
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
            applyDebtSnapshot(dataStore.fetchDebts())
            renderContent()
        }
    }

    private func applyDebtSnapshot(_ debts: [DebtItem], totalOpenOverride: Decimal? = nil) {
        entries = debts.map { debt in
            let status = statusPresentation(for: debt.status)
            let detail = remoteDebtDetails[debt.id]
            let resolvedTitle = detail.map { detail in
                let trimmed = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? nil
            return ReceivableEntry(
                debtID: debt.id,
                contractID: detail?.contractID ?? debt.contractID,
                title: resolvedTitle ?? (debt.titulo.isEmpty ? "Cobrança sem título" : debt.titulo),
                dueDate: "Vence em \(detail?.dueDateDisplay ?? Formatters.shortDate.string(from: debt.vencimento))",
                installmentSummary: detail?.installmentSummary,
                amountCaption: amountCaption(for: detail),
                amount: detail?.updatedAmountText ?? normalizedCurrency(debt.valor.asCurrency),
                status: status.text,
                statusColor: status.background,
                statusTextColor: status.textColor,
                warning: receivableWarning(for: detail, fallback: status.warning),
                debtorDocument: detail?.debtorDocument ?? debt.debtorDocument
            )
        }

        metrics = metricsForDebts(debts, totalOpenOverride: totalOpenOverride)
    }

    private func refreshRemoteSnapshotIfNeeded() {
        guard portalService.isRemoteMode else { return }
        guard session.canAccessCreditorWorkspace else { return }
        loadReceivablePage(reset: true)
    }

    /// Reinicia o estado paginado antes de recarregar a lista remota do zero.
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

    private func loadReceivablePage(reset: Bool = false) {
        guard portalService.isRemoteMode else { return }
        guard session.canAccessCreditorWorkspace else { return }
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
                let page = try await self.portalService.fetchReceivableDebtPage(page: pageToLoad, size: self.remotePageSize)
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

    /// Busca o detalhe das cobranças carregadas para enriquecer os cards após o primeiro paint.
    /// Agrupa as re-renderizações com debounce de 150ms para evitar N renderizações para N cobranças.
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

    /// Agenda uma re-renderização com debounce de 150ms — múltiplos detalhes chegando juntos
    /// resultam em um único `renderContent`, não um por detalhe.
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

    private func receivableWarning(for detail: PortalDebtDetail?, fallback: String?) -> String? {
        guard let detail else { return fallback }
        guard detail.isOverdue else { return fallback }
        return "\(detail.overdueDays) dias de atraso. Multa e juros aplicados."
    }

    private func renderContent() {
        rows = makeRows()
        tableView.reloadData()
    }

    private func makeRows() -> [Row] {
        var nextRows: [Row] = [
            .sectionTitle("Quero Receber"),
            .total,
            .reputation,
            .actions,
            .sectionTitle("Suas Cobranças")
        ]
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

        nextRows.append(contentsOf: entries.map(Row.receivable))

        if remoteIsLoadingPage {
            nextRows.append(.pageLoading)
        }

        nextRows.append(.spacer)
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
            title: "Carregando cobranças",
            subtitle: "Estou buscando sua lista inicial e já vou enriquecer cada card com valor atualizado, atraso e parcelamento do backend."
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

    private func makeTotalCard() -> UIView {
        let card = GradientCardView(
            colors: [
                UIColor(hex: "#24874A"),
                UIColor(hex: "#0C602D")
            ],
            cornerRadius: 18
        )
        card.translatesAutoresizingMaskIntoConstraints = false

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "TOTAL A RECEBER"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.8)
        subtitle.applyScaledFont(size: 16, weight: .bold, textStyle: .headline)

        let value = UILabel()
        value.text = normalizedCurrency(metrics.totalOpen.asCurrency)
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
        card.accessibilityLabel = "Resumo de recebimentos"
        card.accessibilityValue = "Total a receber \(normalizedCurrency(metrics.totalOpen.asCurrency)), \(metrics.overdueCount) atrasados e \(metrics.paidCount) pagos."

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
        level.minimumScaleFactor = 0.75

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
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

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

    private func makeActionsCard() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        row.addArrangedSubview(makeActionButton(title: "Ver Agenda", icon: "calendar") { [weak self] in
            (self?.parent as? MainTabBarController)?.navigateToAgenda()
        })
        row.addArrangedSubview(makeActionButton(title: "Localizar Devedor", icon: "magnifyingglass") { [weak self] in
            (self?.parent as? MainTabBarController)?.navigateToDebtorLocator()
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
            title: "Nenhuma cobrança ainda",
            subtitle: "Sua conta está pronta para começar. Cadastre seu primeiro contrato ou cobrança para acompanhar valores, vencimentos e ações aqui.",
            iconSystemName: "tray"
        )
    }

    private func makeReceivableCard(_ entry: ReceivableEntry) -> UIView {
        let card = makeSurfaceCard()

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = entry.title
        title.textColor = UIColor(hex: "#283344")
        title.applyScaledFont(size: 20, weight: .bold, textStyle: .title3)
        title.numberOfLines = 1

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

        let legalCard = makeFormalizeCard(for: entry)
        legalCard.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(legalCard)
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

            legalCard.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 12),
            legalCard.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            legalCard.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            legalCard.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
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

    private func makeActionRow(for entry: ReceivableEntry) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        row.addArrangedSubview(makeIconSquare(systemName: "doc.text") { [weak self] in
            self?.presentCreditorContractPopup(for: entry)
        })
        row.addArrangedSubview(makeIconSquare(systemName: "square.and.arrow.up") { [weak self] in
            self?.openAttachmentPicker(for: entry.title)
        })
        row.addArrangedSubview(
            makePrimaryActionButton(
                title: "Cobrar",
                color: UIColor(hex: "#EAF1F8"),
                textColor: UIColor(hex: "#7A8B9F"),
                icon: "bubble.left"
            ) { [weak self] in
                self?.presentConciliationPopup(disputeTitle: entry.title)
            }
        )

        return row
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
        button.accessibilityHint = "Executa uma ação rápida relacionada à cobrança."
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 38)
        ])
        return button
    }

    private func makePrimaryActionButton(
        title: String,
        color: UIColor,
        textColor: UIColor,
        icon: String,
        action: @escaping () -> Void
    ) -> UIView {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("  \(title)", for: .normal)
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.applyScaledTitleFont(size: 16, weight: .semibold, textStyle: .headline)
        button.layer.cornerRadius = 19
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D2DBE7").cgColor
        button.applyStableStateColors(
            normalBackground: color,
            normalForeground: textColor
        )
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.accessibilityHint = "Abre a ação principal desta cobrança."
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 38),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 106)
        ])
        return button
    }

    private func makeFormalizeCard(for entry: ReceivableEntry) -> UIView {
        let card = makeSurfaceCard(background: UIColor(hex: "#F3F7FB"), border: UIColor(hex: "#D0DBE8"), cornerRadius: 10)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "⚖︎  Formalizar Cobrança"
        title.textColor = UIColor(hex: "#283344")
        title.applyScaledFont(size: 16, weight: .bold, textStyle: .headline)

        let description = UILabel()
        description.translatesAutoresizingMaskIntoConstraints = false
        description.text = "Gere uma Notificação Extrajudicial com validade jurídica. Este documento serve como prova da existência da dívida e constituição em mora."
        description.textColor = UIColor(hex: "#74879E")
        description.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)
        description.numberOfLines = 0

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("  Gerar Notificação Extrajudicial", for: .normal)
        button.setImage(UIImage(systemName: "doc.text"), for: .normal)
        button.applyScaledTitleFont(size: 15, weight: .bold, textStyle: .headline)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.applyStableStateColors(
            normalBackground: UIColor(fixedHex: "#1F2A39"),
            normalForeground: .white,
            disabledBackground: UIColor(fixedHex: "#1F2A39", alpha: 0.58)
        )
        button.addAction(UIAction { [weak self] _ in
            self?.presentCreditorContractPopup(for: entry)
        }, for: .touchUpInside)

        card.addSubview(title)
        card.addSubview(description)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            description.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            description.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            description.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            button.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 12),
            button.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            button.heightAnchor.constraint(equalToConstant: 46),
            button.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func presentCreditorContractPopup(for entry: ReceivableEntry) {
        let fallbackText = creditorContractText(for: entry)
        var resolvedContractID = entry.contractID
        let popup = ContractDigitalPopupViewController(
            mode: .creditorActions,
            contractTextOverride: fallbackText
        )
        hydrateCreditorContractPopup(
            popup,
            entry: entry,
            fallbackText: fallbackText
        ) { contractID in
            resolvedContractID = contractID ?? resolvedContractID
        }
        popup.onDownload = { [weak self, weak popup] in
            self?.downloadContractIfPossible(
                contractID: resolvedContractID,
                fallbackText: popup?.currentContractText ?? fallbackText,
                title: entry.title,
                presenter: popup
            )
        }
        popup.onProtest = { [weak self, weak popup] in
            popup?.dismiss(animated: true) {
                self?.presentSerasaPopup(for: entry)
            }
        }
        popup.onSignAsCreditor = { [weak self, weak popup] in
            popup?.dismiss(animated: true) {
                self?.presentGovBrCreditorPopup(
                    for: entry,
                    contractText: popup?.currentContractText ?? fallbackText,
                    contractID: resolvedContractID
                )
            }
        }
        present(popup, animated: true)
    }

    private func presentGovBrCreditorPopup(for entry: ReceivableEntry, contractText: String, contractID: String?) {
        let popup = ContractDigitalPopupViewController(
            mode: .govBrCreditor,
            contractTextOverride: contractText
        )
        popup.onDraw = { [weak self] in
            self?.signCreditorContract(contractID: contractID, signatureType: .physical, popup: popup)
        }
        popup.onGovBr = { [weak self, weak popup] in
            guard let popup else { return }
            self?.signCreditorContract(contractID: contractID, signatureType: .govBr, popup: popup)
        }
        present(popup, animated: true)
    }

    private func presentSerasaPopup(for entry: ReceivableEntry) {
        let overdueText = entry.status == "Atrasado" ? "em atraso" : "a verificar"
        let popup = SerasaPopupViewController(
            debtTitle: entry.title,
            amountText: entry.amount,
            documentText: entry.debtorDocument ?? "não informado",
            overdueText: overdueText
        )
        popup.onConfirmNegativation = { [weak self, weak popup] in
            popup?.dismiss(animated: true) {
                self?.showSimpleToast("Negativação enviada para Serasa (simulação).", style: .success)
            }
        }
        present(popup, animated: true)
        hydrateSerasaPopup(popup, debtID: entry.debtID)
    }

    private func presentConciliationPopup(disputeTitle: String) {
        let popup = ConciliationPopupViewController(disputeTitle: disputeTitle)
        present(popup, animated: true)
    }

    private func openAttachmentPicker(for debtTitle: String) {
        attachmentDebtTitle = debtTitle
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let debtTitle = attachmentDebtTitle ?? "cobrança"
        showSimpleToast("Arquivo \"\(url.lastPathComponent)\" anexado em \(debtTitle).", style: .success)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        showSimpleToast("Anexo cancelado.")
    }

    private func metricsForDebts(_ debts: [DebtItem], totalOpenOverride: Decimal? = nil) -> ReceivableMetrics {
        let openDebts = debts.filter { $0.status != .paga && $0.status != .cancelada }
        let overdueCount = debts.filter { $0.status == .vencida }.count
        let paidCount = debts.filter { $0.status == .paga }.count
        let computedTotalOpen = openDebts.reduce(Decimal.zero) { partialResult, item in
            partialResult + item.valor
        }
        let totalOpen = totalOpenOverride ?? computedTotalOpen

        let rawScore = max(0, (paidCount * 130) + (debts.count * 20) - (overdueCount * 85))
        return ReceivableMetrics(
            totalOpen: totalOpen,
            overdueCount: overdueCount,
            paidCount: paidCount,
            reputationPoints: rawScore,
            reputationLevel: reputationLevel(for: rawScore, hasDebts: !debts.isEmpty)
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

    private func statusPresentation(for status: DebtStatus) -> (text: String, background: UIColor, textColor: UIColor, warning: String?) {
        switch status {
        case .pendente:
            return ("A Receber", UIColor(hex: "#DCECF8"), UIColor(hex: "#2886C4"), nil)
        case .vencida:
            return ("Atrasado", UIColor(hex: "#F8D7DA"), UIColor(hex: "#D75C5C"), "Cobrança em atraso. Revise multa e juros antes de formalizar.")
        case .negociada:
            return ("Em Negociação", UIColor(hex: "#FCECC8"), UIColor(hex: "#C78615"), nil)
        case .parcial:
            return ("Parcial", UIColor(hex: "#E6F4FF"), UIColor(hex: "#1D75B3"), "Pagamento parcial identificado. Avalie o saldo antes de cobrar novamente.")
        case .paga:
            return ("Pago", UIColor(hex: "#DCFCE7"), UIColor(hex: "#169C57"), nil)
        case .cancelada:
            return ("Cancelado", UIColor(hex: "#E5E7EB"), UIColor(hex: "#6B7280"), nil)
        }
    }

    private func normalizedCurrency(_ value: String) -> String {
        Formatters.normalizeCurrencyDisplay(value)
    }

    private func creditorContractText(for entry: ReceivableEntry) -> String {
        return """
        CONTRATO DE RECONHECIMENTO DE DÍVIDA

        Pelo presente instrumento particular, as partes abaixo qualificadas têm entre si justo e contratado o seguinte:

        CLÁUSULA 1ª - DO OBJETO
        O presente contrato tem por objeto o reconhecimento de dívida referente a "\(entry.title)".

        CLÁUSULA 2ª - DO VENCIMENTO
        A dívida tem vencimento em \(entry.dueDate.replacingOccurrences(of: "Vence em ", with: "")).

        CLÁUSULA 3ª - DA FORMA DE PAGAMENTO
        O pagamento será realizado conforme condições acordadas entre as partes, com valor de referência em \(entry.amount).

        CLÁUSULA 4ª - DA MULTA E JURO
        Em caso de atraso, poderão incidir multa e juros conforme legislação aplicável.

        Documento gerado por IA e validado eletronicamente via BillEasy.ia.
        """
    }

    private func hydrateCreditorContractPopup(
        _ popup: ContractDigitalPopupViewController,
        entry: ReceivableEntry,
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

    private func hydrateSerasaPopup(_ popup: SerasaPopupViewController, debtID: String) {
        guard actionsService.isRemoteMode else { return }

        Task { [weak self, weak popup] in
            guard let self else { return }

            do {
                let detail = try await self.actionsService.fetchDebtDetail(debtID: debtID)
                _ = await MainActor.run {
                    popup?.updateSummary(
                        debtTitle: detail.title,
                        amountText: detail.updatedAmountText,
                        documentText: detail.debtorDocument ?? "não informado",
                        overdueText: detail.overdueText
                    )
                }
            } catch {
                _ = await MainActor.run {
                    self.showSimpleToast("Não consegui atualizar os dados do Serasa agora. Mantive o resumo local.", style: .info)
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
                showSimpleToast("Essa cobrança ainda não possui contrato remoto vinculado. Abri a visualização local do contrato.", style: .info)
            } catch {
                showSimpleToast("Essa cobrança ainda não possui contrato remoto vinculado e eu não consegui gerar a visualização local do contrato.", style: .error)
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

    private func signCreditorContract(
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
                self?.showSimpleToast("Essa cobrança ainda não possui contrato remoto vinculado.", style: .info)
            }
            return
        }

        Task { [weak self, weak popup] in
            guard let self else { return }

            do {
                _ = try await self.actionsService.signContractAsCreditor(
                    contractID: contractID,
                    signatureType: signatureType
                )

                _ = await MainActor.run {
                    popup?.dismiss(animated: true) {
                        self.showSimpleToast("Contrato assinado com sucesso pelo credor.", style: .success)
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
            loadReceivablePage()
        }
    }

    private func view(for row: Row) -> UIView {
        switch row {
        case let .sectionTitle(title):
            return makeSectionTitle(title)
        case .total:
            return makeTotalCard()
        case .reputation:
            return makeReputationCard()
        case .actions:
            return makeActionsCard()
        case .initialLoading:
            return makeInitialLoadingCard()
        case .empty:
            return makeEmptyStateCard()
        case .detailLoading:
            return makeLoadingFooter(text: "Atualizando valores, vencimentos e parcelamento...")
        case let .receivable(entry):
            return makeReceivableCard(entry)
        case .pageLoading:
            return makeLoadingFooter(text: "Carregando mais cobranças...")
        case .spacer:
            let spacer = UIView()
            spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
            return spacer
        }
    }

    private func insets(for row: Row) -> UIEdgeInsets {
        switch row {
        case .spacer:
            return .zero
        default:
            return UIEdgeInsets(
                top: Layout.stackSpacing / 2,
                left: Layout.horizontalMargin,
                bottom: Layout.stackSpacing / 2,
                right: Layout.horizontalMargin
            )
        }
    }
}
