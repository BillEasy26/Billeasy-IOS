//
//  RouteListViewController.swift
//  BillEasy
//

import UIKit

#if DEBUG
/// Aqui eu exponho uma lista simples de rotas auxiliares para navegação e testes internos.
final class RouteListViewController: UITableViewController {
    var onLogout: (() -> Void)?

    private let session: AuthSession
    private let routes: [AppRouteDefinition]
    private let dataStore: LocalAppDataStore

    init(session: AuthSession, routes: [AppRouteDefinition], dataStore: LocalAppDataStore) {
        self.session = session
        self.routes = routes
        self.dataStore = dataStore
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Mais"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        configureNavigation()
        tableView.tableHeaderView = makeTableHeaderView()
    }

    /// Aqui eu deixo explícita a ação de logout dessa listagem auxiliar.
    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Sair",
            style: .plain,
            target: self,
            action: #selector(logoutTapped)
        )
    }

    /// Aqui eu mostro no cabeçalho qual sessão local está alimentando a navegação.
    private func makeTableHeaderView() -> UIView {
        let headerLabel = UILabel()
        headerLabel.text = "Sessão local: \(session.email)"
        headerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        headerLabel.textColor = .secondaryLabel
        headerLabel.numberOfLines = 0
        headerLabel.textAlignment = .left

        let headerContainer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 56))
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerLabel)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -20),
            headerLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor)
        ])

        return headerContainer
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        routes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let route = routes[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = route.title
        config.secondaryText = route.webRoute.rawValue
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    /// Aqui eu entrego a rota selecionada para a factory nativa que escolhe a tela apropriada.
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let definition = routes[indexPath.row]
        let destination = RouteScreenFactory.makeScreen(
            for: definition.webRoute,
            title: definition.title,
            dataStore: dataStore,
            session: session
        )
        navigationController?.pushViewController(destination, animated: true)
    }

    /// Aqui eu devolvo o fluxo para quem abriu essa listagem auxiliar.
    @objc private func logoutTapped() {
        onLogout?()
    }
}
#endif
