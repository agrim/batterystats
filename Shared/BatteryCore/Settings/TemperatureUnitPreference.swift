import Foundation

enum ResolvedTemperatureUnit {
    case celsius
    case fahrenheit
}

enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
    case system
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .celsius:
            return "Celsius"
        case .fahrenheit:
            return "Fahrenheit"
        }
    }

    var resolvedUnit: ResolvedTemperatureUnit {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.measurementSystem == .us ? .fahrenheit : .celsius
        case .celsius:
            return .celsius
        case .fahrenheit:
            return .fahrenheit
        }
    }
}
