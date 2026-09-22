import MapKit
import SwiftUI

struct ParkingMapView: View {
  @EnvironmentObject private var model: AppModel
  @StateObject private var location = LocationService()
  @State private var camera: MapCameraPosition = .region(
    MKCoordinateRegion(
      center: .init(latitude: 53.905, longitude: 27.557),
      span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018)))
  @State private var visibleRegion = MKCoordinateRegion(
    center: .init(latitude: 53.905, longitude: 27.557),
    span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018))
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var search = ""
  @State private var searchOpen = false
  @State private var payment = false
  @State private var addCar = false
  @State private var locationAlert = false
  @State private var awaitingLocation = false
  let showHelp: () -> Void
  private var results: [ParkingZone] {
    let matching = model.zones.filter {
      search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        || $0.number.contains(search)
    }
    if let p = location.location {
      return matching.sorted { distance($0, from: p) < distance($1, from: p) }
    }
    return matching
  }
  var body: some View {
    ZStack(alignment: .top) {
      MapReader { proxy in
        Map(position: $camera) {
          UserAnnotation()
          ForEach(model.zones) { zone in
            ForEach(Array(zone.polygons.enumerated()), id: \.offset) { _, points in
              MapPolygon(coordinates: points).foregroundStyle(
                zone.id == model.selectedZone?.id
                  ? Palette.green.opacity(0.55) : Palette.green.opacity(0.22)
              ).stroke(
                Palette.green.opacity(0.8), lineWidth: zone.id == model.selectedZone?.id ? 3 : 1.5)
            }
            Annotation(zone.title, coordinate: zone.coordinate) {
              Button {
                select(zone)
              } label: {
                HStack(spacing: 3) {
                  Text("P").font(.system(size: 15, weight: .heavy, design: .rounded))
                  if model.selectedZone?.id == zone.id {
                    Text(zone.number).font(.system(size: 12, weight: .bold))
                  }
                }.padding(.horizontal, 9).padding(.vertical, 7).foregroundStyle(
                  model.selectedZone?.id == zone.id ? .white : Palette.ink
                ).background(
                  model.selectedZone?.id == zone.id ? Palette.ink : .white,
                  in: RoundedRectangle(cornerRadius: 11)
                ).overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.green.opacity(0.25)))
                  .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
              }.buttonStyle(.plain).accessibilityLabel(
                L("Парковка %@", String(describing: zone.title)))
            }.annotationTitles(.hidden)
          }
        }.mapStyle(
          .standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        )
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
        .onTapGesture { point in
          guard let c = proxy.convert(point, from: .local) else { return }
          let p = CLLocation(latitude: c.latitude, longitude: c.longitude)
          if let nearest = model.zones.min(by: { distance($0, from: p) < distance($1, from: p) }),
            distance(nearest, from: p) < 150
          {
            select(nearest)
          }
        }
      }.ignoresSafeArea(edges: .top)
      VStack(spacing: 12) {
        HStack {
          HStack(spacing: 8) {
            Image("BrandMark").resizable().frame(width: 28, height: 28).clipShape(
              RoundedRectangle(cornerRadius: 8))
            Text(L("стаянка")).font(.system(size: 25, weight: .bold, design: .rounded)).tracking(
              -0.8)
          }.padding(.horizontal, 17).padding(.vertical, 12).background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
          Spacer()
          RoundButton(icon: "questionmark", label: L("Как это работает"), action: showHelp)
        }
        Button {
          searchOpen = true
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
            Text(L("Улица или номер зоны")).foregroundStyle(Palette.muted)
            Spacer()
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.ink)
          }.font(.system(size: 15)).padding(17).background(
            .white, in: RoundedRectangle(cornerRadius: 20)
          ).shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        }.buttonStyle(.plain).accessibilityIdentifier("search-zones")
        if let message = model.zoneMessage {
          Button {
            Task { await model.refreshZones() }
          } label: {
            Label(message, systemImage: "arrow.clockwise").font(.caption).padding(10).background(
              Palette.paper, in: RoundedRectangle(cornerRadius: 12))
          }
        }
        Spacer()
        HStack {
          Label(L("Минск"), systemImage: "location.circle").font(
            .system(size: 12, weight: .semibold)
          )
          .padding(.horizontal, 12).padding(.vertical, 9).background(
            .white.opacity(0.95), in: Capsule())
          Spacer()
          VStack(spacing: 12) {
            VStack(spacing: 0) {
              zoomButton(closer: true)
              Rectangle().fill(Palette.line).frame(width: 26, height: 1).accessibilityHidden(true)
              zoomButton(closer: false)
            }.background(.white, in: RoundedRectangle(cornerRadius: 18))
              .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
              .accessibilityElement(children: .contain).accessibilityLabel(L("Масштаб карты"))
            RoundButton(icon: "location.fill", label: L("Моё местоположение")) {
              awaitingLocation = true
              location.request()
              if let p = location.location {
                move(to: p.coordinate)
                awaitingLocation = false
              }
              if location.denied { locationAlert = true }
            }
          }
        }
        if let zone = model.selectedZone { zoneCard(zone) } else { welcomeCard }
      }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 16)
    }
    .foregroundStyle(Palette.ink)
    .sheet(isPresented: $searchOpen) { searchSheet }
    .sheet(isPresented: $addCar) { VehicleEditor() }
    .sheet(isPresented: $payment) {
      if let zone = model.selectedZone, let v = model.vehicle {
        PaymentView(zone: zone, vehicle: v)
      }
    }
    .alert(L("Геолокация выключена"), isPresented: $locationAlert) {
      Button(L("Настройки")) {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
      }
      Button(L("Выбрать вручную"), role: .cancel) {}
    } message: {
      Text(L("Разрешите доступ к геолокации в настройках или найдите нужную улицу."))
    }
    .onChange(of: location.location) { _, p in
      if awaitingLocation, let p {
        move(to: p.coordinate)
        awaitingLocation = false
      }
    }
  }
  private var welcomeCard: some View {
    Button {
      searchOpen = true
    } label: {
      HStack(spacing: 13) {
        Text("P").font(.system(size: 23, weight: .heavy, design: .rounded))
          .frame(width: 44, height: 44).background(
            Palette.lime, in: RoundedRectangle(cornerRadius: 14))
        VStack(alignment: .leading, spacing: 4) {
          Text(L("Где припаркуемся?")).font(.system(size: 18, weight: .bold, design: .rounded))
          Text(L("%@ участков", String(model.zones.count))).font(.caption).foregroundStyle(
            Palette.muted)
        }
        Spacer(minLength: 0)
        Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold))
          .frame(width: 44, height: 44).foregroundStyle(.white).background(
            Palette.ink, in: Circle())
      }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: Palette.ink.opacity(0.10), radius: 18, y: 6)
    }.buttonStyle(.plain).accessibilityLabel(L("Выбрать парковку"))
      .accessibilityValue(L("%@ участков", String(model.zones.count)))
      .accessibilityIdentifier("map-welcome")
  }
  private func zoomButton(closer: Bool) -> some View {
    Button {
      zoom(closer: closer)
    } label: {
      Image(systemName: closer ? "plus" : "minus").font(.system(size: 22, weight: .semibold))
        .frame(width: 50, height: 50).contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel(closer ? L("Приблизить карту") : L("Отдалить карту"))
      .accessibilityHint(closer ? L("Показывает парковки крупнее") : L("Показывает больше районов"))
      .accessibilityIdentifier(closer ? "map-zoom-in" : "map-zoom-out")
  }
  private func zoom(closer: Bool) {
    let factor = closer ? 0.5 : 2.0
    let next = MKCoordinateRegion(
      center: visibleRegion.center,
      span: MKCoordinateSpan(
        latitudeDelta: min(120, max(0.0005, visibleRegion.span.latitudeDelta * factor)),
        longitudeDelta: min(180, max(0.0005, visibleRegion.span.longitudeDelta * factor))))
    visibleRegion = next
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { camera = .region(next) }
  }
  private func zoneCard(_ zone: ParkingZone) -> some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack {
        Text(L("ЗОНА %@", String(describing: zone.number))).font(.system(size: 11, weight: .bold))
          .tracking(1.5).padding(
            .horizontal, 10
          ).padding(.vertical, 7).background(Palette.lime, in: Capsule())
        Spacer()
        Button {
          model.selectedZone = nil
        } label: {
          Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(
            width: 30, height: 30
          ).background(Palette.paper, in: Circle())
        }.accessibilityLabel(L("Снять выбор парковки"))
      }
      Text(zone.title).font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 16) {
        Label(zone.displayCost, systemImage: "creditcard")
        Label(zone.displayHours, systemImage: "clock")
      }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
      if let launch = zone.launch_date {
        Text(L("Платная с %@", String(describing: launch))).font(.caption).foregroundStyle(
          Palette.orange)
      }
      if let car = model.vehicle {
        HStack {
          Image(systemName: "car.side")
          Text(car.plate).font(.system(size: 14, weight: .bold, design: .monospaced))
          Spacer()
          Text(L("Мой автомобиль")).font(.caption).foregroundStyle(Palette.muted)
        }
      }
      PrimaryButton(
        title: model.vehicle == nil ? L("Добавить автомобиль") : L("Выбрать время"),
        icon: model.vehicle == nil ? "plus" : "arrow.right"
      ) { if model.vehicle == nil { addCar = true } else { payment = true } }
      .accessibilityIdentifier("zone-continue")
    }.padding(21).background(.white, in: RoundedRectangle(cornerRadius: 28)).shadow(
      color: Palette.ink.opacity(0.1), radius: 24, y: 8)
  }
  private var searchSheet: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(results) { zone in
            Button {
              select(zone)
              searchOpen = false
            } label: {
              HStack(alignment: .top, spacing: 14) {
                Text(zone.number).font(.system(size: 13, weight: .bold, design: .rounded)).padding(
                  12
                ).background(Palette.lime, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 6) {
                  Text(zone.title).font(.system(size: 16, weight: .semibold))
                  Text("\(zone.displayCost) · \(zone.displayHours)").font(.system(size: 12))
                    .foregroundStyle(
                      Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).padding(.top, 12)
              }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
          }
          if results.isEmpty { ContentUnavailableView.search(text: search) }
        }.padding(18)
      }.background(Palette.paper).navigationTitle(L("Найти парковку"))
        .navigationBarTitleDisplayMode(
          .inline
        ).searchable(text: $search, prompt: L("Улица или номер зоны")).toolbar {
          ToolbarItem(placement: .topBarTrailing) { Button(L("Готово")) { searchOpen = false } }
        }
    }
  }
  private func select(_ zone: ParkingZone) {
    #if DEBUG
      if model.isScreenshotSession {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          model.selectedZone = zone
          camera = .region(
            MKCoordinateRegion(
              center: .init(
                latitude: zone.coordinate.latitude - 0.0016,
                longitude: zone.coordinate.longitude),
              span: .init(latitudeDelta: 0.009, longitudeDelta: 0.009)))
        }
        return
      }
    #endif
    withAnimation(.easeInOut(duration: 0.3)) {
      model.selectedZone = zone
      camera = .region(
        MKCoordinateRegion(
          center: .init(
            latitude: zone.coordinate.latitude - 0.0016, longitude: zone.coordinate.longitude),
          span: .init(latitudeDelta: 0.009, longitudeDelta: 0.009)))
    }
  }
  private func move(to coordinate: CLLocationCoordinate2D) {
    withAnimation {
      camera = .region(
        MKCoordinateRegion(
          center: coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
    }
  }
  private func distance(_ z: ParkingZone, from location: CLLocation) -> Double {
    location.distance(
      from: CLLocation(latitude: z.coordinate.latitude, longitude: z.coordinate.longitude))
  }
}
