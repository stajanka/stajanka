import SwiftUI

struct LanguagePickerView: View {
  @EnvironmentObject private var languages: LanguageStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SheetHeader(title: L("Язык приложения"), dismiss: { dismiss() })
      ForEach(AppLanguage.allCases) { language in
        Button {
          languages.language = language
          dismiss()
        } label: {
          HStack(spacing: 14) {
            Text(language.rawValue.uppercased()).font(.system(.headline, design: .rounded))
              .frame(width: 48, height: 48).background(
                Palette.lime, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
              Text(language.name).font(.headline)
              if language == .belarusian {
                Text(L("По умолчанию")).font(.caption).foregroundStyle(Palette.muted)
              }
            }
            Spacer()
            Image(systemName: languages.language == language ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(Palette.green)
          }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("language-\(language.rawValue)")
      }
      Spacer(minLength: 0)
    }.padding(24).background(Palette.paper).foregroundStyle(Palette.ink)
      .presentationDetents([.medium, .large])
  }
}

struct CountryPickerView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var selection: String
  @State private var search = ""
  private var countries: [String] {
    VehicleCountry.sortedCodes.filter {
      search.isEmpty || $0.localizedCaseInsensitiveContains(search)
        || VehicleCountry.name($0).localizedCaseInsensitiveContains(search)
        || VehicleCountry.name($0, language: .english).localizedCaseInsensitiveContains(search)
    }
  }
  var body: some View {
    NavigationStack {
      List(countries, id: \.self) { code in
        Button {
          selection = code
          dismiss()
        } label: {
          HStack(spacing: 14) {
            Text(VehicleCountry.flag(code)).font(.title2)
            Text(VehicleCountry.name(code)).foregroundStyle(Palette.ink)
            Spacer()
            Text(code).font(.caption.monospaced()).foregroundStyle(Palette.muted)
            if selection == code { Image(systemName: "checkmark").foregroundStyle(Palette.green) }
          }.frame(minHeight: 40)
        }.accessibilityIdentifier("country-\(code)")
      }
      .searchable(text: $search, prompt: L("Найти страну"))
      .navigationTitle(L("Страна регистрации")).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Готово")) { dismiss() } } }
    }.tint(Palette.ink)
  }
}

struct VehiclePickerView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let selectedID: UUID
  let onSelect: (Vehicle) -> Void
  @State private var adding = false
  @State private var newlyAdded: Vehicle?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SheetHeader(title: L("Выберите автомобиль"), dismiss: { dismiss() })
        ForEach(model.vehicles) { car in
          Button {
            onSelect(car)
            dismiss()
          } label: {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 10) {
                PlateView(plate: car.plate, countryCode: car.countryCode)
                Text(car.label).font(.subheadline).foregroundStyle(Palette.muted)
              }
              Spacer()
              Image(systemName: selectedID == car.id ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(Palette.green)
            }.frame(maxWidth: .infinity, alignment: .leading).card()
          }.buttonStyle(.plain).accessibilityIdentifier("choose-vehicle-\(car.plate)")
        }
        PrimaryButton(title: L("Добавить новый автомобиль"), icon: "plus") { adding = true }
          .accessibilityIdentifier("payment-add-vehicle")
      }.padding(24)
    }.background(Palette.paper).foregroundStyle(Palette.ink)
      .sheet(
        isPresented: $adding,
        onDismiss: {
          if let newlyAdded {
            onSelect(newlyAdded)
            dismiss()
          }
        }
      ) {
        VehicleEditor { newlyAdded = $0 }
      }
  }
}
