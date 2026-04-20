struct Intensity: Equatable {
    let value: Double

    enum Band: String, Equatable {
        case minimal
        case balanced
        case strong
        case maximum
    }

    static let balanced = Intensity(value: 0.5)

    var band: Band {
        switch value {
        case ..<0.26:
            .minimal
        case ..<0.61:
            .balanced
        case ..<0.86:
            .strong
        default:
            .maximum
        }
    }
}
