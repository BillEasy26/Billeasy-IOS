//
//  Formatters.swift
//  BillEasy
//

import Foundation

/// Coleção de formatadores reutilizáveis para moeda, data e máscaras de documentos brasileiros.
/// Todos os formatadores estáticos são instanciados uma única vez (lazy) para evitar overhead de criação repetida.
enum Formatters {

    // MARK: - Formatadores base (reutilizáveis)

    /// Formata valores monetários no padrão real brasileiro (R$ 1.234,56).
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    /// Formata data e hora no padrão brasileiro curto (ex.: 26/04/2026 14:30).
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    /// Formata apenas a data no padrão brasileiro curto (ex.: 26/04/2026), sem horário.
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// Formata data no padrão numérico completo brasileiro (dd/MM/yyyy).
    static let fullNumericDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    /// Formata data no padrão ISO 8601 sem horário (yyyy-MM-dd). Usado para normalizar datas vindas de OCR.
    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Formata data e hora no padrão ISO 8601 sem timezone (yyyy-MM-dd'T'HH:mm:ss). Usado para normalizar datas do backend.
    private static let isoDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    // MARK: - Moeda

    /// Converte um `Decimal` em texto formatado como real brasileiro (ex.: `R$ 1.234,56`).
    /// Remove o espaço não separável (`\u{00A0}`) que o `NumberFormatter` insere em alguns locais.
    static func currencyText(from amount: Decimal) -> String {
        let formatted = currency.string(from: NSDecimalNumber(decimal: amount)) ?? "R$ 0,00"
        return formatted.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Formata a digitação contínua de um valor monetário (ex.: o usuário digita `1234` → exibe `R$ 12,34`).
    /// Trata o número como centavos, dividindo por 100 antes de formatar.
    static func formatCurrencyInput(_ value: String) -> String {
        let digits = digitsOnly(value)
        guard let cents = Decimal(string: digits), !digits.isEmpty else { return "" }
        return currencyText(from: cents / 100)
    }

    /// Converte o texto de um campo monetário editável em `Decimal`, tratando o valor como centavos.
    static func decimalFromCurrencyInput(_ value: String) -> Decimal {
        let digits = digitsOnly(value)
        guard let cents = Decimal(string: digits), !digits.isEmpty else { return .zero }
        return cents / 100
    }

    /// Interpreta um texto monetário já formatado (vindo de OCR, backend ou payloads de IA)
    /// e retorna o valor como `Decimal`. Suporta os formatos `R$ 1.234,56`, `1234.56` e `1234,56`.
    static func decimalFromCurrencyString(_ value: String) -> Decimal? {
        let sanitized = value
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty else { return nil }
        let compact = sanitized.replacingOccurrences(of: " ", with: "")

        // Formato brasileiro com ponto de milhar e vírgula decimal: 1.234,56
        if compact.contains(",") && compact.contains(".") {
            let normalized = compact.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            return Decimal(string: normalized)
        }
        // Apenas vírgula decimal: 1234,56
        if compact.contains(",") {
            return Decimal(string: compact.replacingOccurrences(of: ",", with: "."))
        }
        // Ponto como separador decimal (≤ 2 casas): 1234.56
        if compact.contains(".") {
            let components = compact.split(separator: ".", omittingEmptySubsequences: false)
            if components.count == 2, let decimalDigits = components.last?.count, decimalDigits <= 2 {
                return Decimal(string: compact)
            }
            // Ponto como separador de milhar: 1.234 → 1234
            return Decimal(string: compact.replacingOccurrences(of: ".", with: ""))
        }
        return Decimal(string: digitsOnly(compact))
    }

    /// Normaliza textos monetários variados para o formato padrão `R$ 1.234,56`.
    /// Se a conversão falhar, retorna o valor original apenas removendo espaços não separáveis.
    static func normalizeCurrencyDisplay(_ value: String) -> String {
        guard let decimal = decimalFromCurrencyString(value) else {
            return value.replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        return currencyText(from: decimal)
    }

    // MARK: - Data

    /// Tenta normalizar textos de data vindos de IA/OCR para o formato `dd/MM/yyyy`.
    /// Tenta os formatadores em ordem: numérico BR, data curta, ISO date, ISO datetime.
    /// Retorna o valor original se nenhum formato for reconhecido.
    static func normalizeDateDisplay(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }

        let formatters: [DateFormatter] = [fullNumericDate, shortDate, isoDate, isoDateTime]
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return fullNumericDate.string(from: date)
            }
        }
        return value
    }

    // MARK: - Utilitários

    /// Remove todos os caracteres não numéricos de uma string (útil para limpar CPF, CNPJ, CEP, etc.).
    static func digitsOnly(_ value: String) -> String {
        String(value.filter(\.isNumber))
    }

    // MARK: - Máscaras de documentos

    /// Aplica a máscara de CPF: `###.###.###-##` (máximo 11 dígitos).
    static func formatCPF(_ value: String) -> String {
        let raw = String(digitsOnly(value).prefix(11))
        guard !raw.isEmpty else { return "" }
        var result = ""
        for (index, character) in raw.enumerated() {
            switch index {
            case 3, 6: result.append(".")
            case 9: result.append("-")
            default: break
            }
            result.append(character)
        }
        return result
    }

    /// Aplica a máscara de CNPJ: `##.###.###/####-##` (máximo 14 dígitos).
    static func formatCNPJ(_ value: String) -> String {
        let raw = String(digitsOnly(value).prefix(14))
        guard !raw.isEmpty else { return "" }
        var result = ""
        for (index, character) in raw.enumerated() {
            switch index {
            case 2, 5: result.append(".")
            case 8: result.append("/")
            case 12: result.append("-")
            default: break
            }
            result.append(character)
        }
        return result
    }

    /// Aplica automaticamente a máscara de CPF ou CNPJ dependendo da quantidade de dígitos digitados.
    /// Com até 11 dígitos usa CPF; acima disso, CNPJ.
    static func formatCPFOrCNPJ(_ value: String) -> String {
        let digits = digitsOnly(value)
        return digits.count > 11 ? formatCNPJ(digits) : formatCPF(digits)
    }

    /// Aplica a máscara de CEP: `#####-###` (máximo 8 dígitos).
    static func formatCEP(_ value: String) -> String {
        let raw = String(digitsOnly(value).prefix(8))
        guard !raw.isEmpty else { return "" }
        var result = ""
        for (index, character) in raw.enumerated() {
            if index == 5 { result.append("-") }
            result.append(character)
        }
        return result
    }
}

// MARK: - Extensão de conveniência

extension Decimal {
    /// Converte o valor diretamente para texto no formato real brasileiro (ex.: `R$ 1.234,56`).
    var asCurrency: String { Formatters.currencyText(from: self) }
}
