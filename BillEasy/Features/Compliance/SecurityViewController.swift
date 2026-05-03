//
//  SecurityViewController.swift
//  BillEasy
//

import LocalAuthentication
import UIKit

/// Aqui eu concentro a tela local de segurança com preferências simples de MFA e biometria.
final class SecurityViewController: UIViewController {
    private let dataStore: LocalAppDataStore

    private let mfaSwitch = UISwitch()
    private let biometricSwitch = UISwitch()
    private let passwordDateLabel = UILabel()
    private let passwordInfoCard = UIView()

    init(dataStore: LocalAppDataStore) {
        self.dataStore = dataStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Segurança"
        view.backgroundColor = UIColor(hex: "#E6EAEE")
        setupLayout()
        reloadData()
    }

    /// Aqui eu monto o layout vertical das configurações de segurança.
    private func setupLayout() {
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 18

        let introCard = BrandCardFactory.makeEmptyStateCard(
            title: "Segurança da conta",
            subtitle: "Aqui eu acompanho preferências locais de autenticação reforçada e biometria do dispositivo.",
            iconSystemName: "lock.shield"
        )

        let mfaRow = makeSwitchCard(
            title: "MFA habilitado",
            subtitle: "Exige uma etapa extra de verificação para entrar na conta.",
            toggle: mfaSwitch
        )
        let biometricRow = makeSwitchCard(
            title: "Biometria para abrir app",
            subtitle: "Usa Face ID ou Touch ID quando disponível no aparelho.",
            toggle: biometricSwitch
        )

        passwordDateLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .subheadline)
        passwordDateLabel.textColor = .secondaryLabel
        passwordDateLabel.numberOfLines = 0

        passwordInfoCard.backgroundColor = UIColor(hex: "#F8FAFC")
        passwordInfoCard.layer.cornerRadius = 14
        passwordInfoCard.layer.cornerCurve = .continuous
        passwordInfoCard.layer.borderWidth = 1
        passwordInfoCard.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        passwordInfoCard.addSubview(passwordDateLabel)

        content.addArrangedSubview(introCard)
        content.addArrangedSubview(mfaRow)
        content.addArrangedSubview(biometricRow)
        content.addArrangedSubview(passwordInfoCard)

        view.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            passwordDateLabel.topAnchor.constraint(equalTo: passwordInfoCard.topAnchor, constant: 16),
            passwordDateLabel.leadingAnchor.constraint(equalTo: passwordInfoCard.leadingAnchor, constant: 16),
            passwordDateLabel.trailingAnchor.constraint(equalTo: passwordInfoCard.trailingAnchor, constant: -16),
            passwordDateLabel.bottomAnchor.constraint(equalTo: passwordInfoCard.bottomAnchor, constant: -16)
        ])

        mfaSwitch.addTarget(self, action: #selector(securityChanged), for: .valueChanged)
        biometricSwitch.addTarget(self, action: #selector(securityChanged), for: .valueChanged)
        mfaSwitch.accessibilityLabel = "MFA habilitado"
        biometricSwitch.accessibilityLabel = "Biometria para abrir app"
    }

    /// Aqui eu salvo as preferências de segurança, verificando disponibilidade de biometria antes de aceitar.
    @objc private func securityChanged() {
        if biometricSwitch.isOn {
            verifyBiometricAvailability { [weak self] available in
                guard let self else { return }
                if available {
                    self.commitSecurityChange()
                } else {
                    // Reverte o toggle — biometria indisponível neste dispositivo.
                    self.biometricSwitch.setOn(false, animated: true)
                }
            }
        } else {
            commitSecurityChange()
        }
    }

    /// Aqui eu persisto as preferências de segurança após validação.
    private func commitSecurityChange() {
        dataStore.updateSecurity(
            mfaEnabled: mfaSwitch.isOn,
            biometricEnabled: biometricSwitch.isOn
        )
        reloadData()
    }

    /// Aqui eu verifico se o dispositivo suporta biometria e mostro alerta se não suportar.
    private func verifyBiometricAvailability(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let message: String
                if let laError = error as? LAError, laError.code == .biometryNotEnrolled {
                    message = "Nenhuma biometria cadastrada. Configure Face ID ou Touch ID nas Configurações do dispositivo."
                } else {
                    message = "Este dispositivo não suporta autenticação biométrica."
                }
                let alert = UIAlertController(
                    title: "Biometria indisponível",
                    message: message,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                completion(false)
            }
            return
        }

        completion(true)
    }

    /// Aqui eu reaproveito a mesma linha para qualquer configuração baseada em chave liga/desliga.
    private func makeSwitchCard(title: String, subtitle: String, toggle: UISwitch) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(hex: "#F8FAFC")
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 4

        let label = UILabel()
        label.text = title
        label.textColor = UIColor(hex: "#2A3442")
        label.applyScaledFont(size: 16, weight: .semibold, textStyle: .body)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor(hex: "#607993")
        subtitleLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)
        subtitleLabel.numberOfLines = 0

        textStack.addArrangedSubview(label)
        textStack.addArrangedSubview(subtitleLabel)

        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(toggle)
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    /// Aqui eu sincronizo a UI com o último estado salvo no data store local.
    private func reloadData() {
        let settings = dataStore.fetchSecuritySettings()
        mfaSwitch.setOn(settings.mfaEnabled, animated: true)
        biometricSwitch.setOn(settings.biometricEnabled, animated: true)
        passwordDateLabel.text = "Última troca de senha: \(Formatters.dateTime.string(from: settings.lastPasswordChangeAt))"
        passwordInfoCard.isAccessibilityElement = true
        passwordInfoCard.accessibilityLabel = "Última troca de senha"
        passwordInfoCard.accessibilityValue = passwordDateLabel.text
    }
}
