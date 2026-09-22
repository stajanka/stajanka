import SwiftUI

@main
struct StajankaApp: App {
  @StateObject private var model = AppModel()
  @StateObject private var languages = LanguageStore()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(model).environmentObject(languages).environment(
        \.locale, languages.language.locale
      ).preferredColorScheme(.light)
    }
  }
}

struct RootView: View {
  @EnvironmentObject private var languages: LanguageStore
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("onboarded", store: AppPersistence.defaults) private var onboarded = false
  @State private var tab = 0
  @State private var help = false
  var body: some View {
    VStack(spacing: 0) {
      Group {
        if tab == 0 {
          ParkingMapView(showHelp: { help = true })
        } else if tab == 1 {
          SessionsView()
        } else {
          GarageView()
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack(spacing: 0) {
        tabButton(L("Карта"), icon: "map", index: 0)
        tabButton(L("Парковка"), icon: "timer", index: 1)
        tabButton(L("Гараж"), icon: "car.side", index: 2)
      }.padding(.top, 12).padding(.bottom, 4).background(.white)
    }
    .id(languages.language)
    .background(Palette.paper).tint(Palette.ink)
    .sheet(isPresented: $help) { GuideView() }
    .fullScreenCover(
      isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })
    ) { OnboardingView { onboarded = true }.id(languages.language) }
    .task { await model.load() }
    .task(id: model.vehicle?.id) { await model.restoreCurrentParking() }
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      await model.restoreCurrentParking()
      while !Task.isCancelled {
        await model.checkPayments()
        do { try await Task.sleep(for: .seconds(20)) } catch { return }
      }
    }
  }
  private func tabButton(_ title: String, icon: String, index: Int) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.18)) { tab = index }
    } label: {
      VStack(spacing: 5) {
        Image(systemName: icon).font(.system(size: 20, weight: tab == index ? .bold : .regular))
        Text(title).font(.system(size: 11, weight: .semibold))
      }.foregroundStyle(tab == index ? Palette.ink : Palette.muted).frame(maxWidth: .infinity)
        .padding(.vertical, 5).background(alignment: .top) {
          if tab == index { Capsule().fill(Palette.lime).frame(width: 42, height: 3).offset(y: -7) }
        }
    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(index)")
  }
}
