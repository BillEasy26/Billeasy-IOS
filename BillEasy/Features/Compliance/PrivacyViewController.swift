import UIKit

/// Aqui eu espelho o fluxo LGPD do web com ações legíveis para o usuário final.
final class PrivacyViewController: UIViewController {
    private struct LocalPrivacyExportSnapshot: Encodable {
        let exportedAt: Date
        let userID: String?
        let displayName: String?
        let email: String?
        let provider: String?
        let privacySettings: LocalPrivacySettingsPayload
    }

    private struct LocalPrivacySettingsPayload: Encodable {
        let marketingEmailsEnabled: Bool
        let dataExportRequestedAt: Date?
    }

    private let session: AuthSession?
    private let dataStore: LocalAppDataStore
    private let authService: AuthService
    private let privacyService: PortalPrivacyService
    private let onAccountAnonymized: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let viewDataButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let exportStatusCard = UIView()
    private let exportStatusLabel = UILabel()

    private var isLoadingMyData = false {
        didSet { updateButtonStates() }
    }

    private var isExporting = false {
        didSet { updateButtonStates() }
    }

    private var isDeleting = false {
        didSet { updateButtonStates() }
    }

    init(
        session: AuthSession? = nil,
        dataStore: LocalAppDataStore,
        authService: AuthService = AuthService(),
        privacyService: PortalPrivacyService = PortalPrivacyService(),
        onAccountAnonymized: (() -> Void)? = nil
    ) {
        self.session = session
        self.dataStore = dataStore
        self.authService = authService
        self.privacyService = privacyService
        self.onAccountAnonymized = onAccountAnonymized
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacidade"
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        view.accessibilityIdentifier = "privacy.screen"
        setupView()
        setupLayout()
        configureNavigation()
        reloadState()
    }

    private func setupView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive

        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 18

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)

        contentStack.addArrangedSubview(
            BrandCardFactory.makeEmptyStateCard(
                title: "Seus dados e sua conta",
                subtitle: "Veja suas informações, baixe uma cópia delas e, se precisar, solicite a anonimização da conta conforme a LGPD.",
                iconSystemName: "hand.raised"
            )
        )
        contentStack.addArrangedSubview(makeViewDataCard())
        contentStack.addArrangedSubview(makeExportCard())
        contentStack.addArrangedSubview(makeForgetCard())
        contentStack.addArrangedSubview(exportStatusCard)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func configureNavigation() {
        if presentingViewController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeTapped)
            )
        }
    }

    private func makeViewDataCard() -> UIView {
        let card = makeSurfaceCard()

        let iconContainer = makeIconContainer(
            background: UIColor(hex: "#E8F2FA"),
            tint: UIColor(hex: "#2E87C8"),
            systemName: "eye"
        )

        let title = makeCardTitle("Ver meus dados")
        let subtitle = makeCardSubtitle(
            "Consulte suas informações pessoais, permissões, empresas vinculadas e histórico recente de acessos."
        )

        configureOutlinedButton(
            viewDataButton,
            title: "Ver meus dados",
            foregroundColor: UIColor(hex: "#0B7BBC"),
            borderColor: UIColor(hex: "#A8C9E3"),
            iconName: "doc.text.magnifyingglass"
        )
        viewDataButton.accessibilityIdentifier = "privacy.viewDataButton"
        viewDataButton.addTarget(self, action: #selector(viewDataTapped), for: .touchUpInside)

        return assembleActionCard(
            card: card,
            iconContainer: iconContainer,
            title: title,
            subtitle: subtitle,
            actionButton: viewDataButton
        )
    }

    private func makeExportCard() -> UIView {
        let card = makeSurfaceCard()

        let iconContainer = makeIconContainer(
            background: UIColor(hex: "#E8F2FA"),
            tint: UIColor(hex: "#2E87C8"),
            systemName: "square.and.arrow.down"
        )

        let title = makeCardTitle("Baixar meus dados")
        let subtitle = makeCardSubtitle(
            "Faça o download de uma cópia completa em JSON para guardar ou compartilhar com quem você autorizar."
        )

        configureFilledButton(
            exportButton,
            title: "Baixar arquivo JSON",
            backgroundColor: UIColor(hex: "#0B7BBC"),
            foregroundColor: .white,
            iconName: "arrow.down.doc"
        )
        exportButton.accessibilityIdentifier = "privacy.exportButton"
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        let assembled = assembleActionCard(
            card: card,
            iconContainer: iconContainer,
            title: title,
            subtitle: subtitle,
            actionButton: exportButton
        )

        exportStatusCard.backgroundColor = UIColor(hex: "#F8FAFC")
        exportStatusCard.layer.cornerRadius = 16
        exportStatusCard.layer.cornerCurve = .continuous
        exportStatusCard.layer.borderWidth = 1
        exportStatusCard.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        exportStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        exportStatusLabel.numberOfLines = 0
        exportStatusLabel.textColor = UIColor(hex: "#607993")
        exportStatusLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        exportStatusCard.addSubview(exportStatusLabel)

        NSLayoutConstraint.activate([
            exportStatusLabel.topAnchor.constraint(equalTo: exportStatusCard.topAnchor, constant: 16),
            exportStatusLabel.leadingAnchor.constraint(equalTo: exportStatusCard.leadingAnchor, constant: 16),
            exportStatusLabel.trailingAnchor.constraint(equalTo: exportStatusCard.trailingAnchor, constant: -16),
            exportStatusLabel.bottomAnchor.constraint(equalTo: exportStatusCard.bottomAnchor, constant: -16)
        ])

        return assembled
    }

    private func makeForgetCard() -> UIView {
        let card = makeSurfaceCard(
            background: UIColor(hex: "#FFF7F7"),
            border: UIColor(hex: "#F4C6C6")
        )

        let iconContainer = makeIconContainer(
            background: UIColor(hex: "#FFE8E8"),
            tint: UIColor(hex: "#C94D5D"),
            systemName: "person.crop.circle.badge.xmark"
        )

        let title = makeCardTitle("Excluir minha conta")
        let subtitle = makeCardSubtitle(
            "Se você não quiser mais usar o Billeasy.ia, podemos anonimizar seus dados e encerrar sua conta conforme a LGPD."
        )

        let warningCard = UIView()
        warningCard.translatesAutoresizingMaskIntoConstraints = false
        warningCard.backgroundColor = UIColor(hex: "#FFF8E7")
        warningCard.layer.cornerRadius = 12
        warningCard.layer.cornerCurve = .continuous
        warningCard.layer.borderWidth = 1
        warningCard.layer.borderColor = UIColor(hex: "#F0DCA5").cgColor

        let warningLabel = UILabel()
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.numberOfLines = 0
        warningLabel.text = "Essa ação é definitiva. Seus dados serão anonimizados, sua sessão será encerrada e a conta deixará de poder ser usada."
        warningLabel.textColor = UIColor(hex: "#8B5E14")
        warningLabel.applyScaledFont(size: 13, weight: .semibold, textStyle: .callout)
        warningCard.addSubview(warningLabel)

        configureOutlinedButton(
            deleteButton,
            title: "Continuar para exclusão",
            foregroundColor: UIColor(hex: "#C94D5D"),
            borderColor: UIColor(hex: "#E69AA5"),
            iconName: "trash"
        )
        deleteButton.accessibilityIdentifier = "privacy.deleteAccountButton"
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        card.addSubview(iconContainer)
        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(warningCard)
        card.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            warningCard.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            warningCard.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            warningCard.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            warningLabel.topAnchor.constraint(equalTo: warningCard.topAnchor, constant: 12),
            warningLabel.leadingAnchor.constraint(equalTo: warningCard.leadingAnchor, constant: 12),
            warningLabel.trailingAnchor.constraint(equalTo: warningCard.trailingAnchor, constant: -12),
            warningLabel.bottomAnchor.constraint(equalTo: warningCard.bottomAnchor, constant: -12),

            deleteButton.topAnchor.constraint(equalTo: warningCard.bottomAnchor, constant: 14),
            deleteButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            deleteButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            deleteButton.heightAnchor.constraint(equalToConstant: 48),
            deleteButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makeSurfaceCard(
        background: UIColor = UIColor(hex: "#F8FAFC"),
        border: UIColor = UIColor(hex: "#D7DEE8")
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = background
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor
        return card
    }

    private func makeCardTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor(hex: "#283344")
        label.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)
        return label
    }

    private func makeCardSubtitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = text
        label.textColor = UIColor(hex: "#6E7F95")
        label.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        return label
    }

    private func assembleActionCard(
        card: UIView,
        iconContainer: UIView,
        title: UILabel,
        subtitle: UILabel,
        actionButton: UIButton
    ) -> UIView {
        card.addSubview(iconContainer)
        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(actionButton)

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            actionButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            actionButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            actionButton.heightAnchor.constraint(equalToConstant: 48),
            actionButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makeIconContainer(background: UIColor, tint: UIColor, systemName: String) -> UIView {
        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = background
        iconContainer.layer.cornerRadius = 18
        iconContainer.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36)
        ])

        let imageView = UIImageView(image: UIImage(systemName: systemName))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = tint
        iconContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        return iconContainer
    }

    private func configureFilledButton(
        _ button: UIButton,
        title: String,
        backgroundColor: UIColor,
        foregroundColor: UIColor,
        iconName: String
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = backgroundColor
        configuration.baseForegroundColor = foregroundColor
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: iconName)
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18)
        configuration.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.billeasyScaledFont(size: 16, weight: .bold, textStyle: .headline)])
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
    }

    private func configureOutlinedButton(
        _ button: UIButton,
        title: String,
        foregroundColor: UIColor,
        borderColor: UIColor,
        iconName: String
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = foregroundColor
        configuration.image = UIImage(systemName: iconName)
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18)
        configuration.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.billeasyScaledFont(size: 15, weight: .bold, textStyle: .headline)])
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 2
        button.layer.borderColor = borderColor.cgColor
    }

    private func reloadState() {
        let settings = dataStore.fetchPrivacySettings()
        if let exportDate = settings.dataExportRequestedAt {
            exportStatusLabel.text = "Último download registrado neste aparelho: \(Formatters.dateTime.string(from: exportDate))"
        } else {
            exportStatusLabel.text = "Você ainda não baixou uma cópia dos seus dados neste aparelho. Quando tocar no botão acima, o arquivo será preparado para você."
        }
        exportStatusCard.accessibilityIdentifier = "privacy.exportStatusCard"
        exportStatusCard.isAccessibilityElement = true
        exportStatusCard.accessibilityLabel = "Status do download dos seus dados"
        exportStatusCard.accessibilityValue = exportStatusLabel.text
        updateButtonStates()
    }

    private func updateButtonStates() {
        let controlsEnabled = isLoadingMyData == false && isExporting == false && isDeleting == false
        viewDataButton.isEnabled = controlsEnabled
        exportButton.isEnabled = controlsEnabled
        deleteButton.isEnabled = controlsEnabled

        var viewConfig = viewDataButton.configuration
        viewConfig?.showsActivityIndicator = isLoadingMyData
        viewConfig?.image = isLoadingMyData ? nil : UIImage(systemName: "doc.text.magnifyingglass")
        viewConfig?.attributedTitle = AttributedString(
            isLoadingMyData ? "Abrindo seus dados..." : "Ver meus dados",
            attributes: AttributeContainer([.font: UIFont.billeasyScaledFont(size: 15, weight: .bold, textStyle: .headline)])
        )
        viewDataButton.configuration = viewConfig

        var exportConfig = exportButton.configuration
        exportConfig?.showsActivityIndicator = isExporting
        exportConfig?.image = isExporting ? nil : UIImage(systemName: "arrow.down.doc")
        exportConfig?.attributedTitle = AttributedString(
            isExporting ? "Preparando arquivo..." : "Baixar arquivo JSON",
            attributes: AttributeContainer([.font: UIFont.billeasyScaledFont(size: 16, weight: .bold, textStyle: .headline)])
        )
        exportButton.configuration = exportConfig

        var deleteConfig = deleteButton.configuration
        deleteConfig?.showsActivityIndicator = isDeleting
        deleteConfig?.image = isDeleting ? nil : UIImage(systemName: "trash")
        deleteConfig?.attributedTitle = AttributedString(
            isDeleting ? "Encerrando sua conta..." : "Continuar para exclusão",
            attributes: AttributeContainer([.font: UIFont.billeasyScaledFont(size: 15, weight: .bold, textStyle: .headline)])
        )
        deleteButton.configuration = deleteConfig
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func viewDataTapped() {
        guard isLoadingMyData == false, isExporting == false, isDeleting == false else { return }
        isLoadingMyData = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let export = try await self.resolveMyDataPreview()
                await MainActor.run {
                    self.presentDataPreview(export)
                    self.isLoadingMyData = false
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                    self.isLoadingMyData = false
                }
            }
        }
    }

    @objc private func exportTapped() {
        guard isExporting == false, isLoadingMyData == false, isDeleting == false else { return }
        isExporting = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let fileURL = try await self.resolveExportFileURL()
                await MainActor.run {
                    self.dataStore.requestDataExport()
                    self.reloadState()
                    self.presentExportSheet(fileURL: fileURL)
                    self.isExporting = false
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                    self.isExporting = false
                }
            }
        }
    }

    @objc private func deleteTapped() {
        guard isDeleting == false, isLoadingMyData == false, isExporting == false else { return }
        presentDeletionWarning()
    }

    private func presentDeletionWarning() {
        let alert = UIAlertController(
            title: "Excluir conta",
            message: "Seus dados serão anonimizados e você será desconectado. Essa ação é definitiva.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Agora não", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continuar", style: .destructive, handler: { [weak self] _ in
            self?.presentDeletionConfirmationPrompt()
        }))

        present(alert, animated: true)
    }

    private func presentDeletionConfirmationPrompt(prefilledReason: String = "") {
        let alert = UIAlertController(
            title: "Confirme sua solicitação",
            message: "Para sua segurança, digite EXCLUIR MINHA CONTA. Se quiser, informe também um motivo.",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "EXCLUIR MINHA CONTA"
            textField.autocapitalizationType = .allCharacters
            textField.accessibilityIdentifier = "privacy.confirmDeletionField"
        }

        alert.addTextField { textField in
            textField.placeholder = "Motivo (opcional)"
            textField.text = prefilledReason
            textField.accessibilityIdentifier = "privacy.deletionReasonField"
        }

        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Concluir exclusão", style: .destructive, handler: { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let confirmation = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let reason = alert.textFields?.dropFirst().first?.text ?? ""

            guard confirmation == "EXCLUIR MINHA CONTA" else {
                self.showSimpleToast("Digite EXCLUIR MINHA CONTA para continuar.", style: .error)
                self.presentDeletionConfirmationPrompt(prefilledReason: reason)
                return
            }

            self.performAccountAnonymization(reason: reason)
        }))

        present(alert, animated: true)
    }

    private func performAccountAnonymization(reason: String) {
        guard isDeleting == false else { return }
        isDeleting = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let successMessage: String
                if self.privacyService.isRemoteMode {
                    let result = try await self.privacyService.anonymizeMyAccount(reason: reason)
                    successMessage = result.mensagem?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? (result.mensagem ?? "Sua conta foi anonimizada. Você será desconectado.")
                        : "Sua conta foi anonimizada. Você será desconectado."
                } else {
                    LocalAuthStore().anonymizeCurrentAccount(reason: reason)
                    successMessage = "Sua conta foi anonimizada. A sessão será encerrada agora."
                }

                self.authService.logout()

                await MainActor.run {
                    self.presentDeletionSuccessAlert(message: successMessage)
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                    self.isDeleting = false
                }
            }
        }
    }

    private func presentDeletionSuccessAlert(message: String) {
        let alert = UIAlertController(
            title: "Solicitação concluída",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.isDeleting = false
            if let onAccountAnonymized = self.onAccountAnonymized {
                onAccountAnonymized()
            } else {
                self.dismiss(animated: true)
            }
        }))

        present(alert, animated: true)
    }

    private func resolveMyDataPreview() async throws -> PortalPrivacyService.MyDataExport {
        if privacyService.isRemoteMode {
            return try await privacyService.fetchMyData()
        }

        return buildLocalMyDataPreview()
    }

    private func buildLocalMyDataPreview() -> PortalPrivacyService.MyDataExport {
        PortalPrivacyService.MyDataExport(
            dataExportacao: Date(),
            usuarioId: currentSession?.userID,
            dadosPessoais: .init(
                nome: currentSession?.displayName,
                email: currentSession?.email,
                telefone: nil,
                cpfCnpjEnc: nil,
                status: "ATIVO",
                mfaHabilitado: false,
                criadoEm: nil,
                atualizadoEm: nil
            ),
            papeis: ["USUARIO"],
            permissoes: [],
            empresas: [],
            historicoAuditoria: []
        )
    }

    private func resolveExportFileURL() async throws -> URL {
        if privacyService.isRemoteMode {
            return try await privacyService.downloadMyData()
        }

        let export = LocalPrivacyExportSnapshot(
            exportedAt: Date(),
            userID: currentSession?.userID,
            displayName: currentSession?.displayName,
            email: currentSession?.email,
            provider: currentSession?.provider.rawValue,
            privacySettings: LocalPrivacySettingsPayload(
                marketingEmailsEnabled: dataStore.fetchPrivacySettings().marketingEmailsEnabled,
                dataExportRequestedAt: dataStore.fetchPrivacySettings().dataExportRequestedAt
            )
        )

        let data = try JSONEncoder().encode(export)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meus-dados-lgpd-local")
            .appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private var currentSession: AuthSession? {
        session ?? authService.currentSession()
    }

    private func presentDataPreview(_ export: PortalPrivacyService.MyDataExport) {
        let controller = PrivacyDataPreviewViewController(
            export: export,
            onDownloadRequested: { [weak self] in
                self?.exportTapped()
            }
        )
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    private func presentExportSheet(fileURL: URL) {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        present(controller, animated: true)
    }
}

private final class PrivacyDataPreviewViewController: UIViewController {
    private let export: PortalPrivacyService.MyDataExport
    private let onDownloadRequested: (() -> Void)?
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let downloadButton = UIButton(type: .system)

    init(
        export: PortalPrivacyService.MyDataExport,
        onDownloadRequested: (() -> Void)? = nil
    ) {
        self.export = export
        self.onDownloadRequested = onDownloadRequested
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Meus dados"
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        view.accessibilityIdentifier = "privacy.dataPreview.screen"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "privacy.dataPreview.closeButton"
        setupView()
        setupLayout()
    }

    private func setupView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)

        contentStack.addArrangedSubview(makeSummaryCard())
        contentStack.addArrangedSubview(makePersonalDataCard())

        if let papeis = export.papeis, papeis.isEmpty == false {
            contentStack.addArrangedSubview(makeBadgeCard(title: "Papéis", values: papeis))
        }

        if let permissoes = export.permissoes, permissoes.isEmpty == false {
            contentStack.addArrangedSubview(makeBadgeCard(title: "Permissões", values: permissoes))
        }

        if let empresas = export.empresas, empresas.isEmpty == false {
            contentStack.addArrangedSubview(makeCompaniesCard(empresas))
        }

        if let auditoria = export.historicoAuditoria, auditoria.isEmpty == false {
            contentStack.addArrangedSubview(makeAuditCard(auditoria))
        }

        configureDownloadButton()
        contentStack.addArrangedSubview(downloadButton)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func makeSummaryCard() -> UIView {
        let card = makeCard()
        let title = makeTitle("Resumo da exportação")
        let subtitle = makeBody(
            export.dataExportacao != nil
                ? "Dados gerados em \(Formatters.dateTime.string(from: export.dataExportacao!))."
                : "Estes são os dados pessoais atualmente vinculados à sua conta."
        )
        card.addSubview(title)
        card.addSubview(subtitle)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            subtitle.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makePersonalDataCard() -> UIView {
        let card = makeCard()
        let stack = makeSectionStack(title: "Dados pessoais")
        let data = export.dadosPessoais

        stack.addArrangedSubview(makeRow(label: "Nome", value: data?.nome ?? "-"))
        stack.addArrangedSubview(makeRow(label: "E-mail", value: data?.email ?? "-"))
        stack.addArrangedSubview(makeRow(label: "Telefone", value: data?.telefone ?? "-"))
        stack.addArrangedSubview(makeRow(label: "Status", value: data?.status ?? "-"))
        stack.addArrangedSubview(makeRow(label: "MFA", value: (data?.mfaHabilitado ?? false) ? "Habilitado" : "Desabilitado"))
        stack.addArrangedSubview(makeRow(label: "Criado em", value: formatted(date: data?.criadoEm)))

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func makeCompaniesCard(_ companies: [PortalPrivacyService.MyDataExport.CompanySummary]) -> UIView {
        let card = makeCard()
        let stack = makeSectionStack(title: "Empresas vinculadas")

        for company in companies {
            let item = makeBody("\(company.nome ?? "Empresa") • \(company.tipo ?? "-")\n\(company.cpfCnpj ?? "-")")
            stack.addArrangedSubview(item)
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func makeAuditCard(_ events: [PortalPrivacyService.MyDataExport.AuditEvent]) -> UIView {
        let card = makeCard()
        let stack = makeSectionStack(title: "Acessos recentes")

        for event in events.prefix(10) {
            let line = [event.acao, event.entidade].compactMap { $0 }.joined(separator: " • ")
            let item = makeBody("\(line.isEmpty ? "Evento" : line)\n\(formatted(date: event.data)) • IP: \(event.ip ?? "-")")
            stack.addArrangedSubview(item)
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func makeBadgeCard(title: String, values: [String]) -> UIView {
        let card = makeCard()
        let stack = makeSectionStack(title: title)
        let valuesLabel = makeBody(values.joined(separator: " • "))
        stack.addArrangedSubview(valuesLabel)
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(hex: "#F8FAFC")
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        return card
    }

    private func makeSectionStack(title: String) -> UIStackView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.addArrangedSubview(makeTitle(title))
        return stack
    }

    private func makeTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor(hex: "#283344")
        label.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)
        return label
    }

    private func makeBody(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = text
        label.textColor = UIColor(hex: "#607993")
        label.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        return label
    }

    private func makeRow(label: String, value: String) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 4

        let labelView = UILabel()
        labelView.text = label
        labelView.textColor = UIColor(hex: "#607993")
        labelView.applyScaledFont(size: 12, weight: .semibold, textStyle: .caption1)

        let valueView = UILabel()
        valueView.numberOfLines = 0
        valueView.text = value
        valueView.textColor = UIColor(hex: "#283344")
        valueView.applyScaledFont(size: 15, weight: .medium, textStyle: .body)

        container.addArrangedSubview(labelView)
        container.addArrangedSubview(valueView)
        return container
    }

    private func configureDownloadButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor(hex: "#0B7BBC")
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "arrow.down.doc")
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18)
        configuration.attributedTitle = AttributedString(
            "Baixar cópia em JSON",
            attributes: AttributeContainer([.font: UIFont.billeasyScaledFont(size: 16, weight: .bold, textStyle: .headline)])
        )
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.configuration = configuration
        downloadButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        downloadButton.accessibilityIdentifier = "privacy.dataPreview.downloadButton"
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
    }

    private func formatted(date: Date?) -> String {
        guard let date else { return "-" }
        return Formatters.dateTime.string(from: date)
    }

    @objc private func downloadTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDownloadRequested?()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
