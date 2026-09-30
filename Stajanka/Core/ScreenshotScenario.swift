#if DEBUG
  import Foundation
  import UIKit

  /// Used only by the isolated simulator screenshot tests. Excluded from Release.
  @MainActor
  enum ScreenshotScenario {
    static var enabled: Bool {
      ProcessInfo.processInfo.arguments.contains("--app-store-screenshots")
    }
    static func seed(_ model: AppModel) {
      UIView.setAnimationsEnabled(false)
      let args = ProcessInfo.processInfo.arguments
      let language =
        args.firstIndex(of: "--screenshot-language").flatMap {
          $0 + 1 < args.count ? args[$0 + 1] : nil
        } ?? "be"
      AppPersistence.defaults.set(language, forKey: "appLanguage")
      AppPersistence.defaults.set(true, forKey: "onboarded")
      let labels: [String: [String]] = [
        "be": ["Гарадскі аўтамабіль", "Для падарожжаў"],
        "ru": ["Городской автомобиль", "Для путешествий"], "en": ["City car", "Road trips"],
      ]
      let names = labels[language] ?? labels["en"]!
      model.vehicles = [
        Vehicle(plate: "1234AA7", nickname: names[0]),
        Vehicle(plate: "WA12345", nickname: names[1], countryCode: "PL"),
      ]
      model.selectedVehicleID = model.vehicles[0].id
      let now = Date()
      let formatter = ISO8601DateFormatter()
      let end = now.addingTimeInterval(3600)
      let quote = ParkingQuote(
        plate: "1234AA7", zoneID: "710", zoneTitle: L("Парковочная зона %@", "710"),
        start: formatter.string(from: now.addingTimeInterval(-1800)),
        validTill: formatter.string(from: end), hours: 2, isExtension: false, tariff: 1,
        amount: "4.0", eripURL: nil, createdAt: now, countryCode: "BY")
      let pastQuote = ParkingQuote(
        plate: "1234AA7", zoneID: "720", zoneTitle: L("Парковочная зона %@", "720"),
        start: formatter.string(from: now.addingTimeInterval(-10800)),
        validTill: formatter.string(from: now.addingTimeInterval(-7200)),
        hours: 1, isExtension: false, tariff: 1, amount: "2.0", eripURL: nil,
        createdAt: now.addingTimeInterval(-10800), countryCode: "BY")
      model.sessions = [
        ParkingSession(
          quote: quote, state: .confirmed, lastChecked: now, confirmationSource: .currentCoverage,
          confirmedValidTill: quote.validTill),
        ParkingSession(
          quote: pastQuote, state: .confirmed, lastChecked: pastQuote.createdAt,
          confirmationSource: .currentCoverage, confirmedValidTill: pastQuote.validTill)
      ]
    }
    static func quote(vehicle: Vehicle, zone: ParkingZone, hours: Int) -> ParkingQuote {
      let now = Date()
      let formatter = ISO8601DateFormatter()
      return ParkingQuote(
        plate: vehicle.plate, zoneID: zone.paymentID, zoneTitle: zone.title,
        start: formatter.string(from: now),
        validTill: formatter.string(from: now.addingTimeInterval(Double(hours) * 3600)),
        hours: hours, isExtension: false, tariff: vehicle.isBus ? 2 : 1, amount: String(hours * 2),
        eripURL: nil, createdAt: now, countryCode: vehicle.countryCode)
    }
  }
#endif
