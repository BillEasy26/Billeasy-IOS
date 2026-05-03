//
//  ProfileViewController.swift
//  BillEasy
//

import UIKit
import PhotosUI

/// Aqui eu concentro a tela de perfil e identidade combinando persistência local com sincronização remota.
final class ProfileViewController: UIViewController, UITextFieldDelegate, PHPickerViewControllerDelegate {
    /// Aqui eu salvo apenas os campos editaveis da tela de identidade.
    private struct IdentitySnapshot: Codable {
        var fullName: String
        var email: String
        var phone: String
        var document: String
    }

    /// Aqui eu descrevo cada campo de identidade em um unico lugar para reduzir configuracao repetida.
    private struct IdentityFieldConfiguration {
        let title: String
        let field: UITextField
        let placeholder: String
        let icon: String?
        let keyboardType: UIKeyboardType
        let autocapitalizationType: UITextAutocapitalizationType
        let returnKeyType: UIReturnKeyType
        let accessibilityIdentifier: String
    }

    private let session: AuthSession
    private let dataStore: LocalAppDataStore
    private let defaults: UserDefaults
    private let portalService: PortalDataService
    private let actionsService: PortalActionsService
    private let identityKeyPrefix = "billeasy.profile.identity.v1"
    private let photoKeyPrefix = "billeasy.profile.photo.attachment.v1"
    private let bottomActionSafeInset: CGFloat = 108

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stack = UIStackView()

    private let avatarImageView = UIImageView()
    private let avatarFallbackLabel = UILabel()
    private let changePhotoButton = UIButton(type: .system)
    private let fullNameField = UITextField()
    private let emailField = UITextField()
    private let phoneField = UITextField()
    private let documentField = UITextField()
    private let identityCard = UIView()
    private let identityContentStack = UIStackView()
    private let identityDisclosureButton = UIButton(type: .system)
    private let identityChevronImageView = UIImageView()
    private var identityContentCollapsedConstraint: NSLayoutConstraint?
    private let saveButton = UIButton(type: .system)
    private let changePasswordButton = UIButton(type: .system)
    private let privacyButton = UIButton(type: .system)

    private var photoRefreshTask: Task<Void, Never>?
    private var photoUploadTask: Task<Void, Never>?
    private var socialPhotoImportTask: Task<Void, Never>?
    private var isIdentityExpanded = false

    /// Aqui eu mantenho a ordem de foco oficial do formulario para teclado e acessibilidade.
    private lazy var orderedFields: [UITextField] = [
        fullNameField,
        emailField,
        phoneField,
        documentField
    ]

    /// Aqui eu concentro a definicao visual e comportamental de cada campo do formulario.
    private lazy var fieldConfigurations: [IdentityFieldConfiguration] = [
        IdentityFieldConfiguration(
            title: "Nome Completo",
            field: fullNameField,
            placeholder: "Seu nome completo",
            icon: nil,
            keyboardType: .default,
            autocapitalizationType: .words,
            returnKeyType: .next,
            accessibilityIdentifier: "profile.fullNameField"
        ),
        IdentityFieldConfiguration(
            title: "Email",
            field: emailField,
            placeholder: "seu@email.com",
            icon: "envelope",
            keyboardType: .emailAddress,
            autocapitalizationType: .none,
            returnKeyType: .next,
            accessibilityIdentifier: "profile.emailField"
        ),
        IdentityFieldConfiguration(
            title: "Telefone",
            field: phoneField,
            placeholder: "(00) 00000-0000",
            icon: "phone",
            keyboardType: .numberPad,
            autocapitalizationType: .none,
            returnKeyType: .next,
            accessibilityIdentifier: "profile.phoneField"
        ),
        IdentityFieldConfiguration(
            title: "CPF/CNPJ",
            field: documentField,
            placeholder: "000.000.000-00",
            icon: "doc.text",
            keyboardType: .numberPad,
            autocapitalizationType: .none,
            returnKeyType: .done,
            accessibilityIdentifier: "profile.documentField"
        )
    ]

    init(
        session: AuthSession,
        dataStore: LocalAppDataStore,
        defaults: UserDefaults = .standard,
        portalService: PortalDataService = PortalDataService(),
        actionsService: PortalActionsService = PortalActionsService()
    ) {
        self.session = session
        self.dataStore = dataStore
        self.defaults = defaults
        self.portalService = portalService
        self.actionsService = actionsService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        photoRefreshTask?.cancel()
        photoUploadTask?.cancel()
        socialPhotoImportTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        loadIdentity()
        loadCachedProfilePhoto()
        importGoogleProfilePhotoIfNeeded(uploadToRemoteWhenMissing: false)
        refreshRemoteIdentityIfNeeded()
        refreshRemoteProfilePhotoIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ensureIdentityFieldsInteractive()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ensureIdentityFieldsInteractive()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateScrollInsets()
    }

    /// Aqui eu monto a estrutura principal da tela e deixo a configuracao dos campos centralizada.
    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        view.accessibilityIdentifier = "profile.screen"

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

        contentView.translatesAutoresizingMaskIntoConstraints = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14

        configureIdentityFields()

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)

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
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: 1),

            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        stack.addArrangedSubview(makeTopTitleStrip())

        let body = UIView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.backgroundColor = UIColor(hex: "#E6EAEE")

        let bodyStack = UIStackView()
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.axis = .vertical
        bodyStack.spacing = 14

        body.addSubview(bodyStack)
        NSLayoutConstraint.activate([
            bodyStack.topAnchor.constraint(equalTo: body.topAnchor, constant: 12),
            bodyStack.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 12),
            bodyStack.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -12),
            bodyStack.bottomAnchor.constraint(equalTo: body.bottomAnchor)
        ])

        bodyStack.addArrangedSubview(makeHeroSection())
        bodyStack.addArrangedSubview(makeProfilePhotoCard())
        bodyStack.addArrangedSubview(makeIdentityCard())
        bodyStack.addArrangedSubview(makeSecurityActionsCard())

        stack.addArrangedSubview(body)
        applyIdentityExpansion(animated: false)
        updateScrollInsets()
    }

    /// Aqui eu reservo uma folga fixa acima da barra inferior para que os últimos botões nunca fiquem escondidos.
    private func updateScrollInsets() {
        let bottomInset = bottomActionSafeInset + view.safeAreaInsets.bottom
        if scrollView.contentInset.bottom != bottomInset {
            scrollView.contentInset.bottom = bottomInset
            scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        }
    }

    /// Aqui eu crio a faixa superior fixa que identifica claramente em qual tela o usuario esta.
    private func makeTopTitleStrip() -> UIView {
        let strip = UIView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.backgroundColor = UIColor(hex: "#F8FAFC")

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Perfil"
        title.textColor = UIColor(hex: "#252E3A")
        title.applyScaledFont(size: 33, weight: .bold, textStyle: .largeTitle)
        title.accessibilityTraits.insert(.header)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(hex: "#D7DEE8")

        strip.addSubview(title)
        strip.addSubview(separator)

        NSLayoutConstraint.activate([
            strip.heightAnchor.constraint(equalToConstant: 66),

            title.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: strip.centerYAnchor, constant: 2),

            separator.leadingAnchor.constraint(equalTo: strip.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: strip.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: strip.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])

        return strip
    }

    /// Aqui eu monto o bloco de contexto da tela com titulo, descricao e nivel atual.
    private func makeHeroSection() -> UIView {
        let section = UIView()
        section.backgroundColor = UIColor(hex: "#DEE3E8")

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Perfil e Identidade"
        title.textColor = UIColor(hex: "#2A3442")
        title.applyScaledFont(size: 48, weight: .bold, textStyle: .largeTitle)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.64

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Gerencie seus dados pessoais e configurações de segurança"
        subtitle.textColor = UIColor(hex: "#607993")
        subtitle.applyScaledFont(size: 16, weight: .medium, textStyle: .body)
        subtitle.numberOfLines = 0

        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = "Básico"
        badge.textAlignment = .center
        badge.textColor = UIColor(hex: "#0B7BBC")
        badge.applyScaledFont(size: 14, weight: .semibold, textStyle: .caption1)
        badge.backgroundColor = UIColor(hex: "#D6EAF9")
        badge.layer.cornerRadius = 16
        badge.layer.masksToBounds = true

        section.addSubview(title)
        section.addSubview(subtitle)
        section.addSubview(badge)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: section.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            badge.topAnchor.constraint(equalTo: section.topAnchor, constant: 16),
            badge.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            badge.widthAnchor.constraint(equalToConstant: 66),
            badge.heightAnchor.constraint(equalToConstant: 32),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            subtitle.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: -14)
        ])

        return section
    }

    /// Aqui eu exponho a foto de perfil em um card próprio para não misturar upload com os campos textuais.
    private func makeProfilePhotoCard() -> UIView {
        let card = makeInfoCard()

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14

        let avatarContainer = UIView()
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.backgroundColor = UIColor(hex: "#D6EAF9")
        avatarContainer.layer.cornerRadius = 34
        avatarContainer.layer.masksToBounds = true

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isHidden = true

        avatarFallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarFallbackLabel.textColor = UIColor(hex: "#0B7BBC")
        avatarFallbackLabel.textAlignment = .center
        avatarFallbackLabel.applyScaledFont(size: 26, weight: .bold, textStyle: .title2)

        avatarContainer.addSubview(avatarImageView)
        avatarContainer.addSubview(avatarFallbackLabel)

        let textStack = UIStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Foto de Perfil"
        title.textColor = UIColor(hex: "#2A3442")
        title.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.numberOfLines = 0
        subtitle.text = "Use a biblioteca do iPhone para enviar e sincronizar sua foto com a conta."
        subtitle.textColor = UIColor(hex: "#607993")
        subtitle.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(subtitle)

        changePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        changePhotoButton.setTitle(" Alterar foto", for: .normal)
        changePhotoButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        changePhotoButton.setTitleColor(UIColor(hex: "#0B7BBC"), for: .normal)
        changePhotoButton.tintColor = UIColor(hex: "#0B7BBC")
        changePhotoButton.backgroundColor = UIColor(hex: "#EAF4FC")
        changePhotoButton.layer.cornerRadius = 10
        changePhotoButton.applyScaledTitleFont(size: 15, weight: .bold, textStyle: .headline)
        changePhotoButton.accessibilityIdentifier = "profile.changePhotoButton"
        changePhotoButton.accessibilityHint = "Abre o seletor nativo de fotos para trocar a foto do perfil."
        changePhotoButton.addTarget(self, action: #selector(changePhotoTapped), for: .touchUpInside)

        row.addArrangedSubview(avatarContainer)
        row.addArrangedSubview(textStack)

        card.addSubview(row)
        card.addSubview(changePhotoButton)

        NSLayoutConstraint.activate([
            avatarContainer.widthAnchor.constraint(equalToConstant: 68),
            avatarContainer.heightAnchor.constraint(equalToConstant: 68),

            avatarImageView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),

            avatarFallbackLabel.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            avatarFallbackLabel.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),

            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            changePhotoButton.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 12),
            changePhotoButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            changePhotoButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            changePhotoButton.heightAnchor.constraint(equalToConstant: 44),
            changePhotoButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        updateAvatarFallback()
        return card
    }

    /// Aqui eu construo o card principal de identidade reaproveitando a lista de campos configurados.
    private func makeIdentityCard() -> UIView {
        identityCard.backgroundColor = UIColor(hex: "#F7FAFD")
        identityCard.isUserInteractionEnabled = true
        identityCard.layer.cornerRadius = 12
        identityCard.layer.borderWidth = 1
        identityCard.layer.borderColor = UIColor(hex: "#D1DAE6").cgColor

        let iconBackground = UIView()
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = UIColor(hex: "#E0EDF8")
        iconBackground.layer.cornerRadius = 14

        let icon = UIImageView(image: UIImage(systemName: "person"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#0B7BBC")

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Configuração de Identidade"
        title.textColor = UIColor(hex: "#2A3442")
        title.applyScaledFont(size: 21, weight: .bold, textStyle: .title3)

        let fieldGroups = fieldConfigurations.map { configuration in
            makeFieldGroup(title: configuration.title, field: configuration.field)
        }
        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Toque para visualizar os dados da conta e salvar alterações no servidor."
        subtitle.numberOfLines = 0
        subtitle.textColor = UIColor(hex: "#607993")
        subtitle.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        let titleStack = UIStackView(arrangedSubviews: [title, subtitle])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical
        titleStack.spacing = 4

        identityChevronImageView.translatesAutoresizingMaskIntoConstraints = false
        identityChevronImageView.tintColor = UIColor(hex: "#607993")
        identityChevronImageView.contentMode = .scaleAspectFit

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        identityDisclosureButton.translatesAutoresizingMaskIntoConstraints = false
        identityDisclosureButton.backgroundColor = .clear
        identityDisclosureButton.accessibilityIdentifier = "profile.identityToggleButton"
        identityDisclosureButton.accessibilityLabel = "Configuração de Identidade"
        identityDisclosureButton.accessibilityHint = "Mostra ou oculta os dados de identidade da conta."
        identityDisclosureButton.addTarget(self, action: #selector(toggleIdentitySection), for: .touchUpInside)

        let saveContainer = UIView()
        saveContainer.translatesAutoresizingMaskIntoConstraints = false

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.setTitle(" Salvar Alterações", for: .normal)
        saveButton.setImage(UIImage(systemName: "tray.and.arrow.down"), for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.tintColor = .white
        saveButton.applyScaledTitleFont(size: 16, weight: .bold, textStyle: .headline)
        saveButton.backgroundColor = UIColor(hex: "#0B7BBC")
        saveButton.layer.cornerRadius = 10
        saveButton.accessibilityIdentifier = "profile.saveButton"
        saveButton.accessibilityHint = "Salva as alterações do perfil no servidor."
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        saveContainer.addSubview(saveButton)
        NSLayoutConstraint.activate([
            saveButton.topAnchor.constraint(equalTo: saveContainer.topAnchor),
            saveButton.leadingAnchor.constraint(equalTo: saveContainer.leadingAnchor),
            saveButton.trailingAnchor.constraint(equalTo: saveContainer.trailingAnchor),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
            saveButton.bottomAnchor.constraint(equalTo: saveContainer.bottomAnchor)
        ])

        identityContentStack.translatesAutoresizingMaskIntoConstraints = false
        identityContentStack.axis = .vertical
        identityContentStack.spacing = 12
        identityContentStack.isUserInteractionEnabled = true
        identityContentStack.clipsToBounds = true
        fieldGroups.forEach { identityContentStack.addArrangedSubview($0) }
        identityContentStack.addArrangedSubview(saveContainer)

        identityCard.addSubview(header)
        header.addSubview(iconBackground)
        iconBackground.addSubview(icon)
        header.addSubview(titleStack)
        header.addSubview(identityChevronImageView)
        header.addSubview(identityDisclosureButton)
        identityCard.addSubview(identityContentStack)

        identityContentCollapsedConstraint = identityContentStack.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: identityCard.topAnchor),
            header.leadingAnchor.constraint(equalTo: identityCard.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: identityCard.trailingAnchor),

            iconBackground.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            iconBackground.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            iconBackground.widthAnchor.constraint(equalToConstant: 28),
            iconBackground.heightAnchor.constraint(equalToConstant: 28),

            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            titleStack.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            titleStack.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
            titleStack.trailingAnchor.constraint(equalTo: identityChevronImageView.leadingAnchor, constant: -10),
            titleStack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),

            identityChevronImageView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            identityChevronImageView.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            identityChevronImageView.widthAnchor.constraint(equalToConstant: 16),
            identityChevronImageView.heightAnchor.constraint(equalToConstant: 16),

            identityDisclosureButton.topAnchor.constraint(equalTo: header.topAnchor),
            identityDisclosureButton.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            identityDisclosureButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            identityDisclosureButton.bottomAnchor.constraint(equalTo: header.bottomAnchor),

            identityContentStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            identityContentStack.leadingAnchor.constraint(equalTo: identityCard.leadingAnchor, constant: 12),
            identityContentStack.trailingAnchor.constraint(equalTo: identityCard.trailingAnchor, constant: -12),
            identityContentStack.bottomAnchor.constraint(equalTo: identityCard.bottomAnchor, constant: -14)
        ])

        return identityCard
    }

    /// Aqui eu padronizo os cards claros da tela para não repetir borda, raio e fundo.
    private func makeInfoCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(hex: "#F7FAFD")
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D1DAE6").cgColor
        return card
    }

    /// Aqui eu exponho a troca de senha em uma ação dedicada sem poluir o card principal de identidade.
    private func makeSecurityActionsCard() -> UIView {
        let card = makeInfoCard()

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Segurança"
        title.textColor = UIColor(hex: "#2A3442")
        title.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.numberOfLines = 0
        subtitle.text = "Atualize a senha da conta conectada e acesse a área de privacidade com exportação LGPD e anonimização da conta."
        subtitle.textColor = UIColor(hex: "#607993")
        subtitle.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        changePasswordButton.translatesAutoresizingMaskIntoConstraints = false
        changePasswordButton.setTitle(" Alterar Senha", for: .normal)
        changePasswordButton.setImage(UIImage(systemName: "lock.rotation"), for: .normal)
        changePasswordButton.setTitleColor(UIColor(hex: "#0B7BBC"), for: .normal)
        changePasswordButton.tintColor = UIColor(hex: "#0B7BBC")
        changePasswordButton.applyScaledTitleFont(size: 15, weight: .bold, textStyle: .headline)
        changePasswordButton.backgroundColor = UIColor(hex: "#EAF4FC")
        changePasswordButton.layer.cornerRadius = 10
        changePasswordButton.accessibilityIdentifier = "profile.changePasswordButton"
        changePasswordButton.accessibilityHint = "Abre o formulário para trocar a senha da conta no servidor."
        changePasswordButton.addTarget(self, action: #selector(changePasswordTapped), for: .touchUpInside)

        privacyButton.translatesAutoresizingMaskIntoConstraints = false
        privacyButton.setTitle(" Privacidade e Exclusão da Conta", for: .normal)
        privacyButton.setImage(UIImage(systemName: "hand.raised"), for: .normal)
        privacyButton.setTitleColor(UIColor(hex: "#0B7BBC"), for: .normal)
        privacyButton.tintColor = UIColor(hex: "#0B7BBC")
        privacyButton.applyScaledTitleFont(size: 15, weight: .bold, textStyle: .headline)
        privacyButton.backgroundColor = UIColor(hex: "#EAF4FC")
        privacyButton.layer.cornerRadius = 10
        privacyButton.accessibilityIdentifier = "profile.privacyButton"
        privacyButton.accessibilityHint = "Abre a tela de privacidade com exportação de dados e anonimização LGPD."
        privacyButton.addTarget(self, action: #selector(openPrivacyTapped), for: .touchUpInside)

        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(changePasswordButton)
        card.addSubview(privacyButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            changePasswordButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            changePasswordButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            changePasswordButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            changePasswordButton.heightAnchor.constraint(equalToConstant: 44),

            privacyButton.topAnchor.constraint(equalTo: changePasswordButton.bottomAnchor, constant: 10),
            privacyButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            privacyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            privacyButton.heightAnchor.constraint(equalToConstant: 44),
            privacyButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        return card
    }

    /// Aqui eu deixo a identidade recolhida por padrão e só exponho os dados quando a pessoa pedir.
    @objc private func toggleIdentitySection() {
        isIdentityExpanded.toggle()
        applyIdentityExpansion(animated: true)
    }

    @objc private func openPrivacyTapped() {
        let controller = PrivacyViewController(
            session: session,
            dataStore: dataStore,
            onAccountAnonymized: { [weak self] in
                self?.dismiss(animated: true)
                self?.notifyMainShellAboutAccountAnonymization()
            }
        )
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    private func notifyMainShellAboutAccountAnonymization() {
        var candidate: UIViewController? = parent
        while let current = candidate {
            if let mainTabBar = current as? MainTabBarController {
                mainTabBar.handleAccountAnonymizationCompletion()
                return
            }
            candidate = current.parent
        }
    }

    /// Aqui eu mantenho a mesma hierarquia visual nos dois estados do card sem recriar constraints.
    private func applyIdentityExpansion(animated: Bool) {
        let applyChanges = {
            self.identityContentCollapsedConstraint?.isActive = !self.isIdentityExpanded
            self.identityContentStack.isHidden = !self.isIdentityExpanded
            self.identityContentStack.alpha = self.isIdentityExpanded ? 1 : 0
            let symbolName = self.isIdentityExpanded ? "chevron.up" : "chevron.down"
            self.identityChevronImageView.image = UIImage(systemName: symbolName)
            self.identityDisclosureButton.accessibilityValue = self.isIdentityExpanded ? "Expandido" : "Recolhido"
            self.identityCard.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
                applyChanges()
            }
        } else {
            applyChanges()
        }
    }

    /// Aqui eu padronizo o grupo rotulo + campo sem duplicar layout manual.
    private func makeFieldGroup(title: String, field: UITextField) -> UIView {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = UIColor(hex: "#607993")
        label.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)

        let stack = UIStackView(arrangedSubviews: [label, field])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    /// Aqui eu aplico o estilo base do campo e, quando existir, o icone lateral correspondente.
    private func configureField(_ field: UITextField, placeholder: String, icon: String? = nil) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        field.setPlaceholderColor(UIColor(hex: "#95A9BD"))
        field.textColor = UIColor(hex: "#2A3442")
        field.tintColor = UIColor(hex: "#62C4FF")
        field.backgroundColor = UIColor(hex: "#F7FAFD")
        field.isEnabled = true
        field.isUserInteractionEnabled = true
        field.clearButtonMode = .whileEditing
        field.layer.cornerRadius = 9
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor(hex: "#C7D4E2").cgColor
        field.heightAnchor.constraint(equalToConstant: 42).isActive = true
        field.applyScaledFont(size: 16, weight: .regular, textStyle: .body)

        if let icon {
            field.leftView = makeFieldIconContainer(systemName: icon)
            field.leftViewMode = .always
        } else {
            setFieldLeftPadding(field, value: 12)
        }
    }

    /// Aqui eu centralizo a configuracao funcional dos campos para nao espalhar delegate, teclado e ids pela tela.
    private func configureIdentityFields() {
        for (index, configuration) in fieldConfigurations.enumerated() {
            let field = configuration.field
            configureField(field, placeholder: configuration.placeholder, icon: configuration.icon)
            field.keyboardType = configuration.keyboardType
            field.autocapitalizationType = configuration.autocapitalizationType
            field.returnKeyType = configuration.returnKeyType
            field.accessibilityIdentifier = configuration.accessibilityIdentifier
            field.accessibilityLabel = configuration.title
            field.delegate = self
            field.tag = index
            field.autocorrectionType = .no
        }

        fullNameField.addTarget(self, action: #selector(fullNameChanged), for: .editingChanged)
        phoneField.addTarget(self, action: #selector(phoneChanged), for: .editingChanged)
        documentField.addTarget(self, action: #selector(documentChanged), for: .editingChanged)
    }

    /// Aqui eu reforco a interacao dos campos quando a tela reaparece apos transicoes ou modais.
    private func ensureIdentityFieldsInteractive() {
        orderedFields.forEach { field in
            field.isUserInteractionEnabled = true
            field.isEnabled = true
            field.isExclusiveTouch = false
        }
        saveButton.isUserInteractionEnabled = true
        saveButton.isEnabled = true
        changePhotoButton.isUserInteractionEnabled = true
        changePhotoButton.isEnabled = true
        changePasswordButton.isUserInteractionEnabled = true
        changePasswordButton.isEnabled = true
    }

    /// Aqui eu aplico um padding simples quando o campo nao usa icone lateral.
    private func setFieldLeftPadding(_ field: UITextField, value: CGFloat) {
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        spacer.isUserInteractionEnabled = false
        field.leftView = spacer
        field.leftViewMode = .always
    }

    /// Aqui eu gero o container de icone padronizado para os campos do card.
    private func makeFieldIconContainer(systemName: String) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 42))
        container.isUserInteractionEnabled = false

        let icon = UIImageView(image: UIImage(systemName: systemName))
        icon.tintColor = UIColor(hex: "#95A9BD")
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 10, y: 13, width: 16, height: 16)
        icon.isUserInteractionEnabled = false
        container.addSubview(icon)
        return container
    }

    /// Aqui eu busco o snapshot salvo e reaplico nos campos sempre que a tela for aberta.
    private func loadIdentity() {
        let snapshot = fetchIdentitySnapshot()
        applySnapshot(snapshot)
    }

    /// Aqui eu atualizo nome, telefone e documento com o backend quando o app estiver no modo remoto.
    private func refreshRemoteIdentityIfNeeded() {
        guard portalService.isRemoteMode else { return }

        Task { [weak self] in
            guard let self else { return }

            do {
                let remoteProfile = try await self.portalService.fetchProfile()
                await MainActor.run {
                let mergedSnapshot = self.mergeRemoteProfile(
                    remoteProfile,
                    into: self.fetchIdentitySnapshot()
                )
                    self.saveIdentitySnapshot(mergedSnapshot)
                    self.applySnapshot(mergedSnapshot)
                }
            } catch {
                // Aqui eu mantenho a identidade local quando o backend não estiver acessível.
            }
        }
    }

    /// Aqui eu puxo do backend a foto mais recente do usuário e atualizo o cache local sem bloquear a tela.
    private func refreshRemoteProfilePhotoIfNeeded() {
        guard portalService.isRemoteMode else {
            importGoogleProfilePhotoIfNeeded(uploadToRemoteWhenMissing: false)
            return
        }

        photoRefreshTask?.cancel()
        photoRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let attachment = try await self.portalService.fetchLatestUserAttachment(userID: self.session.userID) else {
                    self.importGoogleProfilePhotoIfNeeded(uploadToRemoteWhenMissing: true)
                    return
                }

                let imageData = try await self.portalService.downloadAttachment(attachment)
                try self.persistProfilePhoto(imageData)

                await MainActor.run {
                    self.applyProfileImageData(imageData)
                    self.savePhotoAttachmentReference(attachment.downloadPath)
                }
            } catch {
                self.importGoogleProfilePhotoIfNeeded(uploadToRemoteWhenMissing: false)
            }
        }
    }

    /// Aqui eu reaproveito a foto social do Google quando o backend ainda não tiver um anexo de perfil.
    private func importGoogleProfilePhotoIfNeeded(uploadToRemoteWhenMissing shouldUploadToRemote: Bool) {
        guard session.provider == .google else { return }
        guard avatarImageView.image == nil else { return }
        guard let rawAvatarURL = session.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawAvatarURL.isEmpty else { return }
        guard let avatarURL = URL(string: rawAvatarURL) else { return }

        socialPhotoImportTask?.cancel()
        socialPhotoImportTask = Task { [weak self] in
            guard let self else { return }

            do {
                let (data, response) = try await URLSession.shared.data(from: avatarURL)
                guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode), !data.isEmpty else {
                    return
                }

                try self.persistProfilePhoto(data)

                await MainActor.run {
                    self.applyProfileImageData(data)
                }

                guard shouldUploadToRemote, self.actionsService.isRemoteMode else { return }
                let attachment = try await self.actionsService.uploadUserProfilePhoto(
                    userID: self.session.userID,
                    imageData: data,
                    filename: "perfil-google.jpg"
                )

                await MainActor.run {
                    self.savePhotoAttachmentReference(attachment.downloadPath)
                }
            } catch {
                // Aqui eu preservo o fallback de iniciais quando a foto social não puder ser reaproveitada.
            }
        }
    }

    /// Aqui eu reaplico a foto em cache logo na abertura para a tela parecer instantânea.
    private func loadCachedProfilePhoto() {
        guard
            let imageData = try? Data(contentsOf: localProfilePhotoURL),
            !imageData.isEmpty
        else {
            updateAvatarFallback()
            return
        }

        applyProfileImageData(imageData)
    }

    /// Aqui eu separo a aplicacao do snapshot para reaproveitar depois de salvar.
    private func applySnapshot(_ snapshot: IdentitySnapshot) {
        fullNameField.text = snapshot.fullName
        emailField.text = snapshot.email
        phoneField.text = snapshot.phone
        documentField.text = Formatters.formatCPFOrCNPJ(snapshot.document)
        updateAvatarFallback()
    }

    /// Aqui eu valido a identidade, salvo o snapshot local e sincronizo com o backend quando ele existir.
    @objc private func saveTapped() {
        view.endEditing(true)
        saveButton.isEnabled = false

        let snapshot = currentIdentitySnapshot()

        guard validate(snapshot) else {
            saveButton.isEnabled = true
            showSimpleToast("Informe um e-mail válido.", style: .error)
            return
        }

        guard portalService.isRemoteMode else {
            saveIdentitySnapshot(snapshot)
            applySnapshot(snapshot)
            showSimpleToast("Alterações salvas localmente.", style: .success)
            saveButton.isEnabled = true
            return
        }

        let remoteFullName = snapshot.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let remotePhone = snapshot.phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !remoteFullName.isEmpty, !remotePhone.isEmpty else {
            showSimpleToast("Informe nome e telefone para salvar a identidade no servidor.", style: .error)
            saveButton.isEnabled = true
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.portalService.saveProfile(
                    userID: self.session.userID,
                    payload: PortalProfileUpdatePayload(
                        fullName: remoteFullName,
                        email: snapshot.email,
                        phone: remotePhone,
                        document: snapshot.document
                    )
                )

                await MainActor.run {
                    let mergedSnapshot = self.mergeRemoteProfile(
                        result.profile,
                        into: snapshot,
                        preferRemoteManagedFields: result.syncMode == .expanded
                    )
                    self.saveIdentitySnapshot(mergedSnapshot)
                    self.applySnapshot(mergedSnapshot)
                    self.showSimpleToast(
                        self.remoteSaveMessage(for: result.syncMode),
                        style: .success
                    )
                    self.saveButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast("Não consegui salvar a identidade no servidor. Revise os dados e tente novamente.", style: .error)
                    self.saveButton.isEnabled = true
                }
            }
        }
    }

    /// Aqui eu abro o seletor nativo do iOS para a pessoa escolher uma nova foto de perfil.
    @objc private func changePhotoTapped() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    /// Aqui eu abro a interface nativa do iOS para a troca de senha da conta conectada.
    @objc private func changePasswordTapped() {
        guard actionsService.isRemoteMode else {
            showSimpleToast("A troca de senha remota está disponível apenas quando a conta estiver conectada ao servidor.", style: .info)
            return
        }

        presentPasswordPrompt()
    }

    /// Aqui eu reutilizo o mesmo alerta nativo sempre que preciso reabrir o fluxo com uma mensagem clara.
    private func presentPasswordPrompt(message: String? = nil) {
        let alert = UIAlertController(
            title: "Alterar senha",
            message: message ?? "Informe a senha atual e defina a nova senha da sua conta.",
            preferredStyle: .alert
        )

        let placeholders = [
            "Senha atual",
            "Nova senha",
            "Confirmar nova senha"
        ]

        for (index, placeholder) in placeholders.enumerated() {
            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.isSecureTextEntry = true
                textField.autocapitalizationType = .none
                textField.autocorrectionType = .no
                textField.textContentType = index == 0 ? .password : .newPassword
                textField.accessibilityLabel = placeholder
            }
        }

        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Atualizar", style: .default) { [weak self, weak alert] _ in
            guard
                let self,
                let alert,
                let currentPassword = alert.textFields?[0].text,
                let newPassword = alert.textFields?[1].text,
                let confirmation = alert.textFields?[2].text
            else {
                return
            }

            if let validationMessage = self.passwordValidationMessage(
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmation: confirmation
            ) {
                self.presentPasswordPrompt(message: validationMessage)
                return
            }

            self.submitPasswordChange(currentPassword: currentPassword, newPassword: newPassword)
        })

        present(alert, animated: true)
    }

    /// Aqui eu recebo a imagem selecionada, atualizo o cache local e só depois tento subir para o backend.
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let result = results.first else {
            showSimpleToast("Seleção de foto cancelada.")
            return
        }

        photoUploadTask?.cancel()
        photoUploadTask = Task { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.setPhotoUploadProcessing(true)
            }

            var savedLocally = false
            do {
                let image = try await self.loadSelectedProfileImage(from: result)
                guard let imageData = image.jpegData(compressionQuality: 0.86), !imageData.isEmpty else {
                    throw URLError(.cannotDecodeContentData)
                }

                try self.persistProfilePhoto(imageData)
                savedLocally = true

                await MainActor.run {
                    self.applyProfileImageData(imageData)
                }

                if self.actionsService.isRemoteMode {
                    let attachment = try await self.actionsService.uploadUserProfilePhoto(
                        userID: self.session.userID,
                        imageData: imageData
                    )

                    await MainActor.run {
                        self.savePhotoAttachmentReference(attachment.downloadPath)
                        self.showSimpleToast("Foto de perfil sincronizada com o servidor.", style: .success)
                    }
                } else {
                    await MainActor.run {
                        self.showSimpleToast("Foto de perfil salva localmente.", style: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    if savedLocally && self.actionsService.isRemoteMode {
                        self.showSimpleToast("Foto salva localmente. Falhou ao sincronizar com o servidor.", style: .info)
                    } else {
                        self.showSimpleToast(error.localizedDescription, style: .error)
                    }
                }
            }

            await MainActor.run {
                self.setPhotoUploadProcessing(false)
            }
        }
    }

    /// Aqui eu centralizo a validação local para evitar round-trip desnecessário ao backend.
    private func passwordValidationMessage(
        currentPassword: String,
        newPassword: String,
        confirmation: String
    ) -> String? {
        if currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            newPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            confirmation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Preencha a senha atual, a nova senha e a confirmação."
        }

        if newPassword != confirmation {
            return "A confirmação da nova senha não confere."
        }

        if currentPassword == newPassword {
            return "A nova senha precisa ser diferente da senha atual."
        }

        if !isValidPasswordPolicy(newPassword) {
            return "A nova senha precisa ter 8+ caracteres, maiúscula, minúscula, número e caractere especial."
        }

        return nil
    }

    /// Aqui eu envio a troca de senha para o backend e atualizo o estado local só quando houver sucesso real.
    private func submitPasswordChange(currentPassword: String, newPassword: String) {
        changePasswordButton.isEnabled = false

        Task { [weak self] in
            guard let self else { return }

            do {
                try await self.actionsService.updatePassword(
                    userID: self.session.userID,
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )

                await MainActor.run {
                    self.dataStore.markPasswordChanged()
                    self.showSimpleToast("Senha atualizada com sucesso.", style: .success)
                    self.changePasswordButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                    self.changePasswordButton.isEnabled = true
                }
            }
        }
    }

    /// Aqui eu deixo claro na UI quando a troca de foto ainda está em andamento.
    private func setPhotoUploadProcessing(_ isProcessing: Bool) {
        changePhotoButton.isEnabled = !isProcessing
        changePhotoButton.alpha = isProcessing ? 0.72 : 1
        let title = isProcessing ? " Enviando foto..." : " Alterar foto"
        let image = UIImage(systemName: isProcessing ? "hourglass" : "photo.on.rectangle")
        changePhotoButton.setTitle(title, for: .normal)
        changePhotoButton.setImage(image, for: .normal)
    }

    /// Aqui eu converto o item do picker para UIImage já pronta para compressão em JPEG.
    private func loadSelectedProfileImage(from result: PHPickerResult) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = object as? UIImage else {
                    continuation.resume(throwing: URLError(.cannotDecodeContentData))
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    /// Aqui eu aplico a imagem final no avatar e escondo o fallback de iniciais.
    private func applyProfileImageData(_ imageData: Data) {
        guard let image = UIImage(data: imageData) else {
            updateAvatarFallback()
            return
        }

        avatarImageView.image = image
        avatarImageView.isHidden = false
        avatarFallbackLabel.isHidden = true
    }

    /// Aqui eu mantenho um avatar com iniciais quando ainda não existe foto selecionada.
    private func updateAvatarFallback() {
        guard avatarImageView.image == nil else { return }

        let fullName = (fullNameField.text ?? session.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = fullName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        avatarFallbackLabel.text = tokens.isEmpty ? "BE" : tokens.joined()
        avatarFallbackLabel.isHidden = false
        avatarImageView.isHidden = true
    }

    /// Aqui eu salvo a foto de perfil com file protection completa para que só seja legível
    /// quando o dispositivo está desbloqueado — conforme as diretrizes de privacidade da Apple.
    private func persistProfilePhoto(_ imageData: Data) throws {
        let directoryURL = localProfilePhotoURL.deletingLastPathComponent()
        let protectionAttributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: protectionAttributes
        )
        try imageData.write(to: localProfilePhotoURL, options: .atomic)
        try FileManager.default.setAttributes(protectionAttributes, ofItemAtPath: localProfilePhotoURL.path)
    }

    /// Aqui eu leio o estado atual do formulario em um unico objeto para facilitar validacao e persistencia.
    private func currentIdentitySnapshot() -> IdentitySnapshot {
        IdentitySnapshot(
            fullName: (fullNameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            email: (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            phone: (phoneField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            document: (documentField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Aqui eu mantenho a regra de validacao simples e explicita enquanto o fluxo ainda e local.
    private func validate(_ snapshot: IdentitySnapshot) -> Bool {
        snapshot.email.isEmpty || (snapshot.email.contains("@") && snapshot.email.contains("."))
    }

    /// Aqui eu mantenho a mesma política mínima de senha usada no restante do app para evitar inconsistência.
    private func isValidPasswordPolicy(_ value: String) -> Bool {
        guard value.count >= 8 else { return false }
        let hasUppercase = value.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowercase = value.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumber = value.rangeOfCharacter(from: .decimalDigits) != nil
        let specialCharacters = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:'\",.<>/?`~\\")
        let hasSpecialCharacter = value.rangeOfCharacter(from: specialCharacters) != nil
        return hasUppercase && hasLowercase && hasNumber && hasSpecialCharacter
    }

    /// Aqui eu atualizo as iniciais do avatar sempre que o nome muda e ainda não existe foto carregada.
    @objc private func fullNameChanged() {
        updateAvatarFallback()
    }

    /// Aqui eu formato o telefone em tempo real sem perder o cursor de digitacao do usuario.
    @objc private func phoneChanged() {
        let digits = Formatters.digitsOnly(phoneField.text ?? "")
        phoneField.text = digits.count <= 10 ? formatPhone10(digits) : formatPhone11(digits)
    }

    /// Aqui eu escolho automaticamente entre mascara de CPF e CNPJ conforme a quantidade de digitos.
    @objc private func documentChanged() {
        documentField.text = Formatters.formatCPFOrCNPJ(documentField.text ?? "")
    }

    /// Aqui eu avanço para o proximo campo por ordem configurada e fecho o teclado no ultimo.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let nextTag = textField.tag + 1
        if let nextField = view.viewWithTag(nextTag) as? UITextField {
            nextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    /// Aqui eu gero uma chave isolada por usuario para nao misturar dados entre contas locais.
    private var identityStorageKey: String {
        "\(identityKeyPrefix).\(session.userID)"
    }

    /// Aqui eu isolo a referência remota do anexo por usuário sem misturar com o snapshot de identidade.
    private var photoAttachmentStorageKey: String {
        "\(photoKeyPrefix).\(session.userID)"
    }

    /// Aqui eu persisto a foto de perfil no applicationSupportDirectory para sobreviver a limpezas de cache
    /// e ser protegida com .completeFileProtection — inacessível quando o dispositivo está bloqueado.
    private var localProfilePhotoURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("BillEasyProfilePhotos", isDirectory: true)
            .appendingPathComponent("\(session.userID).jpg", isDirectory: false)
    }

    /// Aqui eu recupero a identidade salva localmente ou monto um estado inicial coerente com a sessão.
    private func fetchIdentitySnapshot() -> IdentitySnapshot {
        if let data = defaults.data(forKey: identityStorageKey),
           let decoded = try? JSONDecoder().decode(IdentitySnapshot.self, from: data) {
            return decoded
        }

        return IdentitySnapshot(
            fullName: session.displayName,
            email: session.email,
            phone: session.phone ?? "",
            document: ""
        )
    }

    /// Aqui eu salvo o snapshot inteiro para manter a persistencia previsivel e simples.
    private func saveIdentitySnapshot(_ snapshot: IdentitySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: identityStorageKey)
    }

    /// Aqui eu mantenho a última referência remota só para debug leve e futuras sincronizações incrementais.
    private func savePhotoAttachmentReference(_ value: String?) {
        defaults.set(value, forKey: photoAttachmentStorageKey)
    }

    /// Aqui eu mesclo o que veio do backend sem apagar os campos que ainda existem apenas no app local.
    private func mergeRemoteProfile(
        _ remoteProfile: PortalUserProfile,
        into snapshot: IdentitySnapshot,
        preferRemoteManagedFields: Bool = false
    ) -> IdentitySnapshot {
        IdentitySnapshot(
            fullName: remoteProfile.fullName.nilIfEmpty ?? snapshot.fullName,
            email: preferRemoteManagedFields
                ? (remoteProfile.email.nilIfEmpty ?? snapshot.email)
                : (snapshot.email.nilIfEmpty ?? remoteProfile.email),
            phone: remoteProfile.phone.nilIfEmpty ?? snapshot.phone,
            document: preferRemoteManagedFields
                ? (remoteProfile.document.nilIfEmpty ?? snapshot.document)
                : (snapshot.document.nilIfEmpty ?? remoteProfile.document)
        )
    }

    /// Aqui eu deixo a mensagem de sucesso coerente com o que o backend realmente aceitou persistir.
    private func remoteSaveMessage(for syncMode: PortalProfileRemoteSyncMode) -> String {
        switch syncMode {
        case .expanded:
            return "Perfil sincronizado com o servidor."
        case .legacy:
            return "Nome e telefone sincronizados com o servidor. E-mail e CPF/CNPJ continuam locais por enquanto."
        }
    }

    /// Aqui eu formato telefone fixo ou legado com no maximo 10 digitos.
    private func formatPhone10(_ digits: String) -> String {
        let raw = String(digits.prefix(10))
        guard !raw.isEmpty else { return "" }

        var result = ""
        for (index, char) in raw.enumerated() {
            switch index {
            case 0: result.append("(")
            case 2: result.append(") ")
            case 6: result.append("-")
            default: break
            }
            result.append(char)
        }
        return result
    }

    /// Aqui eu formato celular no padrao atual com no maximo 11 digitos.
    private func formatPhone11(_ digits: String) -> String {
        let raw = String(digits.prefix(11))
        guard !raw.isEmpty else { return "" }

        var result = ""
        for (index, char) in raw.enumerated() {
            switch index {
            case 0: result.append("(")
            case 2: result.append(") ")
            case 7: result.append("-")
            default: break
            }
            result.append(char)
        }
        return result
    }

}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
