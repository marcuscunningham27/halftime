import Foundation

/// Free, keyless weather (open-meteo.com): the forecast, or recent history, for the hour nearest a game.
public enum OpenMeteo {
    public static func weather(latitude: Double, longitude: Double, at date: Date,
                               session: URLSession = .shared) async throws -> Weather? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(latitude)), .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "temperature_2m,weather_code,wind_speed_10m,precipitation_probability"),
            .init(name: "start_date", value: day), .init(name: "end_date", value: day), .init(name: "timezone", value: "GMT"),
        ]
        let (data, _) = try await session.data(from: url.url!)
        return try parse(data, at: date)
    }

    static func parse(_ data: Data, at date: Date) throws -> Weather? {
        struct Response: Decodable {
            struct Hourly: Decodable {
                let time: [String]
                let temperature_2m: [Double?]
                let weather_code: [Int?]
                let wind_speed_10m: [Double?]?
                let precipitation_probability: [Int?]?
            }
            let hourly: Hourly
        }
        let hourly = try JSONDecoder().decode(Response.self, from: data).hourly
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        // The hour closest to the given time.
        guard let index = hourly.time.indices.min(by: {
            abs((formatter.date(from: hourly.time[$0]) ?? .distantPast).timeIntervalSince(date))
                < abs((formatter.date(from: hourly.time[$1]) ?? .distantPast).timeIntervalSince(date))
        }), let temperature = hourly.temperature_2m[index], let code = hourly.weather_code[index]
        else { return nil }
        return Weather(temperature: .init(value: temperature, unit: .celsius), code: code,
                       windSpeed: hourly.wind_speed_10m?[index].map { .init(value: $0, unit: .kilometersPerHour) },
                       precipitationChance: hourly.precipitation_probability?[index] ?? nil)
    }
}
