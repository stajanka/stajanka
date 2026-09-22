import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
  case belarusian = "be"
  case russian = "ru"
  case english = "en"
  static func resolved(_ stored: String?) -> AppLanguage {
    stored.flatMap(AppLanguage.init(rawValue:)) ?? .belarusian
  }
  var id: String { rawValue }
  var name: String {
    switch self {
    case .belarusian: return "Беларуская"
    case .russian: return "Русский"
    case .english: return "English"
    }
  }
  var locale: Locale { Locale(identifier: rawValue) }
}

@MainActor
final class LanguageStore: ObservableObject {
  @Published var language: AppLanguage {
    didSet { AppPersistence.defaults.set(language.rawValue, forKey: "appLanguage") }
  }
  init() { language = L10n.language }
}

enum L10n {
  static var language: AppLanguage {
    AppLanguage(rawValue: AppPersistence.defaults.string(forKey: "appLanguage") ?? "")
      ?? .belarusian
  }
  static var locale: Locale { language.locale }
  static func bundle(for language: AppLanguage) -> Bundle {
    guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else { return .main }
    return bundle
  }
  static func text(_ key: String, language: AppLanguage, arguments: [CVarArg] = []) -> String {
    let template = bundle(for: language).localizedString(
      forKey: key, value: key, table: "Localizable")
    return arguments.isEmpty
      ? template : String(format: template, locale: language.locale, arguments: arguments)
  }
  static func hoursWord(_ hours: Int, language: AppLanguage = L10n.language) -> String {
    let key: String
    if language == .english {
      key = hours == 1 ? "час" : "часов"
    } else if hours % 10 == 1 && hours % 100 != 11 {
      key = "час"
    } else if (2...4).contains(hours % 10) && !(12...14).contains(hours % 100) {
      key = "часа"
    } else {
      key = "часов"
    }
    return text(key, language: language)
  }
  static func money(_ amount: String, language: AppLanguage = L10n.language) -> String {
    guard let decimal = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
      return amount + " BYN"
    }
    let formatter = NumberFormatter()
    formatter.locale = language.locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return (formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? amount) + " BYN"
  }
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
  L10n.text(key, language: L10n.language, arguments: arguments)
}

enum VehicleCountry {
  static let codes = Locale.Region.isoRegions.map(\.identifier).filter {
    $0.count == 2 && $0.unicodeScalars.allSatisfy { (65...90).contains(Int($0.value)) }
  }
  static func name(_ code: String, language: AppLanguage = L10n.language) -> String {
    language.locale.localizedString(forRegionCode: code) ?? code
  }
  static func flag(_ code: String) -> String {
    let scalars = code.uppercased().unicodeScalars
    guard scalars.count == 2, scalars.allSatisfy({ (65...90).contains(Int($0.value)) }) else {
      return "🌐"
    }
    return String(String.UnicodeScalarView(scalars.compactMap { UnicodeScalar(127397 + $0.value) }))
  }
  static var sortedCodes: [String] {
    let first = ["BY", "RU", "UA", "PL", "LT", "LV", "EE", "DE"]
    return first
      + codes.filter { !first.contains($0) }.sorted {
        name($0).compare(name($1), options: .caseInsensitive, locale: L10n.locale)
          == .orderedAscending
      }
  }
}
