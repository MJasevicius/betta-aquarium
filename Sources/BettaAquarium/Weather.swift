// The sky over the tank, if you want it: sunrise and sunset where you are (worked out here, from the
// date and the place), and the weather there, asked of Open-Meteo (open-meteo.com: free, no account;
// it is sent only the place's latitude and longitude, and only when the weather is turned on).

import CoreLocation
import Foundation

enum Sun {
    /// sunrise and sunset in local hours on that day (NOAA's approximation), or nil where the sun
    /// doesn't rise or doesn't set that day
    static func times(on date: Date, latitude: Double, longitude: Double) -> (rise: Double, set: Double)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let n = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let g = 2 * Double.pi / 365 * (n - 1)
        let eq = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let lat = latitude * .pi / 180
        let c = cos(90.833 * .pi / 180) / (cos(lat) * cos(decl)) - tan(lat) * tan(decl)
        guard c >= -1, c <= 1 else { return nil }
        let ha = acos(c) * 180 / .pi
        let zone = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600
        func local(_ minutes: Double) -> Double { let h = (minutes / 60 + zone).truncatingRemainder(dividingBy: 24); return h < 0 ? h + 24 : h }
        return (local(720 - 4 * (longitude + ha) - eq), local(720 - 4 * (longitude - ha) - eq))
    }
}

/// what the weather is doing, as far as the tank cares
struct Sky: Equatable {
    var cloud = 0.0                 // 0 clear ... 1 overcast
    var rain = 0.0                  // 0 dry ... 1 pouring
    var snow = false, thunder = false, fog = false
    var wind = 0.0                  // 0 still ... 1 a gale
    var summary = "Clear"
    var at = Date.distantPast

    static func from(code: Int, cloud: Double, rain: Double, wind: Double) -> Sky {
        var s = Sky()
        s.cloud = min(max(cloud / 100, 0), 1)
        s.rain = min(max(rain / 4, 0), 1)                       // mm an hour: 4 is heavy
        s.wind = min(max(wind / 60, 0), 1)                      // km/h
        s.fog = code == 45 || code == 48
        s.snow = (71...77).contains(code) || code == 85 || code == 86
        s.thunder = code >= 95
        if s.rain == 0 && ((51...67).contains(code) || (80...82).contains(code)) { s.rain = 0.25 }
        if s.fog { s.cloud = max(s.cloud, 0.8) }
        s.summary = switch code {
        case 0: "Clear"
        case 1, 2: "Partly Cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow Showers"
        case 95...99: "Thunderstorm"
        default: "Cloudy"
        }
        s.at = Date()
        return s
    }
}

final class Weather: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Weather()
    @Published private(set) var sky: Sky?
    @Published private(set) var problem: String?
    private var asking = false

    /// ask again, if it has been long enough (or `now`)
    func refresh(_ s: Settings = .shared, now: Bool = false) {
        guard s.weather, s.hasPlace, !asking else { return }
        if !now, let sky, Date().timeIntervalSince(sky.at) < s.weatherEvery * 60 { return }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", s.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", s.longitude)),
            URLQueryItem(name: "current", value: "cloud_cover,precipitation,weather_code,wind_speed_10m"),
        ]
        asking = true
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.asking = false
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let cur = json["current"] as? [String: Any] else {
                    self.problem = error?.localizedDescription ?? "No answer from the weather service"
                    return
                }
                func n(_ k: String) -> Double { (cur[k] as? NSNumber)?.doubleValue ?? 0 }
                self.problem = nil
                self.sky = Sky.from(code: Int(n("weather_code")), cloud: n("cloud_cover"), rain: n("precipitation"),
                                    wind: n("wind_speed_10m"))
            }
        }.resume()
    }

    func forget() { sky = nil }

    // MARK: finding a place

    struct Place: Identifiable, Hashable { var id: String { "\(name)\(latitude)\(longitude)" }; var name: String; var latitude, longitude: Double }

    /// places called this (Open-Meteo's geocoding: sent only what you typed)
    func search(_ text: String, _ done: @escaping ([Place]) -> Void) {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: text), URLQueryItem(name: "count", value: "8"),
                        URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        URLSession.shared.dataTask(with: c.url!) { data, _, _ in
            var found = [Place]()
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                for r in results {
                    guard let lat = (r["latitude"] as? NSNumber)?.doubleValue, let lon = (r["longitude"] as? NSNumber)?.doubleValue else { continue }
                    let name = [r["name"], r["admin1"], r["country"]].compactMap { $0 as? String }.reduce(into: [String]()) {
                        if !$0.contains($1) { $0.append($1) }
                    }.joined(separator: ", ")
                    found.append(Place(name: name, latitude: lat, longitude: lon))
                }
            }
            DispatchQueue.main.async { done(found) }
        }.resume()
    }

    // MARK: where this Mac is (Location Services: asked once, with your permission)

    private var manager: CLLocationManager?
    private var located: ((Place?, String?) -> Void)?

    func locate(_ done: @escaping (Place?, String?) -> Void) {
        located = done
        let m = CLLocationManager()
        m.delegate = self
        manager = m
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() } else { m.requestLocation() }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finish(nil, "Location Services are off for Betta Aquarium (System Settings ▸ Privacy & Security)")
        default: m.requestLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(l) { [weak self] marks, _ in
            let name = marks?.first.map { [$0.locality, $0.country].compactMap { $0 }.joined(separator: ", ") } ?? ""
            self?.finish(Place(name: name.isEmpty ? String(format: "%.2f, %.2f", l.coordinate.latitude, l.coordinate.longitude) : name,
                               latitude: l.coordinate.latitude, longitude: l.coordinate.longitude), nil)
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { finish(nil, error.localizedDescription) }

    private func finish(_ p: Place?, _ problem: String?) {
        DispatchQueue.main.async {
            self.located?(p, problem)
            self.located = nil
            self.manager = nil
        }
    }
}
