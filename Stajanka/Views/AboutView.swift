import SwiftUI

struct LegalDocument: Decodable {
  struct Section: Decodable {
    let title: String
    let body: String
  }
  let title: String
  let updated: String
  let sections: [Section]
  static func load(_ kind: String) -> LegalDocument? {
    guard
      let url = Bundle.main.url(
        forResource: "\(kind)-\(L10n.language.rawValue)", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
}
struct AboutView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var erase = false
  @State private var erasing = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 16) {
            Image("BrandMark").resizable().frame(width: 64, height: 64)
              .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
              Text(L("стаянка")).font(.title.bold())
              Text(
                "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
              )
              .font(.caption).foregroundStyle(Palette.muted)
            }
          }
          InfoNote(
            text: L(
              "Независимое приложение для парковки в Минске. Стаянка не является официальным приложением Parkouka.by или оператора парковок."
            ))
          NavigationLink {
            LegalDocumentView(kind: "privacy")
          } label: {
            Label(L("Политика конфиденциальности"), systemImage: "hand.raised").frame(minHeight: 44)
          }.accessibilityIdentifier("privacy-policy")
          NavigationLink {
            LegalDocumentView(kind: "terms")
          } label: {
            Label(L("Условия использования"), systemImage: "doc.text").frame(minHeight: 44)
          }
          NavigationLink {
            LegalDocumentView(kind: "support")
          } label: {
            Label(L("Поддержка"), systemImage: "questionmark.circle").frame(minHeight: 44)
          }
          Link(destination: URL(string: "mailto:sosambus@icloud.com?subject=Stajanka")!) {
            Label("sosambus@icloud.com", systemImage: "envelope").frame(minHeight: 44)
          }
          Link(
            L("Управление аккаунтом Parkouka.by"),
            destination: URL(string: "https://parkouka.by/users/edit")!
          )
          .font(.subheadline).frame(minHeight: 44)
          Divider()
          Text(L("Ваши данные")).font(.headline)
          InfoNote(
            text: L(
              "Удаление из гаража сохраняет историю парковок. Полная очистка ниже удалит автомобили, локальную историю, напоминания и сеанс входа с этого устройства. Платежи и аккаунт Parkouka.by останутся у оператора."
            ))
          Button(role: .destructive) {
            erase = true
          } label: {
            Label(L("Удалить локальные данные"), systemImage: "trash").frame(minHeight: 44)
          }.disabled(erasing).accessibilityIdentifier("erase-local-data")
        }.padding(24)
      }.background(Palette.paper).foregroundStyle(Palette.ink)
        .navigationTitle(L("О приложении и данные")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Готово")) { dismiss() } } }
        .confirmationDialog(
          L("Удалить локальные данные?"), isPresented: $erase, titleVisibility: .visible
        ) {
          Button(L("Удалить"), role: .destructive) {
            erasing = true
            Task {
              await model.eraseLocalData()
              erasing = false
              dismiss()
            }
          }
          Button(L("Назад"), role: .cancel) {}
        } message: {
          Text(
            L(
              "Оплаченная парковка не отменится. Сохраненные на этом устройстве автомобили и история будут удалены."
            ))
        }
    }.tint(Palette.ink)
  }
}
struct LegalDocumentView: View {
  let kind: String
  var body: some View {
    ScrollView {
      if let document = LegalDocument.load(kind) {
        VStack(alignment: .leading, spacing: 20) {
          Text(document.title).font(.title.bold())
          Text(document.updated).font(.caption).foregroundStyle(Palette.muted)
          ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
            VStack(alignment: .leading, spacing: 8) {
              Text(section.title).font(.headline)
              Text(.init(section.body)).font(.body).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }.padding(24)
      }
    }.background(Palette.paper).foregroundStyle(Palette.ink)
  }
}
