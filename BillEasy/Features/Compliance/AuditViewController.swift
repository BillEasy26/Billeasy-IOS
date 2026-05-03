//
//  AuditViewController.swift
//  BillEasy
//

import UIKit

/// Aqui eu listo eventos de auditoria locais para consulta rápida durante desenvolvimento e testes.
final class AuditViewController: UITableViewController {
    private let dataStore: LocalAppDataStore
    private var events: [AuditItem] = []

    init(dataStore: LocalAppDataStore) {
        self.dataStore = dataStore
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Auditoria"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "audit_cell")
        tableView.backgroundColor = UIColor(hex: "#E6EAEE")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    /// Aqui eu devolvo a quantidade de eventos capturados no snapshot local.
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        events.count
    }

    /// Aqui eu monto a célula de auditoria com módulo, ação, usuário e data.
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "audit_cell", for: indexPath)
        let item = events[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = "\(item.modulo.uppercased()) · \(item.acao)"
        config.secondaryText = "\(item.usuario) · \(Formatters.dateTime.string(from: item.createdAt))"
        config.textProperties.font = .billeasyScaledFont(size: 16, weight: .semibold, textStyle: .headline)
        config.secondaryTextProperties.font = .billeasyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)
        config.secondaryTextProperties.numberOfLines = 2
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        cell.accessibilityLabel = "\(item.modulo), \(item.acao)"
        cell.accessibilityValue = "\(item.usuario), \(Formatters.dateTime.string(from: item.createdAt))"
        return cell
    }

    /// Aqui eu sincronizo a lista sempre a partir do data store local.
    private func reloadData() {
        events = dataStore.fetchAuditEvents()
        updateBackgroundState()
        tableView.reloadData()
    }

    /// Aqui eu explico quando ainda não existe nenhum evento de auditoria no ambiente local.
    private func updateBackgroundState() {
        guard events.isEmpty else {
            tableView.backgroundView = nil
            tableView.separatorStyle = .singleLine
            return
        }

        let emptyCard = BrandCardFactory.makeEmptyStateCard(
            title: "Nenhum evento registrado",
            subtitle: "As ações sensíveis do app passarão a aparecer aqui quando o fluxo local gerar novos registros de auditoria.",
            iconSystemName: "doc.text.magnifyingglass"
        )
        let container = UIView()
        container.backgroundColor = UIColor(hex: "#E6EAEE")
        container.addSubview(emptyCard)

        NSLayoutConstraint.activate([
            emptyCard.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            emptyCard.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            emptyCard.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])

        tableView.backgroundView = container
        tableView.separatorStyle = .none
    }
}
