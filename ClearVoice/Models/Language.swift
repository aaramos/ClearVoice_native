struct Language: Identifiable, Equatable {
    let id: String
    let displayName: String

    static let autoDetect = Language(id: "auto", displayName: "Auto Detect")
    static let english = Language(id: "en", displayName: "English")
    static let hindi = Language(id: "hi", displayName: "Hindi")

    static let prioritized: [Language] = [
        .english,
        .autoDetect,
        .hindi,
    ]
}
