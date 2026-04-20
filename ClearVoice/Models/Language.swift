import Foundation

struct Language: Identifiable, Equatable {
    let id: String
    let displayName: String

    static let autoDetect = Language(id: "auto", displayName: "Auto Detect")
    static let english = Language(id: "en", displayName: "English")
    static let hindi = Language(id: "hi", displayName: "Hindi")
    static let bengali = Language(id: "bn", displayName: "Bengali")
    static let telugu = Language(id: "te", displayName: "Telugu")
    static let marathi = Language(id: "mr", displayName: "Marathi")
    static let tamil = Language(id: "ta", displayName: "Tamil")
    static let urdu = Language(id: "ur", displayName: "Urdu")
    static let gujarati = Language(id: "gu", displayName: "Gujarati")
    static let kannada = Language(id: "kn", displayName: "Kannada")
    static let malayalam = Language(id: "ml", displayName: "Malayalam")
    static let punjabi = Language(id: "pa", displayName: "Punjabi")
    static let odia = Language(id: "or", displayName: "Odia")
    static let assamese = Language(id: "as", displayName: "Assamese")

    static let prioritized: [Language] = [
        .english,
        .autoDetect,
        .hindi,
        .bengali,
        .telugu,
        .marathi,
        .tamil,
        .urdu,
        .gujarati,
        .kannada,
        .malayalam,
        .punjabi,
        .odia,
        .assamese,
    ]

    static func displayName(for languageCode: String) -> String {
        if let match = prioritized.first(where: { $0.id == languageCode }) {
            return match.displayName
        }

        if let localized = Locale(identifier: "en").localizedString(forLanguageCode: languageCode) {
            return localized.capitalized
        }

        return languageCode
    }
}
