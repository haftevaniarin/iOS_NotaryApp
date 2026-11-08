import Foundation

nonisolated enum SigningTypeOptions {
    static let values = ["Loan Signing", "Refinance", "HELOC", "Seller Package", "General Notary", "Other"]

    static func matching(_ source: String) -> String? {
        let text = normalized(source)
        guard !text.isEmpty else { return nil }
        if let exact = values.first(where: { normalized($0) == text }) { return exact }

        let buyerAliases = ["buyer", "buyer only", "buyer package", "buyer signing", "purchase", "purchase signing", "purchase closing"]
        let aliases = [
            "Loan Signing": ["loan signing", "loan closing"] + buyerAliases,
            "Refinance": ["refinance", "refinancing", "refi"],
            "HELOC": ["heloc", "h e l o c", "home equity line of credit"],
            "Seller Package": ["seller", "seller only", "seller package", "seller signing"],
            "General Notary": ["general notary", "general notarization", "general notarial work", "gnw"]
        ]
        func contains(_ alias: String) -> Bool { (" " + text + " ").contains(" " + alias + " ") }
        var matches = Set(aliases.compactMap { type, terms in terms.contains(where: contains) ? type : nil })
        // A specific loan type wins over the generic phrase "loan signing".
        // Buyer/seller or refinance/HELOC conflicts still require a user's choice.
        if matches.count > 1 && !buyerAliases.contains(where: contains) { matches.remove("Loan Signing") }
        return matches.count == 1 ? matches.first : nil
    }

    private static func normalized(_ source: String) -> String {
        source.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
