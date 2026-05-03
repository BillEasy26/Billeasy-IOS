//
//  RbacViewController.swift
//  BillEasy
//

import UIKit

/// Aqui eu exponho uma visão simples das permissões por papel para consulta e testes internos.
final class RbacViewController: UITableViewController {
    private let sections: [(title: String, items: [String])] = [
        (
            title: "SUPER_ADMIN",
            items: [
                "usuarios:gerenciar",
                "empresas:gerenciar",
                "dividas:gerenciar",
                "auditoria:visualizar",
                "rbac:gerenciar"
            ]
        ),
        (
            title: "CREDOR",
            items: [
                "devedores:gerenciar",
                "dividas:gerenciar",
                "contratos:gerenciar",
                "pagamentos:visualizar"
            ]
        ),
        (
            title: "DEVEDOR",
            items: [
                "dividas:visualizar",
                "contratos:assinar",
                "pagamentos:visualizar"
            ]
        )
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RBAC"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "rbac_cell")
        tableView.backgroundColor = UIColor(hex: "#E6EAEE")
        tableView.tableHeaderView = makeHeaderView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderLayout()
    }

    /// Aqui eu separo a tabela por perfis para a leitura de permissões ficar mais clara.
    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    /// Aqui eu devolvo a quantidade de permissões listadas dentro de cada perfil.
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    /// Aqui eu uso o nome do papel como cabeçalho visual de cada grupo de permissões.
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    /// Aqui eu exibo cada permissão em fonte monoespaçada para facilitar leitura técnica.
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "rbac_cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = sections[indexPath.section].items[indexPath.row]
        config.textProperties.font = .billeasyScaledMonospacedFont(size: 14, weight: .regular, textStyle: .subheadline)
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        cell.accessibilityLabel = sections[indexPath.section].items[indexPath.row]
        cell.accessibilityValue = "Permissão do perfil \(sections[indexPath.section].title)"
        return cell
    }

    /// Aqui eu adiciono um contexto curto para a leitura técnica da matriz de permissões.
    private func makeHeaderView() -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let card = BrandCardFactory.makeEmptyStateCard(
            title: "Perfis e permissões",
            subtitle: "Use esta visão para conferir rapidamente quais capacidades cada papel possui no app local.",
            iconSystemName: "lock.shield"
        )

        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    /// Aqui eu recalculo a altura do header para o Dynamic Type não cortar o conteúdo.
    private func updateHeaderLayout() {
        guard let header = tableView.tableHeaderView else { return }
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = header.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        guard header.frame.height != height else { return }
        header.frame.size.height = height
        tableView.tableHeaderView = header
    }
}
