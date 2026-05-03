//
//  VerificacaoDetalheViewController.swift
//  BillEasy
//

import UIKit

final class VerificacaoDetalheViewController: UIViewController {

    // MARK: - Layout

    private enum Layout {
        static let horizontalMargin: CGFloat = 16
        static let cardCornerRadius: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let contentInset: CGFloat = 16
        static let bottomMargin: CGFloat = 40
    }

    // MARK: - Dependencies

    private let verificacaoID: String
    private let service: VerificacoesService
    private let session: AuthSession

    // MARK: - State

    private var verificacao: Verificacao?
    private var isLoading = false
    private var isTimelineExpanded = false

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    // MARK: - Callbacks

    var onVoltar: (() -> Void)?
    var onCapturarSelfie: ((String) -> Void)?

    // MARK: - Init

    init(
        verificacaoID: String,
        session: AuthSession,
        service: VerificacoesService = VerificacoesService()
    ) {
        self.verificacaoID = verificacaoID
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
        loadDetalhe()
    }

    func reloadDetalhe() {
        loadDetalhe()
    }

    // MARK: - Setup

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Layout.sectionSpacing
        stack.layoutMargins = UIEdgeInsets(
            top: Layout.contentInset,
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

    // MARK: - Data

    private func loadDetalhe() {
        isLoading = true
        renderContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                let v = try await self.service.fetchDetalhe(id: self.verificacaoID)
                await MainActor.run {
                    self.verificacao = v
                    self.isLoading = false
                    self.renderContent()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.renderContent()
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    // MARK: - Rendering

    private func renderContent() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        stack.addArrangedSubview(makeNavBar())

        if isLoading {
            stack.addArrangedSubview(BrandCardFactory.makeLoadingStateCard(
                title: "Carregando verificação",
                subtitle: "Buscando os detalhes da verificação de identidade…"
            ))
            return
        }

        guard let v = verificacao else {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Verificação não encontrada",
                subtitle: "Não foi possível carregar os detalhes. Volte e tente novamente.",
                iconSystemName: "exclamationmark.circle"
            ))
            return
        }

        stack.addArrangedSubview(makeHeroCard(v))

        if v.situacao == .processando {
            stack.addArrangedSubview(makeProcessandoCard())
        }

        if v.situacao.isTerminal {
            stack.addArrangedSubview(makeSectionLabel("RESULTADO KYC"))
            stack.addArrangedSubview(makeResultadoCard(v))
        }

        stack.addArrangedSubview(makeTimelineCard(v))
    }

    // MARK: - View factories

    private func makeNavBar() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle("  Voltar", for: .normal)
        backButton.tintColor = UIColor(hex: "#2E87C8")
        backButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        backButton.addTarget(self, action: #selector(voltarTapped), for: .touchUpInside)
        backButton.accessibilityLabel = "Voltar"

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Verificação"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)

        container.addSubview(backButton)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeHeroCard(_ v: Verificacao) -> UIView {
        let card = makeSurface()

        // Top row: situação badge + short ID ref
        let (badgeBg, badgeText) = v.situacao.badgeColor
        let situacaoBadge = makePill(
            text: v.situacao.displayTitle.uppercased(),
            bg: badgeBg,
            fg: badgeText
        )

        let refLabel = UILabel()
        refLabel.translatesAutoresizingMaskIntoConstraints = false
        let shortId = String(v.id.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
        refLabel.text = "VRF-\(shortId)"
        refLabel.textColor = UIColor(hex: "#9CAABB")
        refLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption1)

        // Avatar circle
        let avatarSize: CGFloat = 88
        let avatarBack = UIView()
        avatarBack.translatesAutoresizingMaskIntoConstraints = false
        avatarBack.backgroundColor = UIColor(hex: "#EAF1F8")
        avatarBack.layer.cornerRadius = avatarSize / 2
        avatarBack.layer.borderWidth = 2
        avatarBack.layer.borderColor = UIColor(hex: "#2E87C8").cgColor

        let personIcon = UIImageView(image: UIImage(systemName: "person.fill"))
        personIcon.translatesAutoresizingMaskIntoConstraints = false
        personIcon.tintColor = v.selfieCapturadoEm != nil ? UIColor(hex: "#2E87C8") : UIColor(hex: "#94A3B8")
        personIcon.contentMode = .scaleAspectFit
        avatarBack.addSubview(personIcon)

        // Selfie captured checkmark overlaid on avatar
        let hasSelfie = v.selfieCapturadoEm != nil
        let checkBadge = UIView()
        checkBadge.translatesAutoresizingMaskIntoConstraints = false
        checkBadge.backgroundColor = UIColor(hex: "#22C55E")
        checkBadge.layer.cornerRadius = 11
        checkBadge.isHidden = !hasSelfie
        let checkIcon = UIImageView(image: UIImage(systemName: "checkmark"))
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        checkIcon.tintColor = .white
        checkIcon.contentMode = .scaleAspectFit
        checkBadge.addSubview(checkIcon)

        // Nome
        let nomeLabel = UILabel()
        nomeLabel.translatesAutoresizingMaskIntoConstraints = false
        nomeLabel.text = v.nomeDisplay
        nomeLabel.textColor = UIColor(hex: "#252E3A")
        nomeLabel.applyScaledFont(size: 18, weight: .semibold, textStyle: .title3)
        nomeLabel.textAlignment = .center
        nomeLabel.numberOfLines = 2

        // Documento
        let docLabel = UILabel()
        docLabel.translatesAutoresizingMaskIntoConstraints = false
        if let formatted = v.documentoDisplay {
            docLabel.text = formatted
        } else if let tipo = v.documentoTipo {
            docLabel.text = tipo.uppercased()
        } else {
            docLabel.text = "Documento não informado"
        }
        docLabel.textColor = UIColor(hex: "#6E7F95")
        docLabel.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)
        docLabel.textAlignment = .center

        // Primary action button (selfie capture / retry)
        let actionButton = UIButton(type: .system)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        var buttonConfig: UIButton.Configuration
        let showAction: Bool

        switch v.situacao {
        case .aguardandoSelfie:
            buttonConfig = .filled()
            buttonConfig.title = "CAPTURAR SELFIE"
            buttonConfig.image = UIImage(systemName: "camera.fill")
            buttonConfig.baseForegroundColor = .white
            buttonConfig.baseBackgroundColor = UIColor(hex: "#2E87C8")
            showAction = true
        case .reprovado:
            buttonConfig = .tinted()
            buttonConfig.title = "TENTAR NOVAMENTE"
            buttonConfig.image = UIImage(systemName: "arrow.counterclockwise")
            actionButton.tintColor = UIColor(hex: "#EF4444")
            showAction = true
        default:
            buttonConfig = .plain()
            showAction = false
        }

        buttonConfig.imagePadding = 8
        buttonConfig.cornerStyle = .large
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        actionButton.configuration = buttonConfig
        actionButton.isHidden = !showAction
        actionButton.addTarget(self, action: #selector(capturarSelfieTapped), for: .touchUpInside)

        card.addSubview(situacaoBadge)
        card.addSubview(refLabel)
        card.addSubview(avatarBack)
        card.addSubview(checkBadge)
        card.addSubview(nomeLabel)
        card.addSubview(docLabel)
        card.addSubview(actionButton)

        NSLayoutConstraint.activate([
            situacaoBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            situacaoBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),

            refLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            refLabel.centerYAnchor.constraint(equalTo: situacaoBadge.centerYAnchor),

            avatarBack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            avatarBack.topAnchor.constraint(equalTo: situacaoBadge.bottomAnchor, constant: 20),
            avatarBack.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarBack.heightAnchor.constraint(equalToConstant: avatarSize),

            personIcon.centerXAnchor.constraint(equalTo: avatarBack.centerXAnchor),
            personIcon.centerYAnchor.constraint(equalTo: avatarBack.centerYAnchor),
            personIcon.widthAnchor.constraint(equalToConstant: 44),
            personIcon.heightAnchor.constraint(equalToConstant: 44),

            checkBadge.widthAnchor.constraint(equalToConstant: 22),
            checkBadge.heightAnchor.constraint(equalToConstant: 22),
            checkBadge.trailingAnchor.constraint(equalTo: avatarBack.trailingAnchor, constant: 2),
            checkBadge.bottomAnchor.constraint(equalTo: avatarBack.bottomAnchor, constant: 2),
            checkIcon.centerXAnchor.constraint(equalTo: checkBadge.centerXAnchor),
            checkIcon.centerYAnchor.constraint(equalTo: checkBadge.centerYAnchor),
            checkIcon.widthAnchor.constraint(equalToConstant: 12),
            checkIcon.heightAnchor.constraint(equalToConstant: 12),

            nomeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            nomeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            nomeLabel.topAnchor.constraint(equalTo: avatarBack.bottomAnchor, constant: 14),

            docLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            docLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            docLabel.topAnchor.constraint(equalTo: nomeLabel.bottomAnchor, constant: 4),

            actionButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            actionButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            actionButton.topAnchor.constraint(equalTo: docLabel.bottomAnchor, constant: 16),
            actionButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        // When no action button is shown, collapse it to zero height
        if !showAction {
            actionButton.heightAnchor.constraint(equalToConstant: 0).isActive = true
            // Move bottom anchor to docLabel directly
            docLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset).isActive = true
        }

        return card
    }

    private func makeProcessandoCard() -> UIView {
        let card = makeSurface()

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = UIColor(hex: "#2E87C8")
        spinner.startAnimating()

        let label = UILabel()
        label.text = "Estamos analisando sua verificação. Você será notificado em instantes."
        label.textColor = UIColor(hex: "#6E7F95")
        label.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)
        label.textAlignment = .center
        label.numberOfLines = 0

        let inner = UIStackView(arrangedSubviews: [spinner, label])
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.axis = .vertical
        inner.alignment = .center
        inner.spacing = 10

        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        return card
    }

    private func makeResultadoCard(_ v: Verificacao) -> UIView {
        let card = makeSurface()

        let accentColor: UIColor
        switch v.situacao {
        case .aprovado:  accentColor = UIColor(hex: "#22C55E")
        case .reprovado: accentColor = UIColor(hex: "#EF4444")
        default:         accentColor = UIColor(hex: "#6E7F95")
        }

        let accentBar = UIView()
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.backgroundColor = accentColor
        accentBar.layer.cornerRadius = 2

        let infoStack = UIStackView()
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.spacing = 8

        if let scoreText = v.scoreFormatado {
            infoStack.addArrangedSubview(makeInfoRow(label: "Score", value: scoreText))
        }

        if let match = v.resultadoMatchDocumento {
            infoStack.addArrangedSubview(makeInfoRow(
                label: "Match documento",
                value: match ? "Sim ✓" : "Não ✗",
                valueColor: match ? UIColor(hex: "#22C55E") : UIColor(hex: "#EF4444")
            ))
        }

        if let resolvidoDisplay = v.resolvidoEmDisplay {
            infoStack.addArrangedSubview(makeInfoRow(label: "Resultado em", value: resolvidoDisplay))
        }

        if v.situacao == .reprovado, let motivo = v.resultadoMotivo, !motivo.isEmpty {
            let motivoLabel = UILabel()
            motivoLabel.text = "Motivo: \(motivo)"
            motivoLabel.textColor = UIColor(hex: "#EF4444")
            motivoLabel.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)
            motivoLabel.numberOfLines = 0
            infoStack.addArrangedSubview(motivoLabel)
        }

        if infoStack.arrangedSubviews.isEmpty {
            let fallback = UILabel()
            fallback.text = v.situacao == .aprovado
                ? "Verificação concluída com sucesso."
                : "Sem detalhes adicionais disponíveis."
            fallback.textColor = UIColor(hex: "#6E7F95")
            fallback.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)
            infoStack.addArrangedSubview(fallback)
        }

        card.addSubview(accentBar)
        card.addSubview(infoStack)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            accentBar.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            accentBar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset),
            accentBar.widthAnchor.constraint(equalToConstant: 4),

            infoStack.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            infoStack.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            infoStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        return card
    }

    private func makeTimelineCard(_ v: Verificacao) -> UIView {
        let events = buildTimelineEvents(v)
        let card = makeSurface()

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 0

        contentStack.addArrangedSubview(makeTimelineHeader(eventCount: events.count))

        if isTimelineExpanded && !events.isEmpty {
            let spacer = UIView()
            spacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
            contentStack.addArrangedSubview(spacer)

            let separator = UIView()
            separator.backgroundColor = UIColor(hex: "#E2E8F0")
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            contentStack.addArrangedSubview(separator)

            let spacer2 = UIView()
            spacer2.heightAnchor.constraint(equalToConstant: 12).isActive = true
            contentStack.addArrangedSubview(spacer2)

            for (idx, event) in events.enumerated() {
                contentStack.addArrangedSubview(makeTimelineRow(
                    event: event,
                    isLast: idx == events.count - 1
                ))
            }
        }

        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        return card
    }

    private func makeTimelineHeader(eventCount: Int) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true
        container.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(timelineHeaderTapped)))

        let text = eventCount == 0
            ? "Histórico"
            : "Histórico (\(eventCount) \(eventCount == 1 ? "evento" : "eventos"))"

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = text
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)

        let chevron = UIImageView(image: UIImage(systemName: isTimelineExpanded ? "chevron.up" : "chevron.down"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = UIColor(hex: "#9CAABB")

        container.addSubview(titleLabel)
        container.addSubview(chevron)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16)
        ])

        return container
    }

    private func makeTimelineRow(event: TimelineEvent, isLast: Bool) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = event.color
        dot.layer.cornerRadius = 5

        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = UIColor(hex: "#D7DEE8")
        line.isHidden = isLast

        let tagLabel = UILabel()
        tagLabel.translatesAutoresizingMaskIntoConstraints = false
        tagLabel.text = event.tag
        tagLabel.textColor = event.color
        tagLabel.applyScaledFont(size: 9, weight: .bold, textStyle: .caption2)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = event.title
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)

        let dateLabel = UILabel()
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.text = event.dateDisplay
        dateLabel.textColor = UIColor(hex: "#9CAABB")
        dateLabel.applyScaledFont(size: 11, weight: .regular, textStyle: .caption1)

        let textStack = UIStackView(arrangedSubviews: [tagLabel, titleLabel, dateLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        container.addSubview(dot)
        container.addSubview(line)
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dot.topAnchor.constraint(equalTo: textStack.topAnchor, constant: 4),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            line.centerXAnchor.constraint(equalTo: dot.centerXAnchor),
            line.topAnchor.constraint(equalTo: dot.bottomAnchor, constant: 4),
            line.widthAnchor.constraint(equalToConstant: 2),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: container.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: isLast ? 0 : -16)
        ])

        return container
    }

    // MARK: - Helper views

    private func makeSurface() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor(hex: "#F8FAFC")
        v.layer.cornerRadius = Layout.cardCornerRadius
        v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        return v
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor(hex: "#4B6378")
        label.applyScaledFont(size: 11, weight: .semibold, textStyle: .footnote)
        label.accessibilityTraits = [.header]
        return label
    }

    private func makePill(text: String, bg: String, fg: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(hex: bg)
        container.layer.cornerRadius = 8
        container.layer.cornerCurve = .continuous

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor(hex: fg)
        label.applyScaledFont(size: 10, weight: .bold, textStyle: .caption1)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    private func makeInfoRow(
        label: String,
        value: String,
        valueColor: UIColor = UIColor(hex: "#252E3A")
    ) -> UIView {
        let labelView = UILabel()
        labelView.text = label
        labelView.textColor = UIColor(hex: "#6E7F95")
        labelView.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)

        let valueView = UILabel()
        valueView.text = value
        valueView.textColor = valueColor
        valueView.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)
        valueView.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [labelView, valueView])
        row.axis = .horizontal
        row.distribution = .fill
        row.alignment = .center
        return row
    }

    // MARK: - Timeline helpers

    private struct TimelineEvent {
        let tag: String
        let title: String
        let dateDisplay: String
        let color: UIColor
    }

    private func buildTimelineEvents(_ v: Verificacao) -> [TimelineEvent] {
        var events: [TimelineEvent] = []

        if let date = v.solicitadoEm {
            events.append(TimelineEvent(
                tag: "SOLICITAÇÃO",
                title: "Verificação solicitada",
                dateDisplay: Formatters.shortDate.string(from: date),
                color: UIColor(hex: "#2E87C8")
            ))
        }

        if let date = v.selfieCapturadoEm {
            events.append(TimelineEvent(
                tag: "SELFIE",
                title: "Selfie capturada",
                dateDisplay: Formatters.shortDate.string(from: date),
                color: UIColor(hex: "#F59E0B")
            ))
        }

        if let date = v.resolvidoEm {
            let (title, hex): (String, String)
            switch v.situacao {
            case .aprovado:  (title, hex) = ("Verificação aprovada", "#22C55E")
            case .reprovado: (title, hex) = ("Verificação reprovada", "#EF4444")
            case .cancelado: (title, hex) = ("Verificação cancelada", "#94A3B8")
            default:         (title, hex) = ("Resultado processado", "#2E87C8")
            }
            events.append(TimelineEvent(
                tag: "RESULTADO",
                title: title,
                dateDisplay: Formatters.shortDate.string(from: date),
                color: UIColor(hex: hex)
            ))
        }

        return events
    }

    // MARK: - Actions

    @objc private func voltarTapped() {
        onVoltar?()
    }

    @objc private func capturarSelfieTapped() {
        onCapturarSelfie?(verificacaoID)
    }

    @objc private func timelineHeaderTapped() {
        isTimelineExpanded.toggle()
        renderContent()
    }
}
