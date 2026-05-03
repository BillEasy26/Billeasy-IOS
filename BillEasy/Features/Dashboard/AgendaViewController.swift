//
//  AgendaViewController.swift
//  BillEasy
//

import UIKit

/// Aqui eu organizo a agenda combinando o fallback local com a lista remota de dívidas.
final class AgendaViewController: UIViewController, UIScrollViewDelegate {
    /// Aqui eu represento o formato final de cada item que aparece na agenda.
    private struct AgendaItem {
        let day: String
        let month: String
        let title: String
        let debtor: String
        let installmentSummary: String?
        let amount: String
        let status: String
        let statusColor: UIColor
    }

    /// Aqui eu centralizo os formatters de data para nao recria-los em toda atualizacao.
    private enum AgendaFormatters {
        static let day: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "pt_BR")
            formatter.dateFormat = "d"
            return formatter
        }()

        static let month: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "pt_BR")
            formatter.dateFormat = "MMM"
            return formatter
        }()
    }

    /// Aqui eu concentro medidas visuais da agenda para manter o mesmo grid das outras telas.
    private enum Layout {
        static let stackSpacing: CGFloat = 14
        static let horizontalMargin: CGFloat = 14
        static let topMargin: CGFloat = 16
        static let bottomMargin: CGFloat = 28
        static let sectionTitleSize: CGFloat = 30
        static let cardCornerRadius: CGFloat = 16
        static let contentInset: CGFloat = 16
    }

    private let session: AuthSession
    private let dataStore: LocalAppDataStore
    private let portalService: PortalDataService
    private let actionsService: PortalActionsService
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private var items: [AgendaItem] = []
    private var remoteDebts: [DebtItem] = []
    private var remoteDebtDetails: [String: PortalDebtDetail] = [:]
    private var remoteDetailRequestsInFlight: Set<String> = []
    private var remoteCurrentPage = 0
    private var remoteHasMorePages = true
    private var remoteIsLoadingPage = false
    private let remotePageSize = 20

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
        setupView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadAgenda()
        renderContent()
    }

    /// Aqui eu monto o container rolavel e deixo o conteudo ser redesenhado por estado.
    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self

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
    }

    /// Aqui eu preparo a agenda local e, quando disponível, substituo pelos dados reais do backend.
    private func reloadAgenda() {
        if portalService.isRemoteMode {
            resetRemotePagination()
            applyDebtSnapshot([])
            renderContent()
            refreshRemoteAgendaIfNeeded()
        } else {
            applyDebtSnapshot(dataStore.fetchDebts())
        }
    }

    /// Aqui eu reaproveito o mesmo mapeamento visual para dados locais e remotos.
    private func applyDebtSnapshot(_ debts: [DebtItem]) {
        items = debts.map { debt in
            let detail = remoteDebtDetails[debt.id]
            let dueDate = detail?.dueDate ?? debt.vencimento
            let day = AgendaFormatters.day.string(from: dueDate)
            let month = AgendaFormatters.month.string(from: dueDate).uppercased()
            let status = agendaStatusPresentation(for: debt.status, detail: detail)
            let resolvedTitle = detail.map { detail in
                let trimmed = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? nil

            return AgendaItem(
                day: day,
                month: month,
                title: resolvedTitle ?? debt.titulo,
                debtor: debt.devedorNome,
                installmentSummary: detail?.installmentSummary,
                amount: detail?.updatedAmountText ?? debt.valor.asCurrency,
                status: status.text,
                statusColor: status.color
            )
        }
    }

    /// Aqui eu puxo a agenda remota sem comprometer a abertura da tela quando a API estiver indisponível.
    private func refreshRemoteAgendaIfNeeded() {
        guard portalService.isRemoteMode else { return }
        guard session.canAccessCreditorWorkspace else { return }
        loadAgendaPage(reset: true)
    }

    /// Aqui eu reinicio a paginação antes de refazer a leitura remota da agenda.
    private func resetRemotePagination() {
        remoteDebts = []
        remoteDebtDetails = [:]
        remoteDetailRequestsInFlight = []
        remoteCurrentPage = 0
        remoteHasMorePages = true
        remoteIsLoadingPage = false
    }

    /// Aqui eu carrego a próxima página da agenda remota e acumulo os itens para o scroll infinito.
    private func loadAgendaPage(reset: Bool = false) {
        guard portalService.isRemoteMode else { return }
        guard session.canAccessCreditorWorkspace else { return }
        guard remoteIsLoadingPage == false else { return }
        guard reset || remoteHasMorePages else { return }

        let pageToLoad = reset ? 0 : remoteCurrentPage + 1
        remoteIsLoadingPage = true
        renderContent()

        Task { [weak self] in
            guard let self else { return }

            do {
                let page = try await self.portalService.fetchReceivableDebtPage(page: pageToLoad, size: self.remotePageSize)
                await MainActor.run {
                    guard self.session.userID.isEmpty == false else { return }
                    if reset {
                        self.remoteDebts = page.debts
                    } else {
                        self.remoteDebts = self.mergeRemoteDebts(self.remoteDebts, with: page.debts)
                    }
                    self.remoteCurrentPage = page.pageNumber
                    self.remoteHasMorePages = page.isLastPage == false
                    self.remoteIsLoadingPage = false
                    self.applyDebtSnapshot(self.remoteDebts)
                    self.renderContent()
                    self.preloadDebtDetails(for: page.debts)
                }
            } catch {
                await MainActor.run {
                    self.remoteIsLoadingPage = false
                    self.renderContent()
                }
            }
        }
    }

    /// Aqui eu removo duplicidades entre páginas para a agenda não repetir vencimentos.
    private func mergeRemoteDebts(_ current: [DebtItem], with nextPage: [DebtItem]) -> [DebtItem] {
        let currentIDs = Set(current.map(\.id))
        return current + nextPage.filter { currentIDs.contains($0.id) == false }
    }

    /// Aqui eu carrego o detalhe remoto de cada item da agenda para refinar valor e atraso sem travar a lista.
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
                        self.applyDebtSnapshot(self.remoteDebts)
                        self.renderContent()
                    }
                } catch {
                    _ = await MainActor.run {
                        self.remoteDetailRequestsInFlight.remove(debt.id)
                    }
                }
            }
        }
    }

    /// Aqui eu reconstruo a tela inteira a partir dos itens atuais da agenda.
    private func renderContent() {
        clearRenderedContent()
        stack.addArrangedSubview(makeSectionTitle("Agenda"))

        stack.addArrangedSubview(makeHeaderCard())

        if isShowingInitialRemoteLoading {
            stack.addArrangedSubview(makeInitialLoadingCard())
            return
        }

        if remoteDetailRequestsInFlight.isEmpty == false, items.isEmpty == false {
            stack.addArrangedSubview(makeLoadingFooter(text: "Atualizando valores, vencimentos e parcelamento..."))
        }

        if items.isEmpty {
            stack.addArrangedSubview(makeEmptyStateCard())
            return
        }

        for item in items {
            stack.addArrangedSubview(makeAgendaCard(item))
        }

        if remoteIsLoadingPage {
            stack.addArrangedSubview(makeLoadingFooter(text: "Carregando mais vencimentos..."))
        }
    }

    /// Aqui eu limpo o conteudo renderizado antes de desenhar a versao atual da tela.
    private func clearRenderedContent() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    /// Aqui eu mostro um rodapé simples enquanto a próxima página da agenda está em trânsito.
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

    /// Aqui eu evito mostrar agenda vazia antes da primeira resposta remota chegar.
    private func makeInitialLoadingCard() -> UIView {
        BrandCardFactory.makeLoadingStateCard(
            title: "Carregando agenda",
            subtitle: "Estou buscando os próximos vencimentos e refinando cada item com valor atualizado, atraso e parcelamento do backend."
        )
    }

    /// Aqui eu separo o loading inicial do estado realmente vazio.
    private var isShowingInitialRemoteLoading: Bool {
        portalService.isRemoteMode && remoteIsLoadingPage && remoteDebts.isEmpty
    }

    /// Aqui eu padronizo o titulo principal da tela.
    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor(hex: "#252E3A")
        label.applyScaledFont(size: Layout.sectionTitleSize, weight: .bold, textStyle: .largeTitle)
        label.accessibilityTraits.insert(.header)
        return label
    }

    /// Aqui eu reaproveito o mesmo estilo de card claro usado na agenda.
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

    /// Aqui eu apresento o contexto da agenda e o resumo do que o usuario vera na lista.
    private func makeHeaderCard() -> UIView {
        let header = UIView()

        let iconBack = UIView()
        iconBack.translatesAutoresizingMaskIntoConstraints = false
        iconBack.backgroundColor = UIColor(hex: "#D9E9F6")
        iconBack.layer.cornerRadius = 18
        iconBack.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "calendar"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#2E87C8")

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Agenda de Recebimentos"
        title.textColor = UIColor(hex: "#283344")
        title.applyScaledFont(size: 24, weight: .bold, textStyle: .title2)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Acompanhe vencimentos cadastrados."
        subtitle.textColor = UIColor(hex: "#688097")
        subtitle.applyScaledFont(size: 15, weight: .medium, textStyle: .body)

        header.addSubview(iconBack)
        iconBack.addSubview(icon)
        header.addSubview(title)
        header.addSubview(subtitle)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 68),

            iconBack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            iconBack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconBack.widthAnchor.constraint(equalToConstant: 36),
            iconBack.heightAnchor.constraint(equalToConstant: 36),

            icon.centerXAnchor.constraint(equalTo: iconBack.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBack.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: iconBack.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 2),

            subtitle.leadingAnchor.constraint(equalTo: iconBack.trailingAnchor, constant: 10),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2)
        ])

        return header
    }

    /// Aqui eu explico o estado inicial da agenda quando ainda nao existe nenhuma cobranca.
    private func makeEmptyStateCard() -> UIView {
        BrandCardFactory.makeEmptyStateCard(
            title: "Agenda vazia",
            subtitle: "Assim que você cadastrar contratos com vencimento, os próximos compromissos aparecerão aqui.",
            iconSystemName: "calendar.badge.clock"
        )
    }

    /// Aqui eu monto cada compromisso da agenda com data, devedor, valor e status atual.
    private func makeAgendaCard(_ item: AgendaItem) -> UIView {
        let card = makeSurfaceCard()

        let dateBadge = UIView()
        dateBadge.translatesAutoresizingMaskIntoConstraints = false
        dateBadge.backgroundColor = UIColor(hex: "#E8F2FA")
        dateBadge.layer.cornerRadius = 14
        dateBadge.layer.cornerCurve = .continuous
        dateBadge.layer.borderWidth = 1
        dateBadge.layer.borderColor = UIColor(hex: "#A9C9E6").cgColor

        let dayLabel = UILabel()
        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        dayLabel.text = item.day
        dayLabel.textColor = UIColor(hex: "#1E7CB2")
        dayLabel.applyScaledFont(size: 32, weight: .bold, textStyle: .title1)

        let monthLabel = UILabel()
        monthLabel.translatesAutoresizingMaskIntoConstraints = false
        monthLabel.text = item.month
        monthLabel.textColor = UIColor(hex: "#4B83A8")
        monthLabel.applyScaledFont(size: 13, weight: .bold, textStyle: .caption1)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = item.title
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 17, weight: .bold, textStyle: .headline)
        titleLabel.numberOfLines = 2

        let debtorLabel = UILabel()
        debtorLabel.translatesAutoresizingMaskIntoConstraints = false
        debtorLabel.text = item.debtor
        debtorLabel.textColor = UIColor(hex: "#70849A")
        debtorLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .subheadline)
        debtorLabel.numberOfLines = 2

        let installmentLabel = UILabel()
        installmentLabel.translatesAutoresizingMaskIntoConstraints = false
        installmentLabel.text = item.installmentSummary?.uppercased()
        installmentLabel.textColor = UIColor(hex: "#1D75B3")
        installmentLabel.applyScaledFont(size: 11, weight: .bold, textStyle: .caption1)
        installmentLabel.numberOfLines = 2
        installmentLabel.isHidden = item.installmentSummary == nil

        let amountLabel = UILabel()
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.text = item.amount
        amountLabel.textColor = UIColor(hex: "#2A3442")
        amountLabel.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)
        amountLabel.textAlignment = .right

        let statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = item.status
        statusLabel.textColor = item.statusColor
        statusLabel.applyScaledFont(size: 14, weight: .bold, textStyle: .subheadline)
        statusLabel.textAlignment = .right

        card.addSubview(dateBadge)
        dateBadge.addSubview(dayLabel)
        dateBadge.addSubview(monthLabel)
        card.addSubview(titleLabel)
        card.addSubview(debtorLabel)
        card.addSubview(installmentLabel)
        card.addSubview(amountLabel)
        card.addSubview(statusLabel)
        card.isAccessibilityElement = true
        card.accessibilityTraits = .staticText
        card.accessibilityLabel = item.title
        let installmentAccessibility = item.installmentSummary.map { ", \($0)" } ?? ""
        card.accessibilityValue = "\(item.debtor)\(installmentAccessibility), \(item.amount), \(item.status), data \(item.day) de \(item.month)"

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: item.installmentSummary == nil ? 100 : 116),

            dateBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            dateBadge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            dateBadge.widthAnchor.constraint(equalToConstant: 60),
            dateBadge.heightAnchor.constraint(equalToConstant: 74),

            dayLabel.centerXAnchor.constraint(equalTo: dateBadge.centerXAnchor),
            dayLabel.topAnchor.constraint(equalTo: dateBadge.topAnchor, constant: 8),

            monthLabel.centerXAnchor.constraint(equalTo: dateBadge.centerXAnchor),
            monthLabel.topAnchor.constraint(equalTo: dayLabel.bottomAnchor, constant: -2),

            titleLabel.leadingAnchor.constraint(equalTo: dateBadge.trailingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),

            debtorLabel.leadingAnchor.constraint(equalTo: dateBadge.trailingAnchor, constant: 14),
            debtorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            debtorLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),

            installmentLabel.leadingAnchor.constraint(equalTo: dateBadge.trailingAnchor, constant: 14),
            installmentLabel.topAnchor.constraint(equalTo: debtorLabel.bottomAnchor, constant: 6),
            installmentLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),

            amountLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            amountLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),

            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            statusLabel.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 4)
        ])

        return card
    }

    /// Aqui eu traduzo o status da cobranca para texto e cor em um unico ponto da agenda.
    private func agendaStatusPresentation(for status: DebtStatus, detail: PortalDebtDetail? = nil) -> (text: String, color: UIColor) {
        if let detail, detail.isOverdue {
            return ("ATRASO \(detail.overdueDays)D", UIColor(hex: "#EF4444"))
        }

        switch status {
        case .vencida:
            return ("ATRASADO", UIColor(hex: "#EF4444"))
        case .paga:
            return ("PAGO", UIColor(hex: "#22C55E"))
        case .negociada:
            return ("NEGOCIANDO", UIColor(hex: "#C78615"))
        case .parcial:
            return ("PARCIAL", UIColor(hex: "#D38B12"))
        case .cancelada:
            return ("CANCELADO", UIColor(hex: "#9CA3AF"))
        case .pendente:
            return ("ABERTO", UIColor(hex: "#475569"))
        }
    }

    /// Aqui eu peço a próxima página quando o usuário já estiver perto do fim da agenda.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard portalService.isRemoteMode else { return }
        guard items.isEmpty == false else { return }

        let threshold: CGFloat = 220
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
        let contentHeight = scrollView.contentSize.height

        if visibleBottom >= contentHeight - threshold {
            loadAgendaPage()
        }
    }
}
