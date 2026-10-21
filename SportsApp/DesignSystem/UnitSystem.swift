import Foundation

/// Metric or imperial, chosen in Settings › General; starts from the Mac's region.
enum UnitSystem: String, CaseIterable, Identifiable {
    case metric, imperial

    static let storageKey = "unitSystem"
    static var regionDefault: UnitSystem { Locale.current.measurementSystem == .us ? .imperial : .metric }

    var id: Self { self }
    var title: String { self == .metric ? "Metric (°C, km/h)" : "Imperial (°F, mph)" }

    func temperature(_ value: Measurement<UnitTemperature>) -> String {
        value.converted(to: self == .metric ? .celsius : .fahrenheit)
            .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    func speed(_ value: Measurement<UnitSpeed>) -> String {
        value.converted(to: self == .metric ? .kilometersPerHour : .milesPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
