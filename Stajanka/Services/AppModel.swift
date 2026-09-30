import CoreLocation
import SwiftUI
import UserNotifications

enum AppPersistence {
  #if DEBUG
    static let isUITest = ProcessInfo.processInfo.arguments.contains("--ui-testing")
  #else
    static let isUITest = false
  #endif
  static let defaults: UserDefaults = {
    if isUITest {
      let suite = "by.stajanka.ui-tests"
      let defaults = UserDefaults(suiteName: suite)!
      if ProcessInfo.processInfo.arguments.contains("--reset-test-state") {
        defaults.removePersistentDomain(forName: suite)
      }
      return defaults
    }
    return .standard
  }()
  static let databaseURL: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent(
      isUITest ? "StajankaUITests" : "Stajanka", isDirectory: true)
    if isUITest && ProcessInfo.processInfo.arguments.contains("--reset-test-state") {
      try? FileManager.default.removeItem(at: directory)
    }
    return directory.appendingPathComponent("parking.sqlite")
  }()
}

@MainActor
final class AppModel: ObservableObject {
  private var store: LocalParkingStore?
  private var persistenceReady = false
  private var durableSnapshot = ParkingSnapshot()
  private var dataRevision = UUID()
  @Published var zones: [ParkingZone] = []
  @Published var vehicles: [Vehicle] = [] { didSet { persistMutation() } }
  @Published var selectedVehicleID: UUID? { didSet { persistMutation() } }
  @Published var sessions: [ParkingSession] = [] { didSet { persistMutation() } }
  @Published var storageMessage: String?
  @Published var zoneMessage: String?
  @Published var refreshing = false
  @Published var checking = false
  @Published var checkMessage: String?
  @Published var selectedZone: ParkingZone?
  private var didLoad = false
  private var restoringVehicles: [UUID: UUID] = [:]
  let api: ParkoukaAPI
  var vehicle: Vehicle? { vehicles.first { $0.id == selectedVehicleID } ?? vehicles.first }
  var pending: [ParkingSession] { sessions.filter { $0.state == .awaiting } }
  var active: [ParkingSession] {
    sessions.filter { $0.state == .confirmed && ($0.endDate ?? .distantPast) > Date() }
  }
  init(
    defaults: UserDefaults = AppPersistence.defaults, storageURL: URL? = nil,
    api: ParkoukaAPI = .shared
  ) {
    self.api = api
    do {
      let store = try LocalParkingStore(
        url: storageURL ?? AppPersistence.databaseURL, legacyDefaults: defaults)
      let snapshot = try store.load()
      self.store = store
      apply(snapshot)
      durableSnapshot = snapshot
    } catch {
      storageMessage = L(
        "Не удалось открыть локальную историю. Исходные данные сохранены для восстановления.")
    }
    persistenceReady = true
    if let url = Bundle.main.url(forResource: "zones", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    {
      zones = (try? ParkingZone.decode(data)) ?? []
    }
    #if DEBUG
      if ScreenshotScenario.enabled { ScreenshotScenario.seed(self) }
    #endif
  }
  var isScreenshotSession: Bool {
    #if DEBUG
      return ScreenshotScenario.enabled
    #else
      return false
    #endif
  }
  func parkingQuote(vehicle: Vehicle, zone: ParkingZone, hours: Int) async throws -> ParkingQuote {
    #if DEBUG
      if ScreenshotScenario.enabled {
        return ScreenshotScenario.quote(vehicle: vehicle, zone: zone, hours: hours)
      }
    #endif
    return try await api.quote(vehicle: vehicle, zone: zone, hours: hours)
  }
  func load() async {
    guard !didLoad else { return }
    didLoad = true
    await refreshZones()
  }
  func refreshZones() async {
    if isScreenshotSession { return }
    refreshing = true
    defer { refreshing = false }
    do {
      zones = try await api.zones()
      zoneMessage = nil
    } catch {
      zoneMessage = L("Карта из сохранённой копии. Для актуальных условий обновите данные.")
    }
  }
  func add(_ vehicle: Vehicle) async throws {
    var vehicle = vehicle
    vehicle.nickname = Vehicle.cleanNickname(vehicle.nickname)
    guard !vehicles.contains(where: { $0.plate == vehicle.plate }) else {
      throw ParkoukaError.message(L("Этот автомобиль уже добавлен."))
    }
    var next = snapshot
    next.vehicles.append(vehicle)
    next.selectedVehicleID = vehicle.id
    try commit(next)
  }
  @discardableResult
  func begin(_ quote: ParkingQuote) -> Bool {
    var next = snapshot
    if !next.sessions.contains(where: { $0.quote == quote }) {
      next.sessions.insert(ParkingSession(quote: quote, state: .awaiting), at: 0)
    }
    do {
      try commit(next)
      return true
    } catch { return false }
  }
  func removeVehicle(_ vehicle: Vehicle) {
    var next = snapshot
    next.vehicles.removeAll { $0.id == vehicle.id }
    if !next.vehicles.contains(where: { $0.id == next.selectedVehicleID }) {
      next.selectedVehicleID = next.vehicles.first?.id
    }
    try? commit(next)
  }
  func eraseLocalData() async {
    do { try commit(ParkingSnapshot()) } catch { return }
    dataRevision = UUID()
    restoringVehicles.removeAll()
    checkMessage = nil
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    await api.resetGuestSession()
  }
  /// Public coverage restores currently paid time, never historical account transactions.
  func restoreCurrentParking() async {
    guard !isScreenshotSession, store != nil, let vehicle, restoringVehicles[vehicle.id] == nil
    else { return }
    let revision = dataRevision
    let workID = UUID()
    restoringVehicles[vehicle.id] = workID
    defer {
      if restoringVehicles[vehicle.id] == workID {
        restoringVehicles.removeValue(forKey: vehicle.id)
      }
    }
    let paymentZones = Dictionary(grouping: zones, by: \.paymentID).compactMap { $0.value.first }
    for zone in paymentZones {
      guard !Task.isCancelled, revision == dataRevision, self.vehicle?.id == vehicle.id else {
        return
      }
      if pending.contains(where: {
        $0.quote.plate == vehicle.plate && $0.quote.zoneID == zone.paymentID
      }) {
        continue
      }
      do {
        let status = try await api.start(
          plate: vehicle.plate, zoneID: zone.paymentID, tariff: vehicle.isBus ? 2 : 1)
        guard !Task.isCancelled, revision == dataRevision, self.vehicle?.id == vehicle.id,
          let restored = ParkingSession.restored(
            vehicle: vehicle, zone: zone, response: status, now: Date()),
          let coverageEnd = restored.endDate
        else { continue }
        var next = snapshot
        let matching = next.sessions.indices.filter {
          next.sessions[$0].state == .confirmed && next.sessions[$0].quote.plate == vehicle.plate
            && next.sessions[$0].quote.zoneID == zone.paymentID
            && (next.sessions[$0].endDate ?? .distantPast) > Date()
        }
        if let latest = matching.max(by: {
          (next.sessions[$0].endDate ?? .distantPast) < (next.sessions[$1].endDate ?? .distantPast)
        }) {
          if coverageEnd <= (next.sessions[latest].endDate ?? .distantPast).addingTimeInterval(1) {
            next.sessions[latest].lastChecked = Date()
          } else if next.sessions[latest].quote.amount.isEmpty {
            next.sessions[latest].confirmedValidTill = restored.confirmedValidTill
            next.sessions[latest].lastChecked = Date()
          } else {
            // Preserve a known transaction's amount and paid interval; extra coverage has no known receipt.
            next.sessions.insert(restored, at: 0)
          }
        } else {
          next.sessions.insert(restored, at: 0)
        }
        try commit(next)
      } catch {
        guard revision == dataRevision, self.vehicle?.id == vehicle.id else { return }
        checkMessage = L(
          "Не все зоны удалось проверить. Потяните список парковок вниз, чтобы повторить.")
      }
    }
  }
  func checkPayments() async {
    guard !checking, !pending.isEmpty, store != nil else { return }
    checking = true
    defer { checking = false }
    let revision = dataRevision
    var errors: [String] = []
    var confirmed = 0
    for entry in pending {
      guard revision == dataRevision, !Task.isCancelled else { return }
      // Public coverage proves only current paid time, never an expired attempt.
      guard let end = entry.quote.endDate, end > Date() else { continue }
      do {
        let status = try await api.start(
          plate: entry.quote.plate, zoneID: entry.quote.zoneID, tariff: entry.quote.tariff)
        guard revision == dataRevision, !Task.isCancelled else { return }
        guard let i = sessions.firstIndex(where: { $0.id == entry.id }) else { continue }
        var next = snapshot
        next.sessions[i].lastChecked = Date()
        let paid = entry.quote.isCovered(by: status, checkedAt: Date())
        if paid {
          next.sessions[i].state = .confirmed
          next.sessions[i].confirmationSource = .currentCoverage
          // Keep the service-confirmed expiry, including any delay before payment completed.
          next.sessions[i].confirmedValidTill = status.t_start
        }
        try commit(next)
        if paid {
          confirmed += 1
          await scheduleReminder(for: next.sessions[i], revision: revision)
        }
      } catch {
        guard revision == dataRevision else { return }
        errors.append(error.localizedDescription)
      }
    }
    guard revision == dataRevision else { return }
    checkMessage =
      errors.first
      ?? (confirmed > 0
        ? L("Сервис подтвердил оплаченное время парковки.")
        : L(
          "Оплата пока не подтверждена. Проверьте результат в банке; повторно оплачивать сразу не нужно."
        ))
  }
  private func scheduleReminder(for entry: ParkingSession, revision: UUID) async {
    guard let end = entry.endDate, end.timeIntervalSinceNow > 600 else { return }
    let center = UNUserNotificationCenter.current()
    guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true,
      revision == dataRevision, end.timeIntervalSinceNow > 600
    else { return }
    let content = UNMutableNotificationContent()
    content.title = L("Ещё 10 минут парковки")
    content.body = L(
      "%@ · %@. При необходимости продлите время.", entry.quote.plate, entry.quote.zoneTitle)
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: end.timeIntervalSinceNow - 600, repeats: false)
    try? await center.add(
      UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: trigger))
    if revision != dataRevision {
      center.removePendingNotificationRequests(withIdentifiers: [entry.id.uuidString])
      center.removeDeliveredNotifications(withIdentifiers: [entry.id.uuidString])
    }
  }
  private var snapshot: ParkingSnapshot {
    ParkingSnapshot(vehicles: vehicles, sessions: sessions, selectedVehicleID: selectedVehicleID)
  }
  private func apply(_ snapshot: ParkingSnapshot) {
    let wasReady = persistenceReady
    persistenceReady = false
    vehicles = snapshot.vehicles
    sessions = snapshot.sessions
    selectedVehicleID = snapshot.selectedVehicleID
    persistenceReady = wasReady
  }
  private func commit(_ snapshot: ParkingSnapshot) throws {
    guard let store else {
      let message = L("Локальное хранилище недоступно. Перезапустите приложение.")
      storageMessage = message
      throw ParkoukaError.message(message)
    }
    do { try store.save(snapshot) } catch {
      let message = L(
        "Не удалось сохранить данные на устройстве. Освободите место и повторите попытку.")
      storageMessage = message
      throw ParkoukaError.message(message)
    }
    durableSnapshot = snapshot
    apply(snapshot)
    storageMessage = nil
  }
  private func persistMutation() {
    guard persistenceReady else { return }
    do { try commit(snapshot) } catch { apply(durableSnapshot) }
  }
}

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
  @Published var location: CLLocation?
  @Published var denied = false
  private let manager = CLLocationManager()
  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
  }
  func request() {
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      denied = true
    } else {
      manager.startUpdatingLocation()
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    if manager.authorizationStatus == .authorizedWhenInUse
      || manager.authorizationStatus == .authorizedAlways
    {
      manager.startUpdatingLocation()
    }
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    location = locations.last
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
