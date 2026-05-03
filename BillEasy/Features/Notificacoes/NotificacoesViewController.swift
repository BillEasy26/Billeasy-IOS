//
//  NotificacoesViewController.swift
//  BillEasy
//

import UIKit

final class NotificacoesViewController: UIViewController {

    // MARK: - Layout constants

    private enum Layout {
        static let horizontalMargin: CGFloat = 16
        static let topMargin: CGFloat = 16
        static let bottomMargin: CGFloat = 28
        static let cardCornerRadius: CGFloat = 16
        static let rowHeight: CGFloat = 88
    }

    // MARK: - Cell model

    struct Row {
        let id: String
        let titulo: String
        let mensagem: String?
        let tipoDisplay: String
        let dataDisplay: String
        var lida: Bool
    }

    // MARK: - Dependencies

    private let service: NotificacoesService
    private let session: AuthSession

    // MARK: - State

    private var rows: [Row] = []
    private var currentPage = 0
    private var hasMorePages = true
    private var isLoadingPage = false
    private let pageSize = 20

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let emptyContainer = UIView()
    private let loadingContainer = UIView()

    // MARK: - Callbacks

    var onVoltar: (() -> Void)?

    // MARK: - Init

    init(session: AuthSession, service: NotificacoesService = NotificacoesService()) {
        self.session = session
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        loadFirstPage()
    }

    // MARK: - Setup

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        setupHeader()
        setupTableView()
        setupEmptyState()
        setupLoadingState()
    }

    private func setupHeader() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = UIColor(hex: "#E6EAEE")
        view.addSubview(header)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Notificações"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 28, weight: .bold, textStyle: .largeTitle)
        titleLabel.accessibilityTraits = [.header]

        let markAllButton = UIButton(type: .system)
        markAllButton.translatesAutoresizingMaskIntoConstraints = false
        markAllButton.setTitle("Marcar todas lidas", for: .normal)
        markAllButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        markAllButton.tintColor = UIColor(hex: "#2E87C8")
        markAllButton.addTarget(self, action: #selector(marcarTodasLidas), for: .touchUpInside)

        header.addSubview(titleLabel)
        header.addSubview(markAllButton)

        var titleLeadingAnchor = header.leadingAnchor

        if onVoltar != nil {
            let closeButton = UIButton(type: .system)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            closeButton.tintColor = UIColor(hex: "#2E87C8")
            closeButton.accessibilityLabel = "Fechar"
            closeButton.addTarget(self, action: #selector(voltarTapped), for: .touchUpInside)
            header.addSubview(closeButton)
            NSLayoutConstraint.activate([
                closeButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Layout.horizontalMargin),
                closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 28),
                closeButton.heightAnchor.constraint(equalToConstant: 28)
            ])
            titleLeadingAnchor = closeButton.trailingAnchor
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: titleLeadingAnchor, constant: Layout.horizontalMargin),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            markAllButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Layout.horizontalMargin),
            markAllButton.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = Layout.rowHeight
        tableView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: Layout.bottomMargin,
            right: 0
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(NotificacaoCell.self, forCellReuseIdentifier: NotificacaoCell.reuseID)
        refreshControl.tintColor = UIColor(hex: "#2E87C8")
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    private func setupEmptyState() {
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.isHidden = true
        view.addSubview(emptyContainer)

        let card = BrandCardFactory.makeEmptyStateCard(
            title: "Sem notificações",
            subtitle: "Você está em dia! Novos alertas de vencimento, contratos e atividades aparecerão aqui.",
            iconSystemName: "bell.slash"
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addSubview(card)

        NSLayoutConstraint.activate([
            emptyContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            emptyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalMargin),
            emptyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalMargin),

            card.topAnchor.constraint(equalTo: emptyContainer.topAnchor, constant: Layout.topMargin),
            card.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: emptyContainer.bottomAnchor)
        ])
    }

    private func setupLoadingState() {
        loadingContainer.translatesAutoresizingMaskIntoConstraints = false
        loadingContainer.isHidden = true
        view.addSubview(loadingContainer)

        let card = BrandCardFactory.makeLoadingStateCard(
            title: "Carregando notificações",
            subtitle: "Buscando alertas e atualizações…"
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        loadingContainer.addSubview(card)

        NSLayoutConstraint.activate([
            loadingContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            loadingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalMargin),
            loadingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalMargin),

            card.topAnchor.constraint(equalTo: loadingContainer.topAnchor, constant: Layout.topMargin),
            card.leadingAnchor.constraint(equalTo: loadingContainer.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: loadingContainer.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: loadingContainer.bottomAnchor)
        ])
    }

    // MARK: - Data loading

    private func loadFirstPage() {
        guard !isLoadingPage else { return }
        guard service.isRemoteMode else {
            showEmptyState()
            return
        }

        showInitialLoading()

        Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.service.fetchPage(page: 0, size: self.pageSize)
                await MainActor.run {
                    self.rows = self.mapRows(from: page.items)
                    self.currentPage = page.pageNumber
                    self.hasMorePages = !page.isLast
                    self.isLoadingPage = false
                    self.refreshControl.endRefreshing()
                    self.applySnapshot()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingPage = false
                    self.refreshControl.endRefreshing()
                    self.showSimpleToast(error.localizedDescription, style: .error)
                    if self.rows.isEmpty { self.showEmptyState() }
                }
            }
        }
    }

    private func loadNextPage() {
        guard service.isRemoteMode else { return }
        guard !isLoadingPage, hasMorePages else { return }

        isLoadingPage = true
        let nextPage = currentPage + 1

        Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.service.fetchPage(page: nextPage, size: self.pageSize)
                await MainActor.run {
                    let newRows = self.mapRows(from: page.items)
                    let existingIDs = Set(self.rows.map(\.id))
                    let unique = newRows.filter { !existingIDs.contains($0.id) }
                    self.rows.append(contentsOf: unique)
                    self.currentPage = page.pageNumber
                    self.hasMorePages = !page.isLast
                    self.isLoadingPage = false
                    self.tableView.reloadData()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingPage = false
                }
            }
        }
    }

    private func mapRows(from items: [Notificacao]) -> [Row] {
        items.map {
            Row(
                id: $0.id,
                titulo: $0.titulo,
                mensagem: $0.mensagem,
                tipoDisplay: $0.tipoDisplay,
                dataDisplay: $0.criadoEmDisplay,
                lida: $0.lida
            )
        }
    }

    private func applySnapshot() {
        loadingContainer.isHidden = true
        if rows.isEmpty {
            showEmptyState()
        } else {
            emptyContainer.isHidden = true
            tableView.reloadData()
        }
    }

    private func showInitialLoading() {
        isLoadingPage = true
        loadingContainer.isHidden = false
        emptyContainer.isHidden = true
    }

    private func showEmptyState() {
        loadingContainer.isHidden = true
        emptyContainer.isHidden = false
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func voltarTapped() {
        onVoltar?()
    }

    @objc private func handleRefresh() {
        currentPage = 0
        hasMorePages = true
        rows = []
        loadFirstPage()
    }

    @objc private func marcarTodasLidas() {
        guard service.isRemoteMode else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.marcarTodasLidas()
                await MainActor.run {
                    self.rows = self.rows.map { Row(
                        id: $0.id,
                        titulo: $0.titulo,
                        mensagem: $0.mensagem,
                        tipoDisplay: $0.tipoDisplay,
                        dataDisplay: $0.dataDisplay,
                        lida: true
                    ) }
                    self.tableView.reloadData()
                    self.showSimpleToast("Todas as notificações marcadas como lidas.", style: .success)
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func marcarLidaOuNaoLida(at indexPath: IndexPath) {
        guard indexPath.row < rows.count else { return }
        var row = rows[indexPath.row]
        let wasLida = row.lida
        let id = row.id

        row.lida = !wasLida
        rows[indexPath.row] = row
        tableView.reloadRows(at: [indexPath], with: .automatic)

        Task { [weak self] in
            guard let self else { return }
            do {
                if wasLida {
                    try await self.service.marcarNaoLida(id: id)
                } else {
                    try await self.service.marcarLida(id: id)
                }
            } catch {
                await MainActor.run {
                    var restored = self.rows[indexPath.row]
                    restored.lida = wasLida
                    self.rows[indexPath.row] = restored
                    self.tableView.reloadRows(at: [indexPath], with: .automatic)
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func deletar(at indexPath: IndexPath) {
        guard indexPath.row < rows.count else { return }
        let id = rows[indexPath.row].id
        rows.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        if rows.isEmpty { showEmptyState() }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.deletar(id: id)
            } catch {
                await MainActor.run {
                    self.showSimpleToast("Não foi possível excluir a notificação.", style: .error)
                    self.loadFirstPage()
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension NotificacoesViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: NotificacaoCell.reuseID, for: indexPath) as! NotificacaoCell
        cell.configure(with: rows[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension NotificacoesViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard rows[indexPath.row].lida == false else { return }
        marcarLidaOuNaoLida(at: indexPath)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Excluir") { [weak self] _, _, done in
            self?.deletar(at: indexPath)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.row < rows.count else { return nil }
        let row = rows[indexPath.row]
        let title = row.lida ? "Não Lida" : "Lida"
        let icon = row.lida ? "envelope" : "envelope.open"

        let action = UIContextualAction(style: .normal, title: title) { [weak self] _, _, done in
            self?.marcarLidaOuNaoLida(at: indexPath)
            done(true)
        }
        action.image = UIImage(systemName: icon)
        action.backgroundColor = UIColor(hex: "#2E87C8")
        return UISwipeActionsConfiguration(actions: [action])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let threshold: CGFloat = 200
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
        let contentHeight = scrollView.contentSize.height
        if visibleBottom >= contentHeight - threshold {
            loadNextPage()
        }
    }
}

// MARK: - NotificacaoCell

private final class NotificacaoCell: UITableViewCell {
    static let reuseID = "NotificacaoCell"

    private let cardView = UIView()
    private let dotView = UIView()
    private let tipoPill = UIView()
    private let tipoLabel = UILabel()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        backgroundColor = .clear
        selectionStyle = .none

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(hex: "#F8FAFC")
        cardView.layer.cornerRadius = 14
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        contentView.addSubview(cardView)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.backgroundColor = UIColor(hex: "#2E87C8")
        dotView.layer.cornerRadius = 5
        cardView.addSubview(dotView)

        tipoPill.translatesAutoresizingMaskIntoConstraints = false
        tipoPill.layer.cornerRadius = 8
        tipoPill.layer.cornerCurve = .continuous
        cardView.addSubview(tipoPill)

        tipoLabel.translatesAutoresizingMaskIntoConstraints = false
        tipoLabel.applyScaledFont(size: 10, weight: .bold, textStyle: .caption1)
        tipoPill.addSubview(tipoLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.applyScaledFont(size: 15, weight: .semibold, textStyle: .body)
        titleLabel.textColor = UIColor(hex: "#252E3A")
        cardView.addSubview(titleLabel)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 2
        messageLabel.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)
        messageLabel.textColor = UIColor(hex: "#6E7F95")
        cardView.addSubview(messageLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption2)
        dateLabel.textColor = UIColor(hex: "#9CAABB")
        cardView.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),

            dotView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            dotView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10),

            tipoPill.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            tipoPill.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            tipoPill.heightAnchor.constraint(equalToConstant: 20),

            tipoLabel.leadingAnchor.constraint(equalTo: tipoPill.leadingAnchor, constant: 8),
            tipoLabel.trailingAnchor.constraint(equalTo: tipoPill.trailingAnchor, constant: -8),
            tipoLabel.centerYAnchor.constraint(equalTo: tipoPill.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: tipoPill.leadingAnchor, constant: -8),

            messageLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 10),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            messageLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            dateLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 10),
            dateLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 6),
            dateLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
    }

    func configure(with row: NotificacoesViewController.Row) {
        titleLabel.text = row.titulo
        titleLabel.textColor = row.lida ? UIColor(hex: "#6E7F95") : UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 15, weight: row.lida ? .regular : .semibold, textStyle: .body)

        messageLabel.text = row.mensagem
        messageLabel.isHidden = row.mensagem?.isEmpty ?? true

        dateLabel.text = row.dataDisplay
        dotView.isHidden = row.lida

        tipoLabel.text = row.tipoDisplay.uppercased()
        tipoPill.backgroundColor = UIColor(hex: "#E8F2FA")
        tipoLabel.textColor = UIColor(hex: "#2E87C8")

        cardView.backgroundColor = row.lida
            ? UIColor(hex: "#F8FAFC")
            : UIColor(hex: "#F0F7FD")
        cardView.layer.borderColor = row.lida
            ? UIColor(hex: "#D7DEE8").cgColor
            : UIColor(hex: "#A9C9E6").cgColor

        isAccessibilityElement = true
        accessibilityLabel = row.titulo
        accessibilityValue = "\(row.tipoDisplay), \(row.dataDisplay), \(row.lida ? "lida" : "não lida")"
    }
}
