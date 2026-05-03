import UIKit

/// Aqui eu separo a gestão de devedores da tela de localizar, seguindo o mesmo contrato remoto do web.
final class DebtorDirectoryViewController: UITableViewController, UISearchResultsUpdating {
    private let session: AuthSession
    private let directoryService: PortalDirectoryService
    private let actionsService: PortalActionsService

    private var debtors: [PortalDebtorRecord] = []
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var isLoading = false
    private var currentQuery: String = ""

    init(
        session: AuthSession,
        dataStore: LocalAppDataStore,
        directoryService: PortalDirectoryService? = nil,
        actionsService: PortalActionsService = PortalActionsService()
    ) {
        self.session = session
        self.directoryService = directoryService ?? PortalDirectoryService(dataStore: dataStore)
        self.actionsService = actionsService
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
        lifecycleTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Devedores"
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        tableView.backgroundColor = UIColor(hex: "#E6EAEE")
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 136
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addDebtorTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "debtors.addButton"

        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Buscar por nome"
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .words
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        loadDebtors(showErrorToast: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        debtors.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)
        let debtor = debtors[indexPath.row]

        var config = UIListContentConfiguration.subtitleCell()
        config.text = debtor.name
        config.textProperties.font = .billeasyScaledFont(size: 18, weight: .bold, textStyle: .headline)
        config.textProperties.color = UIColor(hex: "#283344")
        config.textProperties.numberOfLines = 2
        config.secondaryText = makeDebtorSecondaryText(debtor)
        config.secondaryTextProperties.font = .billeasyScaledFont(size: 13, weight: .medium, textStyle: .subheadline)
        config.secondaryTextProperties.color = UIColor(hex: "#6E7F95")
        config.secondaryTextProperties.numberOfLines = 5
        cell.contentConfiguration = config
        cell.backgroundConfiguration = makeCellBackgroundConfiguration(isActive: debtor.isActive)
        cell.accessoryType = .none
        cell.accessoryView = makeDebtorAccessoryView(debtor)
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "debtors.card.\(debtor.id)"
        cell.accessibilityLabel = debtor.name
        cell.accessibilityValue = makeDebtorAccessibilityValue(debtor)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        presentDebtorForm(mode: .edit(debtors[indexPath.row]))
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let debtor = debtors[indexPath.row]
        guard debtor.isActive else { return nil }

        let action = UIContextualAction(style: .destructive, title: "Inativar") { [weak self] _, _, completion in
            self?.performDebtorLifecycle(
                debtor: debtor,
                action: .block,
                successMessage: "Devedor inativado com sucesso.",
                completion: completion
            )
        }
        action.backgroundColor = UIColor(hex: "#DC2626")
        return UISwipeActionsConfiguration(actions: [action])
    }

    override func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let debtor = debtors[indexPath.row]
        guard debtor.isActive == false else { return nil }

        let action = UIContextualAction(style: .normal, title: "Ativar") { [weak self] _, _, completion in
            self?.performDebtorLifecycle(
                debtor: debtor,
                action: .activate,
                successMessage: "Devedor ativado com sucesso.",
                completion: completion
            )
        }
        action.backgroundColor = UIColor(hex: "#16A34A")
        return UISwipeActionsConfiguration(actions: [action])
    }

    func updateSearchResults(for searchController: UISearchController) {
        let newQuery = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentQuery = newQuery
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                self?.loadDebtors(showErrorToast: false)
            }
        }
    }

    @objc private func addDebtorTapped() {
        presentDebtorForm(mode: .create)
    }

    private func loadDebtors(showErrorToast: Bool) {
        loadTask?.cancel()
        isLoading = true
        updateBackgroundState()

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await directoryService.listDebtors(
                    session: session,
                    searchName: currentQuery.nilIfEmpty
                )

                await MainActor.run {
                    self.isLoading = false
                    self.debtors = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    self.updateBackgroundState()
                    self.tableView.reloadData()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.updateBackgroundState()
                    self.tableView.reloadData()
                    if showErrorToast {
                        self.showSimpleToast(error.localizedDescription, style: .error)
                    }
                }
            }
        }
    }

    private func presentDebtorForm(mode: DebtorFormMode) {
        let controller = DebtorFormViewController(
            session: session,
            mode: mode,
            directoryService: directoryService,
            actionsService: actionsService
        )
        controller.onSave = { [weak self] debtor in
            guard let self else { return }
            switch mode {
            case .create:
                self.showSimpleToast("Devedor cadastrado com sucesso.", style: .success)
                self.debtors.insert(debtor, at: 0)
            case .edit:
                self.showSimpleToast("Devedor atualizado com sucesso.", style: .success)
                if let index = self.debtors.firstIndex(where: { $0.id == debtor.id }) {
                    self.debtors[index] = debtor
                } else {
                    self.debtors.insert(debtor, at: 0)
                }
            }
            self.debtors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.updateBackgroundState()
            self.tableView.reloadData()
        }

        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
    }

    private func performDebtorLifecycle(
        debtor: PortalDebtorRecord,
        action: PortalDebtorLifecycleAction,
        successMessage: String,
        completion: @escaping (Bool) -> Void
    ) {
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }

            do {
                let updatedDebtor = try await directoryService.updateDebtorLifecycle(
                    session: session,
                    debtorID: debtor.id,
                    companyID: debtor.companyID,
                    action: action
                )

                await MainActor.run {
                    if let index = self.debtors.firstIndex(where: { $0.id == updatedDebtor.id }) {
                        self.debtors[index] = updatedDebtor
                    }
                    self.debtors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    self.updateBackgroundState()
                    self.tableView.reloadData()
                    self.showSimpleToast(successMessage, style: .success)
                    completion(true)
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                    completion(false)
                }
            }
        }
    }

    private func updateBackgroundState() {
        if isLoading {
            let card = BrandCardFactory.makeLoadingStateCard(
                title: "Carregando devedores",
                subtitle: "Estou sincronizando a lista com o backend e mantendo o snapshot local consistente."
            )
            installBackgroundCard(card)
            return
        }

        guard debtors.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let card = BrandCardFactory.makeEmptyStateCard(
            title: "Nenhum devedor cadastrado",
            subtitle: "Use o botão + para cadastrar um devedor e manter o endereço alinhado com a API de CEP do backend.",
            iconSystemName: "person.2"
        )
        installBackgroundCard(card)
    }

    private func installBackgroundCard(_ card: UIView) {
        let container = UIView()
        container.backgroundColor = UIColor(hex: "#E6EAEE")
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        ])
        tableView.backgroundView = container
    }

    private func makeDebtorSecondaryText(_ debtor: PortalDebtorRecord) -> String {
        let firstLine = [
            Formatters.formatCPFOrCNPJ(debtor.document).nilIfEmpty,
            formattedPhone(debtor.phone).nilIfEmpty
        ].compactMap { $0 }.joined(separator: " • ")

        return [
            firstLine.nilIfEmpty,
            debtor.email.nilIfEmpty,
            debtor.companyName?.nilIfEmpty.map { "Empresa: \($0)" },
            debtor.addressSummary?.nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func makeDebtorAccessibilityValue(_ debtor: PortalDebtorRecord) -> String {
        [
            Formatters.formatCPFOrCNPJ(debtor.document).nilIfEmpty,
            formattedPhone(debtor.phone).nilIfEmpty,
            debtor.email.nilIfEmpty,
            debtor.companyName?.nilIfEmpty,
            debtor.addressSummary?.nilIfEmpty,
            debtorStatusTitle(debtor.status)
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func debtorStatusTitle(_ rawValue: String) -> String {
        switch rawValue.uppercased() {
        case "ATIVO": return "Ativo"
        case "INADIMPLENTE": return "Inadimplente"
        case "BLOQUEADO": return "Bloqueado"
        default: return rawValue
        }
    }

    private func formattedPhone(_ value: String) -> String {
        let digits = Formatters.digitsOnly(value)
        if digits.count <= 10 {
            return Self.formatPhone10(digits)
        }
        return Self.formatPhone11(digits)
    }

    fileprivate static func formatPhone10(_ digits: String) -> String {
        guard digits.isEmpty == false else { return "" }
        let raw = String(digits.prefix(10))
        guard raw.count >= 3 else { return raw }
        if raw.count < 7 {
            return "(\(raw.prefix(2))) \(raw.dropFirst(2))"
        }
        let prefix = raw.prefix(2)
        let middle = raw.dropFirst(2).prefix(4)
        let suffix = raw.dropFirst(6)
        return "(\(prefix)) \(middle)-\(suffix)"
    }

    fileprivate static func formatPhone11(_ digits: String) -> String {
        guard digits.isEmpty == false else { return "" }
        let raw = String(digits.prefix(11))
        guard raw.count >= 3 else { return raw }
        if raw.count < 8 {
            return "(\(raw.prefix(2))) \(raw.dropFirst(2))"
        }
        let prefix = raw.prefix(2)
        let middle = raw.dropFirst(2).prefix(5)
        let suffix = raw.dropFirst(7)
        return "(\(prefix)) \(middle)-\(suffix)"
    }

    private func makeCellBackgroundConfiguration(isActive: Bool) -> UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = UIColor(hex: "#F8FAFC")
        background.strokeColor = isActive ? UIColor(hex: "#D7DEE8") : UIColor(hex: "#E1E6EF")
        background.strokeWidth = 1
        background.cornerRadius = 16
        return background
    }

    private func makeDebtorAccessoryView(_ debtor: PortalDebtorRecord) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8

        let badge = makeDebtorStatusBadge(debtor)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor(hex: "#9AAABC")
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)

        stack.addArrangedSubview(badge)
        stack.addArrangedSubview(chevron)
        return stack
    }

    private func makeDebtorStatusBadge(_ debtor: PortalDebtorRecord) -> UIView {
        let badge = InsetLabel()
        badge.contentInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        badge.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)
        badge.layer.cornerRadius = 11
        badge.layer.cornerCurve = .continuous
        badge.layer.borderWidth = 1
        badge.clipsToBounds = true

        let style = debtorStatusStyle(debtor.status)
        badge.text = style.title
        badge.textColor = style.textColor
        badge.backgroundColor = style.backgroundColor
        badge.layer.borderColor = style.borderColor.cgColor
        return badge
    }

    private func debtorStatusStyle(_ rawValue: String) -> (title: String, backgroundColor: UIColor, borderColor: UIColor, textColor: UIColor) {
        switch rawValue.uppercased() {
        case "ATIVO":
            return ("Ativo", UIColor(hex: "#E9F8EF"), UIColor(hex: "#BEE5CB"), UIColor(hex: "#149C5C"))
        case "BLOQUEADO":
            return ("Bloqueado", UIColor(hex: "#FFF0F0"), UIColor(hex: "#F6C6C6"), UIColor(hex: "#C94D5D"))
        case "INADIMPLENTE":
            return ("Inativo", UIColor(hex: "#FFF8E7"), UIColor(hex: "#F0DCA5"), UIColor(hex: "#B7791F"))
        default:
            return (debtorStatusTitle(rawValue), UIColor(hex: "#E8F2FA"), UIColor(hex: "#C8D6E8"), UIColor(hex: "#1579A8"))
        }
    }

    private static let cellReuseIdentifier = "debtor_cell"
}

private enum DebtorFormMode {
    case create
    case edit(PortalDebtorRecord)
}

private final class DebtorFormViewController: UIViewController, UITextFieldDelegate {
    private let session: AuthSession
    private let mode: DebtorFormMode
    private let directoryService: PortalDirectoryService
    private let actionsService: PortalActionsService

    var onSave: ((PortalDebtorRecord) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let companyButton = UIButton(type: .system)
    private let companyHelperLabel = UILabel()
    private let nameField = UITextField()
    private let documentField = UITextField()
    private let emailField = UITextField()
    private let phoneField = UITextField()
    private let cepField = UITextField()
    private let numberField = UITextField()
    private let complementField = UITextField()
    private let cepLookupButton = UIButton(type: .system)
    private let addressPreviewCard = UIView()
    private let addressPreviewTitleLabel = UILabel()
    private let addressPreviewSubtitleLabel = UILabel()

    private var selectedCompanyID: String?
    private var selectedCompanyName: String?
    private var availableCompanies: [PortalCompanyRecord] = []
    private var addressPreview: PortalAddressPreview?
    private var loadCompaniesTask: Task<Void, Never>?
    private var cepLookupTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    private var needsCompanySelection: Bool {
        session.empresaID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    init(
        session: AuthSession,
        mode: DebtorFormMode,
        directoryService: PortalDirectoryService,
        actionsService: PortalActionsService
    ) {
        self.session = session
        self.mode = mode
        self.directoryService = directoryService
        self.actionsService = actionsService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadCompaniesTask?.cancel()
        cepLookupTask?.cancel()
        saveTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        title = switch mode {
        case .create: "Novo Devedor"
        case .edit: "Editar Devedor"
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Salvar",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )

        setupView()
        populateIfNeeded()
        loadCompaniesIfNeeded()
    }

    private func setupView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18
        stackView.layoutMargins = UIEdgeInsets(top: 24, left: 20, bottom: 28, right: 20)
        stackView.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let introCard = BrandCardFactory.makeEmptyStateCard(
            title: title ?? "Devedor",
            subtitle: "Eu sigo o mesmo contrato do backend web para identificar o devedor, vincular a empresa responsável e preencher o endereço via CEP.",
            iconSystemName: "person.crop.circle.badge.plus"
        )
        stackView.addArrangedSubview(introCard)

        if needsCompanySelection {
            stackView.addArrangedSubview(makeSectionCard(title: "Empresa Responsável", rows: [
                makeLabeledField(title: "Empresa", field: companyButton),
                companyHelperLabel
            ]))
        }

        stackView.addArrangedSubview(makeSectionCard(title: "Dados do Devedor", rows: [
            makeLabeledField(title: "Nome", field: nameField),
            makeLabeledField(title: "CPF/CNPJ", field: documentField),
            makeLabeledField(title: "E-mail", field: emailField),
            makeLabeledField(title: "Telefone", field: phoneField)
        ]))
        stackView.addArrangedSubview(makeAddressCard())

        configureTextField(nameField, placeholder: "Nome completo", keyboardType: .default, identifier: "debtors.form.name")
        configureTextField(documentField, placeholder: "000.000.000-00", keyboardType: .numberPad, identifier: "debtors.form.document")
        configureTextField(emailField, placeholder: "email@cliente.com", keyboardType: .emailAddress, identifier: "debtors.form.email")
        configureTextField(phoneField, placeholder: "(00) 00000-0000", keyboardType: .numberPad, identifier: "debtors.form.phone")
        configureTextField(cepField, placeholder: "00000-000", keyboardType: .numberPad, identifier: "debtors.form.cep")
        configureTextField(numberField, placeholder: "1578", keyboardType: .default, identifier: "debtors.form.number")
        configureTextField(complementField, placeholder: "Sala 12, Casa 2", keyboardType: .default, identifier: "debtors.form.complement")

        documentField.addTarget(self, action: #selector(documentChanged), for: .editingChanged)
        phoneField.addTarget(self, action: #selector(phoneChanged), for: .editingChanged)
        cepField.addTarget(self, action: #selector(cepChanged), for: .editingChanged)

        configureCompanyButton()

        companyHelperLabel.translatesAutoresizingMaskIntoConstraints = false
        companyHelperLabel.numberOfLines = 0
        companyHelperLabel.textColor = UIColor(hex: "#6E7F95")
        companyHelperLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .subheadline)
        companyHelperLabel.text = needsCompanySelection
            ? "Eu preciso da empresa para usar a rota correta do backend ao criar ou editar o devedor."
            : "Vou usar a empresa vinculada à sua sessão para salvar esse devedor."

        cepLookupButton.setTitle("Buscar CEP", for: .normal)
        cepLookupButton.applyStableStateColors(
            normalBackground: UIColor(hex: "#2E87C8"),
            normalForeground: .white,
            disabledBackground: UIColor(hex: "#A9C9E6"),
            disabledForeground: .white
        )
        cepLookupButton.layer.cornerRadius = 12
        cepLookupButton.layer.cornerCurve = .continuous
        cepLookupButton.applyScaledTitleFont(size: 14, weight: .bold, textStyle: .subheadline)
        cepLookupButton.addTarget(self, action: #selector(lookupCEP), for: .touchUpInside)

        addressPreviewCard.translatesAutoresizingMaskIntoConstraints = false
        addressPreviewCard.backgroundColor = UIColor(hex: "#F8FAFC")
        addressPreviewCard.layer.cornerRadius = 14
        addressPreviewCard.layer.cornerCurve = .continuous
        addressPreviewCard.layer.borderWidth = 1
        addressPreviewCard.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        addressPreviewCard.isHidden = true

        addressPreviewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addressPreviewTitleLabel.textColor = UIColor(hex: "#283344")
        addressPreviewTitleLabel.applyScaledFont(size: 15, weight: .bold, textStyle: .headline)
        addressPreviewTitleLabel.numberOfLines = 0

        addressPreviewSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addressPreviewSubtitleLabel.textColor = UIColor(hex: "#6E7F95")
        addressPreviewSubtitleLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .subheadline)
        addressPreviewSubtitleLabel.numberOfLines = 0

        addressPreviewCard.addSubview(addressPreviewTitleLabel)
        addressPreviewCard.addSubview(addressPreviewSubtitleLabel)
        NSLayoutConstraint.activate([
            addressPreviewTitleLabel.topAnchor.constraint(equalTo: addressPreviewCard.topAnchor, constant: 12),
            addressPreviewTitleLabel.leadingAnchor.constraint(equalTo: addressPreviewCard.leadingAnchor, constant: 14),
            addressPreviewTitleLabel.trailingAnchor.constraint(equalTo: addressPreviewCard.trailingAnchor, constant: -14),
            addressPreviewSubtitleLabel.topAnchor.constraint(equalTo: addressPreviewTitleLabel.bottomAnchor, constant: 6),
            addressPreviewSubtitleLabel.leadingAnchor.constraint(equalTo: addressPreviewCard.leadingAnchor, constant: 14),
            addressPreviewSubtitleLabel.trailingAnchor.constraint(equalTo: addressPreviewCard.trailingAnchor, constant: -14),
            addressPreviewSubtitleLabel.bottomAnchor.constraint(equalTo: addressPreviewCard.bottomAnchor, constant: -12)
        ])
    }

    private func configureCompanyButton() {
        companyButton.translatesAutoresizingMaskIntoConstraints = false
        companyButton.layer.cornerRadius = 14
        companyButton.layer.cornerCurve = .continuous
        companyButton.layer.borderWidth = 1
        companyButton.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        companyButton.accessibilityIdentifier = "debtors.form.companyButton"
        companyButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        companyButton.applyStableStateColors(
            normalBackground: UIColor(hex: "#FFFFFF"),
            normalForeground: UIColor(hex: "#607993"),
            disabledBackground: UIColor(hex: "#F3F7FB"),
            disabledForeground: UIColor(hex: "#8AA0B6")
        )
        companyButton.titleLabel?.lineBreakMode = .byTruncatingTail
        companyButton.configuration = makeSelectorConfiguration(title: needsCompanySelection ? "Selecione a empresa" : "Empresa da sua sessão")
        companyButton.showsMenuAsPrimaryAction = true
        companyButton.isEnabled = needsCompanySelection
    }

    private func populateIfNeeded() {
        guard case let .edit(debtor) = mode else { return }
        nameField.text = debtor.name
        documentField.text = Formatters.formatCPFOrCNPJ(debtor.document)
        emailField.text = debtor.email
        phoneField.text = formatPhone(debtor.phone)
        selectedCompanyID = debtor.companyID
        selectedCompanyName = debtor.companyName

        if let address = debtor.address {
            cepField.text = Formatters.formatCEP(address.cep)
            numberField.text = address.numero
            complementField.text = address.complemento
            applyAddressPreview(
                PortalAddressPreview(
                    cep: address.cep,
                    logradouro: address.logradouro,
                    bairro: address.bairro,
                    cidade: address.cidade,
                    estado: address.estado
                )
            )
        }

        documentField.isEnabled = false
        emailField.isEnabled = false
        documentField.alpha = 0.65
        emailField.alpha = 0.65

        if needsCompanySelection {
            companyButton.isEnabled = false
            companyButton.alpha = 0.75
            companyButton.configuration = makeSelectorConfiguration(title: debtor.companyName ?? "Empresa vinculada")
            companyHelperLabel.text = "A empresa vinculada ao devedor permanece fixa na edição para seguir o contrato atual do backend."
        }
    }

    private func loadCompaniesIfNeeded() {
        guard needsCompanySelection else { return }
        guard case .create = mode else { return }

        loadCompaniesTask?.cancel()
        companyButton.isEnabled = false
        companyButton.configuration = makeSelectorConfiguration(title: "Carregando empresas...")

        loadCompaniesTask = Task { [weak self] in
            guard let self else { return }

            do {
                let companies = try await directoryService.listCompanies(session: session)
                await MainActor.run {
                    self.availableCompanies = companies.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    self.rebuildCompanyMenu()
                }
            } catch {
                await MainActor.run {
                    self.companyButton.isEnabled = false
                    self.companyButton.configuration = self.makeSelectorConfiguration(title: "Não foi possível carregar as empresas")
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func rebuildCompanyMenu() {
        guard needsCompanySelection else { return }

        if availableCompanies.isEmpty {
            companyButton.menu = nil
            companyButton.isEnabled = false
            companyButton.configuration = makeSelectorConfiguration(title: "Cadastre uma empresa antes")
            companyHelperLabel.text = "Não encontrei empresas disponíveis. Cadastre a empresa antes de incluir o devedor."
            return
        }

        if selectedCompanyID == nil, availableCompanies.count == 1 {
            selectedCompanyID = availableCompanies[0].id
            selectedCompanyName = availableCompanies[0].name
        }

        companyButton.menu = UIMenu(children: availableCompanies.map { company in
            UIAction(title: company.name, state: company.id == selectedCompanyID ? .on : .off) { [weak self] _ in
                self?.selectedCompanyID = company.id
                self?.selectedCompanyName = company.name
                self?.companyButton.configuration = self?.makeSelectorConfiguration(title: company.name)
                self?.rebuildCompanyMenu()
            }
        })
        companyButton.isEnabled = true
        companyButton.configuration = makeSelectorConfiguration(title: selectedCompanyName ?? "Selecione a empresa")
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let input = currentFormInput()
        if let validationMessage = validate(input) {
            showSimpleToast(validationMessage, style: .error)
            return
        }

        navigationItem.rightBarButtonItem?.isEnabled = false
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }

            do {
                let saved: PortalDebtorRecord
                switch mode {
                case .create:
                    saved = try await directoryService.createDebtor(session: session, input: input)
                case let .edit(debtor):
                    saved = try await directoryService.updateDebtor(session: session, debtorID: debtor.id, input: input)
                }

                await MainActor.run {
                    self.onSave?(saved)
                    self.dismiss(animated: true)
                }
            } catch {
                await MainActor.run {
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    @objc private func documentChanged() {
        guard documentField.isEnabled else { return }
        documentField.text = Formatters.formatCPFOrCNPJ(documentField.text ?? "")
    }

    @objc private func phoneChanged() {
        phoneField.text = formatPhone(phoneField.text ?? "")
    }

    @objc private func cepChanged() {
        cepField.text = Formatters.formatCEP(cepField.text ?? "")
        if Formatters.digitsOnly(cepField.text ?? "").count < 8 {
            clearAddressPreview()
        }
    }

    @objc private func lookupCEP() {
        let digits = Formatters.digitsOnly(cepField.text ?? "")
        guard digits.count == 8 else {
            showSimpleToast("Informe um CEP válido com 8 dígitos.", style: .error)
            return
        }

        cepLookupTask?.cancel()
        cepLookupButton.isEnabled = false
        cepLookupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await actionsService.fetchAddressPreview(cep: digits)
                await MainActor.run {
                    self.cepLookupButton.isEnabled = true
                    self.applyAddressPreview(preview)
                }
            } catch {
                await MainActor.run {
                    self.cepLookupButton.isEnabled = true
                    self.clearAddressPreview()
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func currentFormInput() -> PortalDebtorFormInput {
        PortalDebtorFormInput(
            companyID: needsCompanySelection ? selectedCompanyID : session.empresaID,
            name: nameField.text ?? "",
            document: documentField.text ?? "",
            email: emailField.text ?? "",
            phone: phoneField.text ?? "",
            cep: cepField.text ?? "",
            number: numberField.text ?? "",
            complement: complementField.text?.nilIfEmpty
        )
    }

    private func validate(_ input: PortalDebtorFormInput) -> String? {
        if needsCompanySelection && input.companyID?.nilIfEmpty == nil {
            return "Selecione a empresa responsável pelo devedor."
        }
        if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Informe o nome do devedor."
        }
        if Formatters.digitsOnly(input.document).count < 11 {
            return "Informe um CPF/CNPJ válido do devedor."
        }
        if input.email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") == false {
            return "Informe um e-mail válido do devedor."
        }
        if Formatters.digitsOnly(input.phone).count < 10 {
            return "Informe um telefone válido do devedor."
        }
        if Formatters.digitsOnly(input.cep).count != 8 {
            return "Informe um CEP válido do devedor."
        }
        if input.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Informe o número do endereço do devedor."
        }
        return nil
    }

    private func makeAddressCard() -> UIView {
        let cepRow = UIStackView(arrangedSubviews: [cepField, cepLookupButton])
        cepRow.axis = .horizontal
        cepRow.spacing = 10
        cepLookupButton.translatesAutoresizingMaskIntoConstraints = false
        cepLookupButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        cepLookupButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let numberComplementRow = UIStackView(arrangedSubviews: [numberField, complementField])
        numberComplementRow.axis = .horizontal
        numberComplementRow.spacing = 10
        numberComplementRow.distribution = .fillEqually

        return makeSectionCard(title: "Endereço", rows: [
            makeLabeledField(title: "CEP", field: cepRow),
            addressPreviewCard,
            makeLabeledField(title: "Número e Complemento", field: numberComplementRow)
        ])
    }

    private func makeSectionCard(title: String, rows: [UIView]) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(hex: "#F8FAFC")
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        card.addSubview(stack)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)
        stack.addArrangedSubview(titleLabel)
        rows.forEach { row in
            if row is UILabel {
                stack.addArrangedSubview(row)
            } else {
                stack.addArrangedSubview(row)
            }
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeLabeledField(title: String, field: UIView) -> UIView {
        let wrapper = UIStackView(arrangedSubviews: [makeFieldLabel(title), field])
        wrapper.axis = .vertical
        wrapper.spacing = 8
        return wrapper
    }

    private func makeFieldLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = UIColor(hex: "#688097")
        label.applyScaledFont(size: 13, weight: .bold, textStyle: .subheadline)
        return label
    }

    private func configureTextField(_ textField: UITextField, placeholder: String, keyboardType: UIKeyboardType, identifier: String) {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.autocorrectionType = .no
        textField.autocapitalizationType = keyboardType == .emailAddress ? .none : .words
        textField.clearButtonMode = .whileEditing
        textField.applyScaledFont(size: 16, weight: .medium, textStyle: .body)
        textField.textColor = UIColor(hex: "#283344")
        textField.backgroundColor = UIColor(hex: "#FFFFFF")
        textField.layer.cornerRadius = 14
        textField.layer.cornerCurve = .continuous
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        textField.setLeftPadding(14)
        textField.setPlaceholderColor(UIColor(hex: "#8AA0B6"))
        textField.heightAnchor.constraint(equalToConstant: 48).isActive = true
        textField.accessibilityIdentifier = identifier
        textField.delegate = self
    }

    private func applyAddressPreview(_ preview: PortalAddressPreview) {
        addressPreview = preview
        addressPreviewTitleLabel.text = preview.logradouro
        addressPreviewSubtitleLabel.text = "\(preview.bairro) • \(preview.cidade), \(preview.estado)"
        addressPreviewCard.isHidden = false
    }

    private func clearAddressPreview() {
        addressPreview = nil
        addressPreviewCard.isHidden = true
        addressPreviewTitleLabel.text = nil
        addressPreviewSubtitleLabel.text = nil
    }

    private func formatPhone(_ value: String) -> String {
        let digits = Formatters.digitsOnly(value)
        if digits.count <= 10 {
            return DebtorDirectoryViewController.formatPhone10(digits)
        }
        return DebtorDirectoryViewController.formatPhone11(digits)
    }

    private func makeSelectorConfiguration(title: String?) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = UIColor(hex: "#607993")
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        configuration.titleAlignment = .leading
        return configuration
    }
}

private extension PortalDebtorRecord {
    var isActive: Bool {
        status.uppercased() == "ATIVO"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftView = padding
        leftViewMode = .always
    }
}
