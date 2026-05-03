//
//  OAuthProfileCompletionViewController.swift
//  BillEasy
//

import UIKit

struct OAuthProfileCompletionInput {
    let documento: String
    let telefone: String
}

final class OAuthProfileCompletionViewController: UIViewController, UITextFieldDelegate {
    enum DocumentKind: Int {
        case cpf
        case cnpj

        var title: String {
            switch self {
            case .cpf: return "CPF"
            case .cnpj: return "CNPJ"
            }
        }

        var placeholder: String {
            switch self {
            case .cpf: return "000.000.000-00"
            case .cnpj: return "00.000.000/0000-00"
            }
        }
    }

    var onSubmit: ((OAuthProfileCompletionInput) -> Void)?
    var onCancel: (() -> Void)?

    private let initialDocumento: String?
    private let initialTelefone: String?
    private var selectedKind: DocumentKind = .cpf
    private var isSubmitting = false

    private let dimmingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        return view
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(hex: "#0B1B2B")
        view.layer.cornerRadius = 18
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor(hex: "#1F4666", alpha: 0.8).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.28
        view.layer.shadowRadius = 24
        view.layer.shadowOffset = CGSize(width: 0, height: 18)
        return view
    }()

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 16
        return stackView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Complete seu cadastro"
        label.textColor = .white
        label.applyScaledFont(size: 24, weight: .bold, textStyle: .title2)
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Para criar sua conta com Google, informe CPF/CNPJ e telefone."
        label.textColor = UIColor(hex: "#AAB7C7")
        label.applyScaledFont(size: 15, weight: .regular, textStyle: .body)
        label.numberOfLines = 0
        return label
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor(hex: "#FF8A8A")
        label.applyScaledFont(size: 13, weight: .semibold, textStyle: .footnote)
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let kindControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["CPF", "CNPJ"])
        control.selectedSegmentIndex = 0
        control.selectedSegmentTintColor = UIColor(hex: "#1688B8")
        control.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ], for: .selected)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor(hex: "#AAB7C7"),
            .font: UIFont.systemFont(ofSize: 14, weight: .medium)
        ], for: .normal)
        return control
    }()

    private lazy var documentField = makeInputField(
        placeholder: selectedKind.placeholder,
        keyboardType: .numberPad,
        contentType: nil
    )

    private lazy var phoneField = makeInputField(
        placeholder: "(00) 00000-0000",
        keyboardType: .phonePad,
        contentType: .telephoneNumber
    )

    private let documentCaption = OAuthProfileCompletionViewController.makeCaption("CPF")
    private let phoneCaption = OAuthProfileCompletionViewController.makeCaption("Telefone")
    private let documentUnderline = OAuthProfileCompletionViewController.makeUnderline()
    private let phoneUnderline = OAuthProfileCompletionViewController.makeUnderline()

    private let buttonsStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.distribution = .fillEqually
        return stackView
    }()

    private let cancelButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Cancelar"
        configuration.baseForegroundColor = UIColor(hex: "#AAB7C7")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)

        let button = UIButton(configuration: configuration)
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#284861").cgColor
        return button
    }()

    private let submitButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Concluir cadastro"
        configuration.baseBackgroundColor = UIColor(hex: "#1688B8")
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)

        let button = UIButton(configuration: configuration)
        button.layer.cornerRadius = 16
        return button
    }()

    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(initialDocumento: String? = nil, initialTelefone: String? = nil) {
        self.initialDocumento = initialDocumento
        self.initialTelefone = initialTelefone
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHierarchy()
        setupConstraints()
        setupActions()
        configureInitialValues()
        registerKeyboardNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setSubmitting(_ submitting: Bool) {
        isSubmitting = submitting
        documentField.isEnabled = !submitting
        phoneField.isEnabled = !submitting
        kindControl.isEnabled = !submitting
        cancelButton.isEnabled = !submitting
        submitButton.isEnabled = !submitting

        if submitting {
            loadingIndicator.startAnimating()
            submitButton.configuration?.title = "Enviando"
        } else {
            loadingIndicator.stopAnimating()
            submitButton.configuration?.title = "Concluir cadastro"
        }
    }

    func setError(_ message: String?) {
        let text = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        errorLabel.text = text
        errorLabel.isHidden = text?.isEmpty != false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === documentField {
            phoneField.becomeFirstResponder()
        } else {
            submitTapped()
        }
        return true
    }

    private func setupHierarchy() {
        view.addSubview(dimmingView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(cardView)
        cardView.addSubview(stackView)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(errorLabel)
        stackView.addArrangedSubview(kindControl)
        stackView.addArrangedSubview(makeFieldGroup(caption: documentCaption, field: documentField, underline: documentUnderline))
        stackView.addArrangedSubview(makeFieldGroup(caption: phoneCaption, field: phoneField, underline: phoneUnderline))

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = .white
        buttonsStack.addArrangedSubview(cancelButton)
        buttonsStack.addArrangedSubview(submitButton)
        stackView.addArrangedSubview(buttonsStack)
        submitButton.addSubview(loadingIndicator)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            cardView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            cardView.topAnchor.constraint(greaterThanOrEqualTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 28),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            cardView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            stackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -22),

            documentField.heightAnchor.constraint(equalToConstant: 44),
            phoneField.heightAnchor.constraint(equalToConstant: 44),
            kindControl.heightAnchor.constraint(equalToConstant: 36),
            buttonsStack.heightAnchor.constraint(equalToConstant: 48),

            loadingIndicator.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
            loadingIndicator.trailingAnchor.constraint(equalTo: submitButton.trailingAnchor, constant: -14)
        ])
    }

    private func setupActions() {
        kindControl.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
        documentField.addTarget(self, action: #selector(documentChanged), for: .editingChanged)
        phoneField.addTarget(self, action: #selector(phoneChanged), for: .editingChanged)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
    }

    private func configureInitialValues() {
        let documentDigits = Formatters.digitsOnly(initialDocumento ?? "")
        if documentDigits.count > 11 {
            selectedKind = .cnpj
            kindControl.selectedSegmentIndex = DocumentKind.cnpj.rawValue
        }
        updateDocumentCaption()
        documentField.text = formattedDocument(documentDigits)
        phoneField.text = formattedPhone(initialTelefone ?? "")
    }

    private func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func makeInputField(
        placeholder: String,
        keyboardType: UIKeyboardType,
        contentType: UITextContentType?
    ) -> UITextField {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textColor = .white
        field.tintColor = UIColor(hex: "#4DB9E6")
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(hex: "#60728A")]
        )
        field.keyboardType = keyboardType
        field.textContentType = contentType
        field.delegate = self
        field.returnKeyType = .next
        field.applyScaledFont(size: 18, weight: .regular, textStyle: .body)
        return field
    }

    private func makeFieldGroup(caption: UILabel, field: UITextField, underline: UIView) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: [caption, field, underline])
        stackView.axis = .vertical
        stackView.spacing = 4
        return stackView
    }

    @objc private func kindChanged() {
        selectedKind = DocumentKind(rawValue: kindControl.selectedSegmentIndex) ?? .cpf
        updateDocumentCaption()
        documentField.text = formattedDocument(documentField.text ?? "")
        setError(nil)
    }

    @objc private func documentChanged() {
        documentField.text = formattedDocument(documentField.text ?? "")
        setError(nil)
    }

    @objc private func phoneChanged() {
        phoneField.text = formattedPhone(phoneField.text ?? "")
        setError(nil)
    }

    @objc private func cancelTapped() {
        guard !isSubmitting else { return }
        dismiss(animated: true) { [onCancel] in
            onCancel?()
        }
    }

    @objc private func submitTapped() {
        guard !isSubmitting else { return }
        view.endEditing(true)

        let documento = Formatters.digitsOnly(documentField.text ?? "")
        let telefone = Formatters.digitsOnly(phoneField.text ?? "")

        guard BrazilianDocumentValidator.isValid(documento) else {
            setError("Informe um CPF ou CNPJ válido.")
            documentField.becomeFirstResponder()
            return
        }

        guard telefone.count == 10 || telefone.count == 11 else {
            setError("Informe um telefone válido com DDD.")
            phoneField.becomeFirstResponder()
            return
        }

        setError(nil)
        onSubmit?(OAuthProfileCompletionInput(documento: documento, telefone: telefone))
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let convertedFrame = view.convert(keyboardFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - convertedFrame.minY)
        let bottomInset = notification.name == UIResponder.keyboardWillHideNotification ? 0 : overlap + 18
        scrollView.contentInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    private func updateDocumentCaption() {
        documentCaption.text = selectedKind.title
        documentField.attributedPlaceholder = NSAttributedString(
            string: selectedKind.placeholder,
            attributes: [.foregroundColor: UIColor(hex: "#60728A")]
        )
    }

    private func formattedDocument(_ value: String) -> String {
        switch selectedKind {
        case .cpf:
            return Formatters.formatCPF(value)
        case .cnpj:
            return Formatters.formatCNPJ(value)
        }
    }

    private func formattedPhone(_ value: String) -> String {
        let digits = String(Formatters.digitsOnly(value).prefix(11))
        guard !digits.isEmpty else { return "" }
        switch digits.count {
        case 1...2:
            return "(\(digits)"
        case 3...6:
            let area = digits.prefix(2)
            let body = digits.dropFirst(2)
            return "(\(area)) \(body)"
        case 7...10:
            let area = digits.prefix(2)
            let prefix = digits.dropFirst(2).prefix(4)
            let suffix = digits.dropFirst(6)
            return "(\(area)) \(prefix)-\(suffix)"
        default:
            let area = digits.prefix(2)
            let prefix = digits.dropFirst(2).prefix(5)
            let suffix = digits.dropFirst(7)
            return "(\(area)) \(prefix)-\(suffix)"
        }
    }

    private static func makeCaption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor(hex: "#8EA0B4")
        label.applyScaledFont(size: 13, weight: .semibold, textStyle: .footnote)
        return label
    }

    private static func makeUnderline() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(hex: "#24435C")
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 1)
        ])
        return view
    }
}

enum BrazilianDocumentValidator {
    static func isValid(_ value: String) -> Bool {
        let digits = Formatters.digitsOnly(value)
        switch digits.count {
        case 11: return isValidCPF(digits)
        case 14: return isValidCNPJ(digits)
        default: return false
        }
    }

    static func isValidCPF(_ value: String) -> Bool {
        let digits = Formatters.digitsOnly(value)
        guard digits.count == 11, Set(digits).count > 1 else { return false }
        let numbers = digits.compactMap { Int(String($0)) }
        guard numbers.count == 11 else { return false }

        let first = cpfDigit(numbers: numbers, count: 9, weightStart: 10)
        guard numbers[9] == first else { return false }
        let second = cpfDigit(numbers: numbers, count: 10, weightStart: 11)
        return numbers[10] == second
    }

    static func isValidCNPJ(_ value: String) -> Bool {
        let digits = Formatters.digitsOnly(value)
        guard digits.count == 14, Set(digits).count > 1 else { return false }
        let numbers = digits.compactMap { Int(String($0)) }
        guard numbers.count == 14 else { return false }

        let firstWeights = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        let first = cnpjDigit(numbers: numbers, weights: firstWeights)
        guard numbers[12] == first else { return false }

        let secondWeights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        let second = cnpjDigit(numbers: numbers, weights: secondWeights)
        return numbers[13] == second
    }

    private static func cpfDigit(numbers: [Int], count: Int, weightStart: Int) -> Int {
        let sum = (0..<count).reduce(0) { partial, index in
            partial + numbers[index] * (weightStart - index)
        }
        let remainder = sum % 11
        return remainder < 2 ? 0 : 11 - remainder
    }

    private static func cnpjDigit(numbers: [Int], weights: [Int]) -> Int {
        let sum = weights.indices.reduce(0) { partial, index in
            partial + numbers[index] * weights[index]
        }
        let remainder = sum % 11
        return remainder < 2 ? 0 : 11 - remainder
    }
}
