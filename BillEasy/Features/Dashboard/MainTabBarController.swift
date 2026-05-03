//
//  MainTabBarController.swift
//  BillEasy
//

import CoreLocation
import QuickLook
import UserNotifications
import UIKit

final class MainTabBarController: UIViewController, CLLocationManagerDelegate {
    var onLogout: (() -> Void)?

    private enum AppSection: CaseIterable {
        case queroReceber
        case queroPagar
        case meuPlano
        case novoContrato
        case promissorias
        case verificacoes
        case agenda
        case localizar
        case perfil

        var menuTitle: String {
            switch self {
            case .queroReceber:  return "Quero Receber"
            case .queroPagar:    return "Quero Pagar"
            case .meuPlano:      return "Meu Plano"
            case .novoContrato:  return "Meus Contratos"
            case .promissorias:  return "Promissórias"
            case .verificacoes:  return "Verificações"
            case .agenda:        return "Agenda"
            case .localizar:     return "Localizar Devedor"
            case .perfil:        return "Perfil"
            }
        }

        var menuIcon: String {
            switch self {
            case .queroReceber:  return "chart.line.uptrend.xyaxis"
            case .queroPagar:    return "chart.line.downtrend.xyaxis"
            case .meuPlano:      return "creditcard.and.123"
            case .novoContrato:  return "square.and.pencil"
            case .promissorias:  return "doc.text"
            case .verificacoes:  return "person.badge.shield.checkmark"
            case .agenda:        return "calendar"
            case .localizar:     return "person.text.rectangle"
            case .perfil:        return "person"
            }
        }

        var menuAccessibilityIdentifier: String {
            switch self {
            case .queroReceber:  return "menu.home"
            case .queroPagar:    return "menu.payments"
            case .meuPlano:      return "menu.subscription"
            case .novoContrato:  return "menu.newContract"
            case .promissorias:  return "menu.promissorias"
            case .verificacoes:  return "menu.verificacoes"
            case .agenda:        return "menu.agenda"
            case .localizar:     return "menu.locate"
            case .perfil:        return "menu.profile"
            }
        }

        var appearsInMenu: Bool {
            switch self {
            case .meuPlano:
                return false
            default:
                return true
            }
        }

        var bottomTitle: String {
            switch self {
            case .queroReceber: return "Início"
            case .agenda: return "Agenda"
            case .localizar: return "Localizar"
            case .perfil: return "Perfil"
            default: return ""
            }
        }

        var bottomIcon: String {
            switch self {
            case .queroReceber: return "square.grid.2x2"
            case .agenda: return "calendar"
            case .localizar: return "person.2"
            case .perfil: return "person"
            default: return ""
            }
        }

        var appearsInBottomBar: Bool {
            switch self {
            case .queroReceber, .agenda, .localizar, .perfil:
                return true
            default:
                return false
            }
        }

        var bottomAccessibilityIdentifier: String {
            switch self {
            case .queroReceber: return "tab.home"
            case .agenda: return "tab.agenda"
            case .localizar: return "tab.locate"
            case .perfil: return "tab.profile"
            default: return "tab.unknown"
            }
        }
    }

    private let session: AuthSession
    private let authService: AuthService
    private let dataStore: LocalAppDataStore
    private let webHandoffService: PortalWebHandoffService
    private let notificacoesService = NotificacoesService()

    private let headerView = UIView()
    private let menuButton = UIButton(type: .system)
    private let bellButton = UIButton(type: .system)
    private let bellBadge = UILabel()
    private let headerSeparator = UIView()
    private let contentContainer = UIView()
    private let bottomBar = UIView()
    private let themeDimmingView = UIView()
    private let overlayButton = UIButton(type: .custom)
    private let sideMenuContainer = UIView()
    private let sideMenuHeader = UIView()
    private let sideMenuCloseButton = UIButton(type: .system)
    private let sideMenuFooter = UIView()
    private let themeToggleButton = UIButton(type: .system)
    private let logoutButton = UIButton(type: .system)
    private let locationManager = CLLocationManager()

    private let themePreferenceKey = "billeasy.theme.dark_mode_enabled"
    private let locationOnboardingPrefix = "billeasy.location.onboarding.completed"
    private let locationStatusPrefix = "billeasy.location.status"
    private let notificationOnboardingPrefix = "billeasy.notifications.onboarding.completed"
    private let notificationStatusPrefix = "billeasy.notifications.status"
    private var isDarkModeEnabled = UserDefaults.standard.bool(forKey: "billeasy.theme.dark_mode_enabled")
    private var didEvaluateLocationOnboarding = false
    private var didEvaluateNotificationOnboarding = false
    private var isRequestingLocationPermission = false
    private var isRequestingNotificationPermission = false

    private var sideMenuLeadingConstraint: NSLayoutConstraint?
    private var sideMenuWidthConstraint: NSLayoutConstraint?
    private var currentSection: AppSection = .queroReceber
    private var currentController: UIViewController?
    private var promissoriaPDFPreviewURL: URL?

    private var controllers: [AppSection: UIViewController] = [:]
    private var menuItemButtons: [AppSection: UIButton] = [:]
    private var menuItemBackgrounds: [AppSection: UIView] = [:]
    private var bottomButtons: [AppSection: UIButton] = [:]
    private var bottomIndicators: [AppSection: UIView] = [:]

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App"
    }

    private var sideMenuWidth: CGFloat {
        min(326, view.bounds.width * 0.82)
    }

    init(
        session: AuthSession,
        authService: AuthService,
        dataStore: LocalAppDataStore,
        webHandoffService: PortalWebHandoffService = PortalWebHandoffService()
    ) {
        self.session = session
        self.authService = authService
        self.dataStore = dataStore
        self.webHandoffService = webHandoffService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupLayout()
        setupHeader()
        setupBottomBar()
        setupSideMenu()
        setupLifecycleObservers()
        switchToSection(.queroReceber)
        applyTheme(animated: false)
        locationManager.delegate = self
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyWindowInterfaceStyle()
        loadNotificationCount()

        guard !AppRuntimeConfiguration.shouldSkipPermissionOnboarding else { return }
        evaluateLocationOnboardingIfNeeded()
        evaluateNotificationOnboardingIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let newWidth = sideMenuWidth
        if sideMenuWidthConstraint?.constant != newWidth {
            sideMenuWidthConstraint?.constant = newWidth
        }
        bottomBar.layer.shadowPath = UIBezierPath(
            roundedRect: bottomBar.bounds,
            cornerRadius: bottomBar.layer.cornerRadius
        ).cgPath
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appWillEnterForeground() {
        applyWindowInterfaceStyle()
        view.setNeedsLayout()
        currentController?.view.setNeedsLayout()
    }

    @objc private func appDidBecomeActive() {
        applyTheme(animated: false)
        currentController?.view.layoutIfNeeded()
        loadNotificationCount()
    }

    private func setupView() {
        view.backgroundColor = .systemBackground

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .secondarySystemBackground

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.tintColor = .secondaryLabel
        menuButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        menuButton.accessibilityIdentifier = "main.menuButton"
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)

        bellButton.translatesAutoresizingMaskIntoConstraints = false
        bellButton.setImage(UIImage(systemName: "bell"), for: .normal)
        bellButton.tintColor = .secondaryLabel
        bellButton.accessibilityLabel = "Notificações"
        bellButton.addTarget(self, action: #selector(bellTapped), for: .touchUpInside)

        bellBadge.translatesAutoresizingMaskIntoConstraints = false
        bellBadge.textColor = .white
        bellBadge.font = .systemFont(ofSize: 9, weight: .bold)
        bellBadge.textAlignment = .center
        bellBadge.backgroundColor = UIColor(hex: "#EF4444")
        bellBadge.layer.cornerRadius = 7
        bellBadge.layer.masksToBounds = true
        bellBadge.isHidden = true

        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.backgroundColor = .separator

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = .systemBackground

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = .tertiarySystemBackground
        bottomBar.layer.cornerRadius = 16
        bottomBar.layer.masksToBounds = false
        bottomBar.layer.shadowColor = UIColor.black.cgColor
        bottomBar.layer.shadowOpacity = 0.18
        bottomBar.layer.shadowOffset = CGSize(width: 0, height: 6)
        bottomBar.layer.shadowRadius = 16

        themeDimmingView.translatesAutoresizingMaskIntoConstraints = false
        themeDimmingView.backgroundColor = .clear
        themeDimmingView.alpha = 0
        themeDimmingView.isUserInteractionEnabled = false

        overlayButton.translatesAutoresizingMaskIntoConstraints = false
        overlayButton.backgroundColor = UIColor.black.withAlphaComponent(0.36)
        overlayButton.alpha = 0
        overlayButton.isHidden = true
        overlayButton.isUserInteractionEnabled = false
        overlayButton.addTarget(self, action: #selector(hideMenu), for: .touchUpInside)

        sideMenuContainer.translatesAutoresizingMaskIntoConstraints = false
        sideMenuContainer.backgroundColor = .secondarySystemBackground
        sideMenuContainer.isUserInteractionEnabled = false

        view.addSubview(contentContainer)
        view.addSubview(headerView)
        view.addSubview(bottomBar)
        view.addSubview(themeDimmingView)
        view.addSubview(overlayButton)
        view.addSubview(sideMenuContainer)

        headerView.addSubview(menuButton)
        headerView.addSubview(bellButton)
        headerView.addSubview(bellBadge)
        headerView.addSubview(headerSeparator)
    }

    private func setupLayout() {
        sideMenuLeadingConstraint = sideMenuContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -sideMenuWidth)
        sideMenuWidthConstraint = sideMenuContainer.widthAnchor.constraint(equalToConstant: sideMenuWidth)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),

            menuButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            menuButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -14),
            menuButton.widthAnchor.constraint(equalToConstant: 28),
            menuButton.heightAnchor.constraint(equalToConstant: 28),

            bellButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            bellButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -14),
            bellButton.widthAnchor.constraint(equalToConstant: 28),
            bellButton.heightAnchor.constraint(equalToConstant: 28),

            bellBadge.topAnchor.constraint(equalTo: bellButton.topAnchor, constant: -2),
            bellBadge.trailingAnchor.constraint(equalTo: bellButton.trailingAnchor, constant: 2),
            bellBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            bellBadge.heightAnchor.constraint(equalToConstant: 14),

            headerSeparator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),

            contentContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -10),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            bottomBar.heightAnchor.constraint(equalToConstant: 74),

            themeDimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            themeDimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            themeDimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            themeDimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            overlayButton.topAnchor.constraint(equalTo: view.topAnchor),
            overlayButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sideMenuContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sideMenuContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sideMenuWidthConstraint!,
            sideMenuLeadingConstraint!
        ])

        let brand = makeBrandView(titleSize: 16, subtitleSize: 6)
        brand.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(brand)

        NSLayoutConstraint.activate([
            brand.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            brand.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8)
        ])
    }

    private func setupHeader() {
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    private func setupBottomBar() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill

        bottomBar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -6)
        ])

        for section in AppSection.allCases where section.appearsInBottomBar {
            let wrapper = UIView()

            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = tag(for: section)
            button.accessibilityIdentifier = section.bottomAccessibilityIdentifier
            button.addTarget(self, action: #selector(bottomTapped(_:)), for: .touchUpInside)
            wrapper.addSubview(button)

            let indicator = UIView()
            indicator.translatesAutoresizingMaskIntoConstraints = false
            indicator.backgroundColor = .systemBlue
            indicator.layer.cornerRadius = 1.5
            indicator.alpha = 0
            wrapper.addSubview(indicator)

            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: wrapper.topAnchor),
                button.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),

                indicator.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                indicator.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -2),
                indicator.widthAnchor.constraint(equalToConstant: 18),
                indicator.heightAnchor.constraint(equalToConstant: 3)
            ])

            stack.addArrangedSubview(wrapper)
            bottomButtons[section] = button
            bottomIndicators[section] = indicator
        }

        refreshBottomSelection()
    }

    private func setupSideMenu() {
        sideMenuHeader.translatesAutoresizingMaskIntoConstraints = false

        let brand = makeBrandView(titleSize: 18, subtitleSize: 7)
        brand.translatesAutoresizingMaskIntoConstraints = false

        sideMenuCloseButton.translatesAutoresizingMaskIntoConstraints = false
        sideMenuCloseButton.tintColor = .secondaryLabel
        sideMenuCloseButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        sideMenuCloseButton.addTarget(self, action: #selector(hideMenu), for: .touchUpInside)

        sideMenuContainer.addSubview(sideMenuHeader)
        sideMenuHeader.addSubview(brand)
        sideMenuHeader.addSubview(sideMenuCloseButton)

        let menuStack = UIStackView()
        menuStack.translatesAutoresizingMaskIntoConstraints = false
        menuStack.axis = .vertical
        menuStack.spacing = 10
        sideMenuContainer.addSubview(menuStack)

        for section in AppSection.allCases where section.appearsInMenu {
            let background = UIView()
            background.translatesAutoresizingMaskIntoConstraints = false
            background.layer.cornerRadius = 10
            background.layer.borderWidth = 1
            background.layer.borderColor = UIColor.clear.cgColor
            background.backgroundColor = .clear

            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.contentHorizontalAlignment = .left
            button.tag = tag(for: section)
            button.accessibilityIdentifier = section.menuAccessibilityIdentifier
            button.addTarget(self, action: #selector(menuSectionTapped(_:)), for: .touchUpInside)

            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: section.menuIcon)
            config.title = section.menuTitle
            config.imagePadding = 12
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12)
            button.configuration = config

            background.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: background.topAnchor),
                button.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                button.bottomAnchor.constraint(equalTo: background.bottomAnchor),
                background.heightAnchor.constraint(equalToConstant: 44)
            ])

            menuStack.addArrangedSubview(background)
            menuItemButtons[section] = button
            menuItemBackgrounds[section] = background
        }

        sideMenuFooter.translatesAutoresizingMaskIntoConstraints = false
        sideMenuFooter.layer.borderWidth = 1
        sideMenuFooter.layer.borderColor = UIColor.separator.cgColor

        let footerStack = UIStackView()
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.axis = .vertical
        footerStack.spacing = 22

        themeToggleButton.translatesAutoresizingMaskIntoConstraints = false
        themeToggleButton.contentHorizontalAlignment = .left
        themeToggleButton.tintColor = .secondaryLabel
        themeToggleButton.addTarget(self, action: #selector(toggleThemeTapped), for: .touchUpInside)

        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.setTitle("  Sair", for: .normal)
        logoutButton.setImage(UIImage(systemName: "arrow.left.square"), for: .normal)
        logoutButton.contentHorizontalAlignment = .left
        logoutButton.tintColor = UIColor(hex: "#EA4335")
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)

        footerStack.addArrangedSubview(themeToggleButton)
        footerStack.addArrangedSubview(logoutButton)
        sideMenuFooter.addSubview(footerStack)
        sideMenuContainer.addSubview(sideMenuFooter)

        NSLayoutConstraint.activate([
            sideMenuHeader.topAnchor.constraint(equalTo: sideMenuContainer.safeAreaLayoutGuide.topAnchor),
            sideMenuHeader.leadingAnchor.constraint(equalTo: sideMenuContainer.leadingAnchor),
            sideMenuHeader.trailingAnchor.constraint(equalTo: sideMenuContainer.trailingAnchor),
            sideMenuHeader.heightAnchor.constraint(equalToConstant: 72),

            brand.leadingAnchor.constraint(equalTo: sideMenuHeader.leadingAnchor, constant: 16),
            brand.centerYAnchor.constraint(equalTo: sideMenuHeader.centerYAnchor),

            sideMenuCloseButton.trailingAnchor.constraint(equalTo: sideMenuHeader.trailingAnchor, constant: -16),
            sideMenuCloseButton.centerYAnchor.constraint(equalTo: sideMenuHeader.centerYAnchor),
            sideMenuCloseButton.widthAnchor.constraint(equalToConstant: 24),
            sideMenuCloseButton.heightAnchor.constraint(equalToConstant: 24),

            menuStack.topAnchor.constraint(equalTo: sideMenuHeader.bottomAnchor, constant: 18),
            menuStack.leadingAnchor.constraint(equalTo: sideMenuContainer.leadingAnchor, constant: 10),
            menuStack.trailingAnchor.constraint(equalTo: sideMenuContainer.trailingAnchor, constant: -10),

            sideMenuFooter.leadingAnchor.constraint(equalTo: sideMenuContainer.leadingAnchor),
            sideMenuFooter.trailingAnchor.constraint(equalTo: sideMenuContainer.trailingAnchor),
            sideMenuFooter.bottomAnchor.constraint(equalTo: sideMenuContainer.bottomAnchor),
            sideMenuFooter.heightAnchor.constraint(equalToConstant: 160),

            footerStack.leadingAnchor.constraint(equalTo: sideMenuFooter.leadingAnchor, constant: 18),
            footerStack.trailingAnchor.constraint(equalTo: sideMenuFooter.trailingAnchor, constant: -18),
            footerStack.centerYAnchor.constraint(equalTo: sideMenuFooter.centerYAnchor),

            themeToggleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            logoutButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        refreshMenuSelection()
        refreshThemeToggleButton()
    }

    private func controller(for section: AppSection) -> UIViewController {
        if let existing = controllers[section] {
            return existing
        }

        let controller = makeController(for: section)
        controllers[section] = controller
        return controller
    }

    private func makeController(for section: AppSection) -> UIViewController {
        switch section {
        case .queroReceber:
            return DashboardViewController(session: session, dataStore: dataStore)
        case .queroPagar:
            return PaymentsViewController(session: session, dataStore: dataStore)
        case .meuPlano:
            return MeuPlanoViewController(session: session, dataStore: dataStore)
        case .novoContrato:
            return ContractsViewController(session: session, dataStore: dataStore)
        case .promissorias:
            let vc = PromissoriasViewController(session: session)
            vc.onAbrirDetalhe = { [weak self] id in self?.presentPromissoriaDetalhe(id: id) }
            vc.onNovaPromissoria = { [weak self] in
                guard let self else { return }
                let wizard = PromissoriaWizardViewController(session: self.session)
                wizard.onConcluido = { [weak self, weak wizard] in
                    wizard?.dismiss(animated: true)
                    (self?.controllers[.promissorias] as? PromissoriasViewController)?.viewWillAppear(true)
                }
                wizard.onCancelar = { [weak wizard] in
                    wizard?.dismiss(animated: true)
                }
                wizard.modalPresentationStyle = .fullScreen
                self.present(wizard, animated: true)
            }
            return vc
        case .verificacoes:
            let vc = VerificacoesViewController(session: session)
            vc.onAbrirDetalhe = { [weak self] id in self?.presentVerificacaoDetalhe(id: id) }
            return vc
        case .agenda:
            return AgendaViewController(session: session, dataStore: dataStore)
        case .localizar:
            return RoutePlaceholderViewController(route: .dashboard, displayTitle: section.menuTitle)
        case .perfil:
            return ProfileViewController(session: session, dataStore: dataStore)
        }
    }

    private func switchToSection(_ section: AppSection) {
        currentSection = section
        // Ensure side menu overlay never blocks interactions in destination screens.
        overlayButton.alpha = 0
        overlayButton.isHidden = true
        overlayButton.isUserInteractionEnabled = false
        sideMenuContainer.isUserInteractionEnabled = false

        let destination = controller(for: section)

        if currentController === destination {
            refreshMenuSelection()
            refreshBottomSelection()
            return
        }

        currentController?.willMove(toParent: nil)
        currentController?.view.removeFromSuperview()
        currentController?.removeFromParent()

        addChild(destination)
        destination.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(destination.view)
        NSLayoutConstraint.activate([
            destination.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            destination.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            destination.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            destination.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        destination.didMove(toParent: self)

        currentController = destination
        refreshMenuSelection()
        refreshBottomSelection()
    }

    func navigateToAgenda() {
        switchToSection(.agenda)
    }

    func navigateToHome() {
        switchToSection(.queroReceber)
    }

    func navigateToDebtorLocator() {
        openDebtorLocatorInBrowser()
    }

    func navigateToMyPlan() {
        switchToSection(.meuPlano)
    }

    func handleAccountAnonymizationCompletion() {
        onLogout?()
    }

    private func refreshMenuSelection() {
        let selectedForeground = isDarkModeEnabled ? UIColor(hex: "#7BD2FF") : UIColor.systemBlue
        let normalForeground = isDarkModeEnabled ? UIColor(hex: "#B7CBE3") : UIColor.secondaryLabel
        let selectedBorder = isDarkModeEnabled
            ? UIColor(hex: "#41A8DC", alpha: 0.72)
            : UIColor.systemBlue.withAlphaComponent(0.35)
        let selectedBackground = isDarkModeEnabled
            ? UIColor(hex: "#123955")
            : UIColor.systemBlue.withAlphaComponent(0.10)

        for section in AppSection.allCases {
            let isSelected = section == currentSection
            let button = menuItemButtons[section]
            let background = menuItemBackgrounds[section]

            button?.configuration?.baseForegroundColor = isSelected ? selectedForeground : normalForeground
            background?.layer.borderColor = isSelected ? selectedBorder.cgColor : UIColor.clear.cgColor
            background?.backgroundColor = isSelected ? selectedBackground : .clear
        }
    }

    /// Reaplica o estado visual da barra inferior apenas nos botões cujo estado de seleção mudou.
    private func refreshBottomSelection() {
        let selectedColor = isDarkModeEnabled ? UIColor(hex: "#7BD2FF") : UIColor.systemBlue
        let normalColor = isDarkModeEnabled ? UIColor(hex: "#B0C6DD") : UIColor.secondaryLabel

        for section in AppSection.allCases where section.appearsInBottomBar {
            guard let button = bottomButtons[section] else { continue }
            let isSelected = currentSection == section

            let targetForeground = isSelected ? selectedColor : normalColor
            if button.configuration?.baseForegroundColor != targetForeground {
                var config = UIButton.Configuration.plain()
                config.image = UIImage(systemName: section.bottomIcon)
                config.title = section.bottomTitle
                config.imagePlacement = .top
                config.imagePadding = 4
                config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 6, trailing: 2)
                config.baseForegroundColor = targetForeground
                button.configuration = config
                button.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
            }

            bottomIndicators[section]?.backgroundColor = selectedColor
            bottomIndicators[section]?.alpha = isSelected ? 1 : 0
        }
    }

    private func showMenu() {
        guard overlayButton.isHidden else { return }
        overlayButton.isHidden = false
        overlayButton.isUserInteractionEnabled = true
        sideMenuContainer.isUserInteractionEnabled = true
        view.layoutIfNeeded()

        sideMenuLeadingConstraint?.constant = 0
        UIView.animate(withDuration: 0.25) {
            self.overlayButton.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    @objc private func hideMenu() {
        sideMenuLeadingConstraint?.constant = -sideMenuWidth
        UIView.animate(withDuration: 0.25) {
            self.overlayButton.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.overlayButton.isHidden = true
            self.overlayButton.isUserInteractionEnabled = false
            self.sideMenuContainer.isUserInteractionEnabled = false
        }
    }

    @objc private func menuTapped() {
        if overlayButton.isHidden {
            showMenu()
        } else {
            hideMenu()
        }
    }

    @objc private func bottomTapped(_ sender: UIButton) {
        guard let section = section(for: sender.tag) else { return }
        if section == .localizar {
            openDebtorLocatorInBrowser()
            return
        }
        switchToSection(section)
    }

    @objc private func menuSectionTapped(_ sender: UIButton) {
        guard let section = section(for: sender.tag) else { return }
        if section == .localizar {
            openDebtorLocatorInBrowser()
            hideMenu()
            return
        }
        switchToSection(section)
        hideMenu()
    }

    @objc private func toggleThemeTapped() {
        isDarkModeEnabled.toggle()
        UserDefaults.standard.set(isDarkModeEnabled, forKey: themePreferenceKey)
        closeMenuImmediately()
        applyTheme(animated: true)
    }

    @objc private func logoutTapped() {
        authService.logout()
        onLogout?()
    }

    private func evaluateLocationOnboardingIfNeeded() {
        guard !didEvaluateLocationOnboarding else { return }
        didEvaluateLocationOnboarding = true

        guard !hasCompletedLocationOnboarding(for: session.email) else {
            saveLocationStatus(currentLocationAuthorizationStatus())
            continuePermissionOnboarding()
            return
        }

        switch currentLocationAuthorizationStatus() {
        case .notDetermined:
            presentInitialLocationPrompt()
        case .denied, .restricted:
            saveLocationStatus(currentLocationAuthorizationStatus())
            presentLocationSettingsPrompt(firstTime: true)
        case .authorizedAlways, .authorizedWhenInUse:
            saveLocationStatus(currentLocationAuthorizationStatus())
            markLocationOnboardingCompleted(for: session.email)
            continuePermissionOnboarding()
        @unknown default:
            saveLocationStatus(currentLocationAuthorizationStatus())
            markLocationOnboardingCompleted(for: session.email)
            continuePermissionOnboarding()
        }
    }

    private func presentInitialLocationPrompt() {
        let alert = UIAlertController(
            title: "Compartilhar localização",
            message: "Deseja permitir localização ao usar o app para melhorar a experiência?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Agora não", style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            self.saveLocationStatus(self.currentLocationAuthorizationStatus())
            self.markLocationOnboardingCompleted(for: self.session.email)
            self.continuePermissionOnboarding()
        }))

        alert.addAction(UIAlertAction(title: "Permitir", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.isRequestingLocationPermission = true
            self.locationManager.requestWhenInUseAuthorization()
        }))

        present(alert, animated: true)
    }

    private func presentLocationSettingsPrompt(firstTime: Bool = false) {
        let alert = UIAlertController(
            title: "Localização desativada",
            message: "Você pode habilitar em Ajustes > \(appDisplayName).",
            preferredStyle: .alert
        )

        let skipTitle = firstTime ? "Não compartilhar" : "Agora não"
        alert.addAction(UIAlertAction(title: skipTitle, style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            self.saveLocationStatus(self.currentLocationAuthorizationStatus())
            self.markLocationOnboardingCompleted(for: self.session.email)
            self.continuePermissionOnboarding()
        }))

        alert.addAction(UIAlertAction(title: "Abrir Ajustes", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.saveLocationStatus(self.currentLocationAuthorizationStatus())
            self.markLocationOnboardingCompleted(for: self.session.email)
            self.continuePermissionOnboarding()
            self.openAppSettings()
        }))

        present(alert, animated: true)
    }

    private func locationOnboardingKey(for email: String) -> String {
        "\(locationOnboardingPrefix).\(email.lowercased())"
    }

    private func locationStatusKey(for email: String) -> String {
        "\(locationStatusPrefix).\(email.lowercased())"
    }

    private func hasCompletedLocationOnboarding(for email: String) -> Bool {
        UserDefaults.standard.bool(forKey: locationOnboardingKey(for: email))
    }

    private func markLocationOnboardingCompleted(for email: String) {
        UserDefaults.standard.set(true, forKey: locationOnboardingKey(for: email))
    }

    private func saveLocationStatus(_ status: CLAuthorizationStatus) {
        UserDefaults.standard.set(status.rawValue, forKey: locationStatusKey(for: session.email))
    }

    private func currentLocationAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleLocationAuthorizationChange(status: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleLocationAuthorizationChange(status: status)
    }

    private func handleLocationAuthorizationChange(status: CLAuthorizationStatus) {
        saveLocationStatus(status)

        guard isRequestingLocationPermission else { return }
        guard status != .notDetermined else { return }

        isRequestingLocationPermission = false

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            markLocationOnboardingCompleted(for: session.email)
            showSimpleToast("Localização ativada com sucesso.", style: .success)
            continuePermissionOnboarding()
        case .denied, .restricted:
            presentLocationSettingsPrompt(firstTime: true)
        case .notDetermined:
            break
        @unknown default:
            markLocationOnboardingCompleted(for: session.email)
            continuePermissionOnboarding()
        }
    }

    private func evaluateNotificationOnboardingIfNeeded() {
        guard presentedViewController == nil else { return }
        guard !didEvaluateNotificationOnboarding else {
            refreshNotificationStatusSnapshot()
            return
        }
        didEvaluateNotificationOnboarding = true

        guard !hasCompletedNotificationOnboarding(for: session.email) else {
            refreshNotificationStatusSnapshot()
            return
        }

        fetchNotificationAuthorizationStatus { [weak self] status in
            guard let self else { return }
            switch status {
            case .notDetermined:
                self.presentInitialNotificationPrompt()
            case .denied:
                self.saveNotificationStatus(status)
                self.presentNotificationSettingsPrompt(firstTime: true)
            case .authorized, .provisional, .ephemeral:
                self.saveNotificationStatus(status)
                self.markNotificationOnboardingCompleted(for: self.session.email)
            @unknown default:
                self.saveNotificationStatus(status)
                self.markNotificationOnboardingCompleted(for: self.session.email)
            }
        }
    }

    private func presentInitialNotificationPrompt() {
        let alert = UIAlertController(
            title: "Receber notificações",
            message: "Deseja receber alertas de vencimento, cobrança e atualizações importantes?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Agora não", style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            self.saveNotificationStatus(.notDetermined)
            self.markNotificationOnboardingCompleted(for: self.session.email)
        }))

        alert.addAction(UIAlertAction(title: "Permitir", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.isRequestingNotificationPermission = true
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.fetchNotificationAuthorizationStatus { status in
                        self?.handleNotificationAuthorizationChange(status: status)
                    }
                }
            }
        }))

        present(alert, animated: true)
    }

    private func presentNotificationSettingsPrompt(firstTime: Bool = false) {
        let alert = UIAlertController(
            title: "Notificações desativadas",
            message: "Você pode habilitar em Ajustes > \(appDisplayName).",
            preferredStyle: .alert
        )

        let skipTitle = firstTime ? "Não receber" : "Agora não"
        alert.addAction(UIAlertAction(title: skipTitle, style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            self.refreshNotificationStatusSnapshot()
            self.markNotificationOnboardingCompleted(for: self.session.email)
        }))

        alert.addAction(UIAlertAction(title: "Abrir Ajustes", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.refreshNotificationStatusSnapshot()
            self.markNotificationOnboardingCompleted(for: self.session.email)
            self.openAppSettings()
        }))

        present(alert, animated: true)
    }

    private func notificationOnboardingKey(for email: String) -> String {
        "\(notificationOnboardingPrefix).\(email.lowercased())"
    }

    private func notificationStatusKey(for email: String) -> String {
        "\(notificationStatusPrefix).\(email.lowercased())"
    }

    private func hasCompletedNotificationOnboarding(for email: String) -> Bool {
        UserDefaults.standard.bool(forKey: notificationOnboardingKey(for: email))
    }

    private func markNotificationOnboardingCompleted(for email: String) {
        UserDefaults.standard.set(true, forKey: notificationOnboardingKey(for: email))
    }

    private func saveNotificationStatus(_ status: UNAuthorizationStatus) {
        UserDefaults.standard.set(status.rawValue, forKey: notificationStatusKey(for: session.email))
    }

    private func refreshNotificationStatusSnapshot() {
        fetchNotificationAuthorizationStatus { [weak self] status in
            self?.saveNotificationStatus(status)
        }
    }

    private func fetchNotificationAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    private func handleNotificationAuthorizationChange(status: UNAuthorizationStatus) {
        saveNotificationStatus(status)

        guard isRequestingNotificationPermission else { return }
        guard status != .notDetermined else { return }

        isRequestingNotificationPermission = false

        switch status {
        case .authorized, .provisional, .ephemeral:
            markNotificationOnboardingCompleted(for: session.email)
            showSimpleToast("Notificações ativadas com sucesso.", style: .success)
        case .denied:
            presentNotificationSettingsPrompt(firstTime: true)
        case .notDetermined:
            break
        @unknown default:
            markNotificationOnboardingCompleted(for: session.email)
        }
    }

    private func continuePermissionOnboarding() {
        DispatchQueue.main.async { [weak self] in
            self?.evaluateNotificationOnboardingIfNeeded()
        }
    }

    private func tag(for section: AppSection) -> Int {
        switch section {
        case .queroReceber:  return 1
        case .queroPagar:    return 2
        case .meuPlano:      return 3
        case .novoContrato:  return 4
        case .promissorias:  return 8
        case .verificacoes:  return 9
        case .agenda:        return 5
        case .localizar:     return 6
        case .perfil:        return 7
        }
    }

    private func section(for tag: Int) -> AppSection? {
        switch tag {
        case 1: return .queroReceber
        case 2: return .queroPagar
        case 3: return .meuPlano
        case 4: return .novoContrato
        case 8: return .promissorias
        case 9: return .verificacoes
        case 5: return .agenda
        case 6: return .localizar
        case 7: return .perfil
        default: return nil
        }
    }

    private func makeBrandView(titleSize: CGFloat, subtitleSize: CGFloat) -> UIView {
        let wrapper = UIView()

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.backgroundColor = UIColor(hex: "#1386BA")
        icon.layer.cornerRadius = 14

        let iconLabel = UILabel()
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.text = "BE"
        iconLabel.textColor = .white
        iconLabel.font = .systemFont(ofSize: 11, weight: .bold)
        iconLabel.textAlignment = .center
        icon.addSubview(iconLabel)

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = -1

        let title = UILabel()
        title.text = "BillEasy.ia"
        title.textColor = UIColor(hex: "#1386BA")
        title.font = .systemFont(ofSize: titleSize, weight: .medium)

        let subtitle = UILabel()
        subtitle.text = "Gestão inteligente. Cobrança eficiente.\nRecebimento seguro."
        subtitle.textColor = UIColor(hex: "#6A7A91")
        subtitle.font = .systemFont(ofSize: subtitleSize, weight: .regular)
        subtitle.numberOfLines = 2

        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(subtitle)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(textStack)
        wrapper.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            iconLabel.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        return wrapper
    }

    private func applyTheme(animated: Bool) {
        let changes = {
            self.applyWindowInterfaceStyle()

            if self.isDarkModeEnabled {
                self.applyDarkThemeColors()
            } else {
                self.applyLightThemeColors()
            }
            self.overlayButton.backgroundColor = UIColor.black.withAlphaComponent(self.isDarkModeEnabled ? 0.52 : 0.36)
            self.themeDimmingView.alpha = 0

            self.refreshMenuSelection()
            self.refreshBottomSelection()
            self.refreshThemeToggleButton()
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(withDuration: 0.22, animations: changes)
    }

    private func applyWindowInterfaceStyle() {
        let style: UIUserInterfaceStyle = isDarkModeEnabled ? .dark : .light
        overrideUserInterfaceStyle = style
        view.window?.overrideUserInterfaceStyle = style
    }

    private func applyDarkThemeColors() {
        view.backgroundColor = UIColor(hex: "#081220")
        contentContainer.backgroundColor = UIColor(hex: "#081220")
        headerView.backgroundColor = UIColor(hex: "#091A2D")
        sideMenuContainer.backgroundColor = UIColor(hex: "#081220")
        sideMenuHeader.backgroundColor = UIColor(hex: "#091A2D")
        sideMenuFooter.backgroundColor = UIColor(hex: "#081220")
        sideMenuFooter.layer.borderColor = UIColor(hex: "#17304B").cgColor
        headerSeparator.backgroundColor = UIColor(hex: "#17304B")
        menuButton.tintColor = UIColor(hex: "#DCE6F3")
        bellButton.tintColor = UIColor(hex: "#DCE6F3")
        sideMenuCloseButton.tintColor = UIColor(hex: "#DCE6F3")
        bottomBar.backgroundColor = UIColor(hex: "#0C1D30")
        bottomBar.layer.borderWidth = 1
        bottomBar.layer.borderColor = UIColor(hex: "#113454", alpha: 0.58).cgColor
        bottomBar.layer.shadowColor = UIColor(hex: "#04101F").cgColor
        bottomBar.layer.shadowOpacity = 0.36
        themeToggleButton.tintColor = UIColor(hex: "#DCE6F3")
    }

    private func applyLightThemeColors() {
        view.backgroundColor = .systemBackground
        contentContainer.backgroundColor = .systemBackground
        headerView.backgroundColor = .secondarySystemBackground
        sideMenuContainer.backgroundColor = .secondarySystemBackground
        sideMenuHeader.backgroundColor = .clear
        sideMenuFooter.backgroundColor = .clear
        sideMenuFooter.layer.borderColor = UIColor.separator.cgColor
        headerSeparator.backgroundColor = .separator
        menuButton.tintColor = .secondaryLabel
        bellButton.tintColor = .secondaryLabel
        sideMenuCloseButton.tintColor = .secondaryLabel
        bottomBar.backgroundColor = .tertiarySystemBackground
        bottomBar.layer.borderWidth = 0
        bottomBar.layer.borderColor = UIColor.clear.cgColor
        bottomBar.layer.shadowColor = UIColor.black.cgColor
        bottomBar.layer.shadowOpacity = 0.18
        themeToggleButton.tintColor = .secondaryLabel
    }

    private func refreshThemeToggleButton() {
        let title = isDarkModeEnabled ? "  Acender as luzes" : "  Apagar as luzes"
        let iconName = isDarkModeEnabled ? "sun.max" : "moon"
        themeToggleButton.setTitle(title, for: .normal)
        themeToggleButton.setImage(UIImage(systemName: iconName), for: .normal)
    }

    private func closeMenuImmediately() {
        sideMenuLeadingConstraint?.constant = -sideMenuWidth
        overlayButton.layer.removeAllAnimations()
        overlayButton.alpha = 0
        overlayButton.isHidden = true
        overlayButton.isUserInteractionEnabled = false
        sideMenuContainer.isUserInteractionEnabled = false
        view.layoutIfNeeded()
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(settingsURL) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func openDebtorLocatorInBrowser() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let url = try await webHandoffService.fetchURL(for: .debtorLocator)
                await MainActor.run {
                    UIApplication.shared.open(url) { [weak self] success in
                        guard success == false else { return }
                        self?.showSimpleToast("Não consegui abrir a versão web agora.", style: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    // MARK: - Notification bell

    private func loadNotificationCount() {
        guard notificacoesService.isRemoteMode else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let count = try await self.notificacoesService.fetchContagem()
                await MainActor.run { self.updateBellBadge(count: count) }
            } catch {
                // Silent fail — badge stays hidden rather than showing stale data
            }
        }
    }

    private func updateBellBadge(count: Int) {
        if count > 0 {
            bellBadge.text = count > 99 ? "99+" : "\(count)"
            bellBadge.isHidden = false
        } else {
            bellBadge.isHidden = true
        }
    }

    @objc private func bellTapped() {
        let vc = NotificacoesViewController(session: session)
        vc.onVoltar = { [weak self, weak vc] in
            vc?.dismiss(animated: true) {
                self?.loadNotificationCount()
            }
        }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    // MARK: - Detail presentation

    private func presentPromissoriaDetalhe(id: String) {
        let vc = PromissoriaDetalheViewController(promissoriaID: id, session: session)
        vc.onVoltar = { [weak vc] in vc?.dismiss(animated: true) }
        vc.onAbrirPDF = { [weak self, weak vc] promissoriaID in
            guard let self else { return }
            vc?.setExternalLoading(true)

            Task { [weak self, weak vc] in
                guard let self else { return }
                do {
                    let data = try await PromissoriasService().baixarDocumento(id: promissoriaID)
                    let safeID = promissoriaID.replacingOccurrences(of: "/", with: "-")
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("promissoria-\(safeID).pdf")
                    try data.write(to: url, options: .atomic)

                    await MainActor.run {
                        vc?.setExternalLoading(false)
                        self.promissoriaPDFPreviewURL = url
                        let previewController = QLPreviewController()
                        previewController.dataSource = self
                        (vc ?? self).present(previewController, animated: true)
                    }
                } catch {
                    await MainActor.run {
                        vc?.setExternalLoading(false)
                        vc?.showSimpleToast(error.localizedDescription, style: .error)
                    }
                }
            }
        }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func presentVerificacaoDetalhe(id: String) {
        let vc = VerificacaoDetalheViewController(verificacaoID: id, session: session)
        vc.onVoltar = { [weak vc] in vc?.dismiss(animated: true) }
        vc.onCapturarSelfie = { [weak self, weak vc] verificacaoID in
            guard let self else { return }
            let selfieVC = SelfieCaptureViewController(verificacaoID: verificacaoID, session: self.session)
            selfieVC.onConcluido = { [weak selfieVC, weak vc] in
                selfieVC?.dismiss(animated: true) {
                    vc?.reloadDetalhe()
                }
            }
            selfieVC.onCancelar = { [weak selfieVC] in
                selfieVC?.dismiss(animated: true)
            }
            selfieVC.modalPresentationStyle = .fullScreen
            self.present(selfieVC, animated: true)
        }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}

extension MainTabBarController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        promissoriaPDFPreviewURL == nil ? 0 : 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        promissoriaPDFPreviewURL! as NSURL
    }
}
