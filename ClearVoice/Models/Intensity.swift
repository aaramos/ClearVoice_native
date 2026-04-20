struct Intensity: Equatable {
    let value: Double

    enum Band: String, CaseIterable, Equatable {
        case minimal
        case balanced
        case strong
        case maximum
    }

    static let minimal = Intensity(value: 0.15)
    static let balanced = Intensity(value: 0.5)
    static let strong = Intensity(value: 0.75)
    static let maximum = Intensity(value: 1.0)

    init(value: Double) {
        self.value = value
    }

    init(band: Band) {
        switch band {
        case .minimal:
            self = .minimal
        case .balanced:
            self = .balanced
        case .strong:
            self = .strong
        case .maximum:
            self = .maximum
        }
    }

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
