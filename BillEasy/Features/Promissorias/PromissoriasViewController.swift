//
//  PromissoriasViewController.swift
//  BillEasy
//

import UIKit

final class PromissoriasViewController: UIViewController {

    // MARK: - Layout

    private enum Layout {
        static let horizontalMargin: CGFloat = 14
        static let topMargin: CGFloat = 16
        static let bottomMargin: CGFloat = 28
        static let cardCornerRadius: CGFloat = 16
        static let contentInset: CGFloat = 14
    }

    // MARK: - Dependencies

    private let service: PromissoriasService
    private let session: AuthSession

    // MARK: - State

    private var promissorias: [Promissoria] = []
    private var isLoading = false

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let refreshControl = UIRefreshControl()

    // MARK: - Callbacks

    var onAbrirDetalhe: ((String) -> Void)?
    var onNovaPromissoria: (() -> Void)?

    // MARK: - Init

    init(session: AuthSession, service: PromissoriasService = PromissoriasService()) {
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
        loadPromissorias()
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

    private func loadPromissorias() {
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
                    self.promissorias = items.sorted { a, b in
                        a.criadoEm ?? .distantPast > b.criadoEm ?? .distantPast
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

        if isLoading && promissorias.isEmpty {
            stack.addArrangedSubview(BrandCardFactory.makeLoadingStateCard(
                title: "Carregando promissórias",
                subtitle: "Buscando suas notas promissórias no servidor…"
            ))
            return
        }

        if !service.isRemoteMode {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Modo local ativo",
                subtitle: "Promissórias estão disponíveis apenas no modo remoto.",
                iconSystemName: "doc.text.fill"
            ))
            return
        }

        if promissorias.isEmpty {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Nenhuma promissória",
                subtitle: "Crie sua primeira nota promissória para formalizar operações de crédito com segurança jurídica.",
                iconSystemName: "doc.text.fill"
            ))
            return
        }

        for promissoria in promissorias {
            let card = makePromissoriaCard(promissoria)
            stack.addArrangedSubview(card)
        }
    }

    // MARK: - View factories

    private func makeHeader() -> UIView {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let iconBack = UIView()
        iconBack.translatesAutoresizingMaskIntoConstraints = false
        iconBack.backgroundColor = UIColor(hex: "#D9E9F6")
        iconBack.layer.cornerRadius = 18
        iconBack.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "doc.text.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#2E87C8")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Promissórias"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 28, weight: .bold, textStyle: .largeTitle)
        titleLabel.accessibilityTraits = [.header]

        let novaButton = UIButton(type: .system)
        novaButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = "Nova"
        config.image = UIImage(systemName: "plus")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor(hex: "#2E87C8")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        novaButton.configuration = config
        novaButton.addTarget(self, action: #selector(novaPromissoriaTapped), for: .touchUpInside)
        novaButton.accessibilityLabel = "Nova Promissória"

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Notas promissórias digitais"
        subtitleLabel.textColor = UIColor(hex: "#688097")
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)

        header.addSubview(titleLabel)
        header.addSubview(novaButton)
        header.addSubview(iconBack)
        iconBack.addSubview(icon)
        header.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 72),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 4),

            novaButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            novaButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            subtitleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            iconBack.trailingAnchor.constraint(equalTo: novaButton.leadingAnchor, constant: -10),
            iconBack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconBack.widthAnchor.constraint(equalToConstant: 36),
            iconBack.heightAnchor.constraint(equalToConstant: 36),

            icon.centerXAnchor.constraint(equalTo: iconBack.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBack.centerYAnchor)
        ])

        return header
    }

    private func makePromissoriaCard(_ p: Promissoria) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(hex: "#F8FAFC")
        card.layer.cornerRadius = Layout.cardCornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        card.isUserInteractionEnabled = true
        card.accessibilityTraits = [.button]
        card.accessibilityLabel = "Promissória \(p.valorDisplay)"
        card.accessibilityValue = "\(p.etapa.displayTitle), vencimento \(p.primeiroVencimentoDisplay)"

        let tap = UITapGestureRecognizer(target: self, action: #selector(promissoriaTapped(_:)))
        card.addGestureRecognizer(tap)
        card.tag = promissorias.firstIndex(where: { $0.id == p.id }) ?? 0

        // Etapa badge
        let (badgeBg, badgeText) = p.etapa.badgeColor
        let badgeView = UIView()
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.backgroundColor = UIColor(hex: badgeBg)
        badgeView.layer.cornerRadius = 8
        badgeView.layer.cornerCurve = .continuous

        let badgeLabel = UILabel()
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.text = p.etapa.displayTitle.uppercased()
        badgeLabel.textColor = UIColor(hex: badgeText)
        badgeLabel.applyScaledFont(size: 10, weight: .bold, textStyle: .caption1)
        badgeView.addSubview(badgeLabel)

        // Valor
        let valorLabel = UILabel()
        valorLabel.translatesAutoresizingMaskIntoConstraints = false
        valorLabel.text = p.valorDisplay
        valorLabel.textColor = UIColor(hex: "#252E3A")
        valorLabel.applyScaledFont(size: 22, weight: .bold, textStyle: .title2)

        // Método de pagamento
        let metodoLabel = UILabel()
        metodoLabel.translatesAutoresizingMaskIntoConstraints = false
        metodoLabel.text = p.quantidadeParcelas > 1
            ? "\(p.quantidadeParcelas)x · \(p.metodoPagamentoDisplay)"
            : "À vista · \(p.metodoPagamentoDisplay)"
        metodoLabel.textColor = UIColor(hex: "#5A7291")
        metodoLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .subheadline)

        // Partes
        let emissorNome = p.emissor?.nome ?? "—"
        let beneficiarioNome = p.beneficiario?.nome ?? "—"
        let partesLabel = UILabel()
        partesLabel.translatesAutoresizingMaskIntoConstraints = false
        partesLabel.text = "\(emissorNome) → \(beneficiarioNome)"
        partesLabel.textColor = UIColor(hex: "#6E7F95")
        partesLabel.applyScaledFont(size: 13, weight: .regular, textStyle: .subheadline)
        partesLabel.numberOfLines = 2

        // Vencimento
        let vencLabel = UILabel()
        vencLabel.translatesAutoresizingMaskIntoConstraints = false
        vencLabel.text = "Venc. \(p.primeiroVencimentoDisplay)"
        vencLabel.textColor = UIColor(hex: "#9CAABB")
        vencLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption1)

        // Chevron
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = UIColor(hex: "#B0C6DD")
        chevron.contentMode = .scaleAspectFit

        card.addSubview(badgeView)
        card.addSubview(valorLabel)
        card.addSubview(metodoLabel)
        card.addSubview(partesLabel)
        card.addSubview(vencLabel)
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            badgeLabel.leadingAnchor.constraint(equalTo: badgeView.leadingAnchor, constant: 8),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: -8),
            badgeLabel.topAnchor.constraint(equalTo: badgeView.topAnchor, constant: 4),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeView.bottomAnchor, constant: -4),

            badgeView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            badgeView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),

            valorLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            valorLabel.topAnchor.constraint(equalTo: badgeView.bottomAnchor, constant: 8),
            valorLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            metodoLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            metodoLabel.topAnchor.constraint(equalTo: valorLabel.bottomAnchor, constant: 4),

            partesLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            partesLabel.topAnchor.constraint(equalTo: metodoLabel.bottomAnchor, constant: 8),
            partesLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            vencLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            vencLabel.topAnchor.constraint(equalTo: partesLabel.bottomAnchor, constant: 6),
            vencLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),

            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 18)
        ])

        return card
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        promissorias = []
        loadPromissorias()
    }

    @objc private func novaPromissoriaTapped() {
        onNovaPromissoria?()
    }

    @objc private func promissoriaTapped(_ gesture: UITapGestureRecognizer) {
        guard let cardView = gesture.view, cardView.tag < promissorias.count else { return }
        let id = promissorias[cardView.tag].id
        onAbrirDetalhe?(id)
    }
}
