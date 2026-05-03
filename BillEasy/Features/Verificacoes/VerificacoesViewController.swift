//
//  VerificacoesViewController.swift
//  BillEasy
//

import UIKit

final class VerificacoesViewController: UIViewController {

    // MARK: - Layout

    private enum Layout {
        static let horizontalMargin: CGFloat = 14
        static let topMargin: CGFloat = 16
        static let bottomMargin: CGFloat = 28
        static let cardCornerRadius: CGFloat = 14
        static let contentInset: CGFloat = 14
    }

    // MARK: - Dependencies

    private let service: VerificacoesService
    private let session: AuthSession

    // MARK: - State

    private var verificacoes: [Verificacao] = []
    private var isLoading = false

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let refreshControl = UIRefreshControl()

    // MARK: - Callbacks

    var onAbrirDetalhe: ((String) -> Void)?

    // MARK: - Init

    init(session: AuthSession, service: VerificacoesService = VerificacoesService()) {
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadVerificacoes()
    }

    // MARK: - Setup

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.refreshControl = refreshControl
        refreshControl.tintColor = UIColor(hex: "#2E87C8")
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
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

    // MARK: - Data

    private func loadVerificacoes() {
        guard service.isRemoteMode else {
            renderContent()
            return
        }
        guard !isLoading else { return }
        isLoading = true
        renderContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.service.fetchMinhas()
                await MainActor.run {
                    self.verificacoes = items.sorted {
                        $0.solicitadoEm ?? .distantPast > $1.solicitadoEm ?? .distantPast
                    }
                    self.isLoading = false
                    self.refreshControl.endRefreshing()
                    self.renderContent()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.refreshControl.endRefreshing()
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

        stack.addArrangedSubview(makeHeader())

        if isLoading && verificacoes.isEmpty {
            stack.addArrangedSubview(BrandCardFactory.makeLoadingStateCard(
                title: "Carregando verificações",
                subtitle: "Buscando suas verificações de identidade…"
            ))
            return
        }

        if !service.isRemoteMode {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Modo local ativo",
                subtitle: "Verificações de identidade estão disponíveis apenas no modo remoto.",
                iconSystemName: "person.badge.shield.checkmark.fill"
            ))
            return
        }

        if verificacoes.isEmpty {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Nenhuma verificação",
                subtitle: "Quando uma nota promissória exigir verificação de identidade, ela aparecerá aqui.",
                iconSystemName: "person.badge.shield.checkmark.fill"
            ))
            return
        }

        for v in verificacoes {
            stack.addArrangedSubview(makeVerificacaoCard(v))
        }
    }

    // MARK: - View factories

    private func makeHeader() -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let iconBack = UIView()
        iconBack.translatesAutoresizingMaskIntoConstraints = false
        iconBack.backgroundColor = UIColor(hex: "#D9E9F6")
        iconBack.layer.cornerRadius = 18
        iconBack.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "person.badge.shield.checkmark.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#2E87C8")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Verificações"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 28, weight: .bold, textStyle: .largeTitle)
        titleLabel.accessibilityTraits = [.header]

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Verificação de identidade (KYC)"
        subtitleLabel.textColor = UIColor(hex: "#688097")
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)

        wrapper.addSubview(iconBack)
        iconBack.addSubview(icon)
        wrapper.addSubview(titleLabel)
        wrapper.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 64),

            iconBack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            iconBack.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            iconBack.widthAnchor.constraint(equalToConstant: 36),
            iconBack.heightAnchor.constraint(equalToConstant: 36),

            icon.centerXAnchor.constraint(equalTo: iconBack.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBack.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),

            subtitleLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
        ])

        return wrapper
    }

    private func makeVerificacaoCard(_ v: Verificacao) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(hex: "#F8FAFC")
        card.layer.cornerRadius = Layout.cardCornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        card.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
        card.addGestureRecognizer(tap)
        card.tag = verificacoes.firstIndex(where: { $0.id == v.id }) ?? 0

        card.accessibilityTraits = [.button]
        card.accessibilityLabel = v.nomeDisplay
        card.accessibilityValue = v.situacao.displayTitle

        let (badgeBg, badgeText) = v.situacao.badgeColor
        let badge = makePill(text: v.situacao.displayTitle.uppercased(), bg: badgeBg, fg: badgeText)
        badge.translatesAutoresizingMaskIntoConstraints = false

        let nomeLabel = UILabel()
        nomeLabel.translatesAutoresizingMaskIntoConstraints = false
        nomeLabel.text = v.nomeDisplay
        nomeLabel.textColor = UIColor(hex: "#252E3A")
        nomeLabel.applyScaledFont(size: 16, weight: .semibold, textStyle: .body)
        nomeLabel.numberOfLines = 2

        let docLabel = UILabel()
        docLabel.translatesAutoresizingMaskIntoConstraints = false
        docLabel.text = v.documentoDisplay ?? (v.documentoTipo?.uppercased() ?? "Documento não informado")
        docLabel.textColor = UIColor(hex: "#6E7F95")
        docLabel.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)

        let dataLabel = UILabel()
        dataLabel.translatesAutoresizingMaskIntoConstraints = false
        dataLabel.text = v.solicitadoEmDisplay.map { "Solicitado em \($0)" } ?? "—"
        dataLabel.textColor = UIColor(hex: "#9CAABB")
        dataLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption1)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = UIColor(hex: "#B0C6DD")

        let selfieIcon: UIView
        if v.situacao.needsSelfie {
            let iv = UIImageView(image: UIImage(systemName: "camera.fill"))
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.tintColor = UIColor(hex: "#F59E0B")
            selfieIcon = iv
        } else {
            selfieIcon = UIView()
        }

        card.addSubview(badge)
        card.addSubview(nomeLabel)
        card.addSubview(docLabel)
        card.addSubview(dataLabel)
        card.addSubview(chevron)
        card.addSubview(selfieIcon)

        selfieIcon.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),

            selfieIcon.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            selfieIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            selfieIcon.widthAnchor.constraint(equalToConstant: 20),
            selfieIcon.heightAnchor.constraint(equalToConstant: 20),

            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 18),

            nomeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            nomeLabel.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 8),
            nomeLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            docLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            docLabel.topAnchor.constraint(equalTo: nomeLabel.bottomAnchor, constant: 4),

            dataLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            dataLabel.topAnchor.constraint(equalTo: docLabel.bottomAnchor, constant: 6),
            dataLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func makePill(text: String, bg: String, fg: String) -> UIView {
        let container = UIView()
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

    // MARK: - Actions

    @objc private func handleRefresh() {
        verificacoes = []
        loadVerificacoes()
    }

    @objc private func cardTapped(_ gesture: UITapGestureRecognizer) {
        guard let cardView = gesture.view, cardView.tag < verificacoes.count else { return }
        let id = verificacoes[cardView.tag].id
        onAbrirDetalhe?(id)
    }
}
