import SwiftUI

struct GarageView: View {
  @EnvironmentObject private var model: AppModel
  @State private var adding = false
  @State private var account = false
  @State private var help = false
  @State private var choosingLanguage = false
  @State private var deleting: Vehicle?
  @State private var about = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          Eyebrow(text: L("Всё своё — под рукой"))
          Spacer()
          RoundButton(icon: "globe", label: L("Выбрать язык")) { choosingLanguage = true }
            .accessibilityIdentifier("language-settings")
          RoundButton(icon: "person.crop.circle", label: L("Личный кабинет")) { account = true }
        }
        Text(L("Мой гараж")).font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1)
        Text(L("Сохраните номер. В следующий раз\nон уже будет ждать вас.")).font(.system(size: 16))
          .foregroundStyle(Palette.muted).lineSpacing(4)
        ForEach(model.vehicles) { car in
          VStack(alignment: .leading, spacing: 16) {
            Button {
              model.selectedVehicleID = car.id
            } label: {
              VStack(alignment: .leading, spacing: 16) {
                HStack {
                  Image(systemName: car.isBus ? "bus.fill" : "car.side.fill")
                    .font(.system(size: 40)).foregroundStyle(Palette.green)
                  Spacer()
                  Image(
                    systemName: model.vehicle?.id == car.id ? "checkmark.circle.fill" : "circle"
                  )
                  .font(.title2).foregroundStyle(Palette.green)
                }
                Text(car.label).font(.system(size: 20, weight: .bold, design: .rounded))
                PlateView(plate: car.plate, countryCode: car.countryCode)
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("garage-vehicle-\(car.plate)")
            HStack {
              Text(
                model.vehicle?.id == car.id ? L("Выбран для парковки") : L("Нажмите, чтобы выбрать")
              )
              .font(.caption).foregroundStyle(Palette.muted)
              Spacer()
              Button(role: .destructive) {
                deleting = car
              } label: {
                Label(L("Удалить"), systemImage: "trash").font(.subheadline)
                  .frame(minHeight: 44)
              }.accessibilityIdentifier("delete-vehicle-\(car.plate)")
            }
          }.card().contextMenu {
            Button(L("Удалить с устройства"), role: .destructive) { deleting = car }
          }
        }
        if model.vehicles.isEmpty {
          VStack(spacing: 18) {
            Image(systemName: "car.side").font(.system(size: 66, weight: .light)).foregroundStyle(
              Palette.green)
            Text(L("Здесь будет ваш автомобиль")).font(.headline)
            Text(L("Достаточно номера — без документов\nи доступа к штрафам.")).font(.subheadline)
              .multilineTextAlignment(.center).foregroundStyle(Palette.muted)
          }.frame(maxWidth: .infinity).padding(.vertical, 32).card()
        }
        PrimaryButton(title: L("Добавить автомобиль"), icon: "plus") { adding = true }
          .accessibilityIdentifier("add-vehicle")
        Button {
          account = true
        } label: {
          HStack(spacing: 14) {
            Image(systemName: "person.crop.circle").font(.title2)
            VStack(alignment: .leading, spacing: 4) {
              Text(L("Кабинет Parkouka.by")).font(.headline)
              Text(model.loggedIn ? L("Подключён · история оплат") : L("Подключить историю оплат"))
                .font(
                  .caption
                ).foregroundStyle(Palette.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
          }.card()
        }.buttonStyle(.plain)
        InfoNote(
          icon: "lock.shield",
          text:
            L(
              "Номер хранится на устройстве. В кабинет он добавляется только по вашему выбору, без подтверждения права на информацию о штрафах."
            )
        )
        Button {
          about = true
        } label: {
          Label(L("О приложении и данные"), systemImage: "info.circle").font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier("about-app")
        Button(L("Как работает Стаянка")) { help = true }.font(.subheadline).frame(
          maxWidth: .infinity)
      }.padding(22)
    }.background(Palette.paper).foregroundStyle(Palette.ink).sheet(isPresented: $adding) {
      VehicleEditor()
    }.sheet(isPresented: $account) { AccountView() }.sheet(isPresented: $help) { GuideView() }
      .sheet(isPresented: $choosingLanguage) { LanguagePickerView() }
      .sheet(isPresented: $about) { AboutView() }
      .confirmationDialog(
        L("Удалить автомобиль из гаража?"),
        isPresented: Binding(
          get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible
      ) {
        Button(L("Удалить"), role: .destructive) {
          if let deleting { model.removeVehicle(deleting) }
          deleting = nil
        }
        Button(L("Назад"), role: .cancel) { deleting = nil }
      } message: {
        Text(
          L(
            "Автомобиль %@ будет удален из гаража. Оплаченные сеансы и история останутся; оплата не отменяется.",
            deleting?.plate ?? ""))
      }
  }
}

struct VehicleEditor: View {
  var onSaved: ((Vehicle) -> Void)? = nil
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var plate = ""
  @State private var nickname = ""
  @State private var bus = false
  @State private var countryCode = "BY"
  @State private var choosingCountry = false
  @State private var sync = false
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        SheetHeader(title: L("Ваш автомобиль"), dismiss: { dismiss() })
        Image(systemName: "car.side.fill").font(.system(size: 65)).foregroundStyle(Palette.green)
          .frame(maxWidth: .infinity).padding(.vertical, 20)
        Button {
          choosingCountry = true
        } label: {
          HStack(spacing: 12) {
            Text(VehicleCountry.flag(countryCode)).font(.title)
            VStack(alignment: .leading, spacing: 4) {
              Eyebrow(text: L("Страна регистрации"))
              Text(VehicleCountry.name(countryCode)).font(.headline)
            }
            Spacer()
            Image(systemName: "chevron.down").font(.caption.bold())
          }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("vehicle-country")
        VStack(alignment: .leading, spacing: 10) {
          Eyebrow(text: L("Номерной знак"))
          TextField("1234 AA-7", text: $plate).font(
            .system(size: 30, weight: .bold, design: .monospaced)
          ).textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(
            .asciiCapable
          ).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("vehicle-plate")
          Text(L("Можно вводить пробелы и дефис — мы уберём их.")).font(.caption).foregroundStyle(
            Palette.muted)
        }
        VStack(alignment: .leading, spacing: 10) {
          Eyebrow(text: L("Название · необязательно"))
          TextField(L("Например, моя машина"), text: $nickname).padding(18).background(
            .white, in: RoundedRectangle(cornerRadius: 18)
          ).accessibilityIdentifier("vehicle-name")
            .onChange(of: nickname) { _, value in
              if value.count > 40 { nickname = String(value.prefix(40)) }
            }
        }
        Toggle(L("Автобус (категория M2 / M3)"), isOn: $bus).font(.subheadline)
        if model.loggedIn { Toggle(L("Также добавить в кабинет"), isOn: $sync).font(.subheadline) }
        InfoNote(
          icon: "checkmark.shield",
          text:
            L(
              "Только номер для оплаты парковки. Мы не запрашиваем техпаспорт и не оформляем доступ к штрафам."
            )
        )
        if let error { Text(error).font(.subheadline).foregroundStyle(Palette.orange) }
        PrimaryButton(title: L("Сохранить автомобиль"), icon: "checkmark", busy: busy) { save() }
          .disabled(!Vehicle.isValid(plate)).opacity(Vehicle.isValid(plate) ? 1 : 0.45)
          .accessibilityIdentifier("save-vehicle")
      }.padding(24)
    }.background(Palette.paper).foregroundStyle(Palette.ink)
      .sheet(isPresented: $choosingCountry) { CountryPickerView(selection: $countryCode) }
  }
  private func save() {
    busy = true
    error = nil
    Task {
      do {
        let saved = Vehicle(
          plate: Vehicle.normalize(plate), nickname: Vehicle.cleanNickname(nickname),
          isBus: bus, countryCode: countryCode)
        try await model.add(saved, sync: sync)
        onSaved?(saved)
        dismiss()
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
}

struct AccountView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var email = ""
  @State private var password = ""
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        SheetHeader(title: L("Личный кабинет"), dismiss: { dismiss() })
        Text(model.loggedIn ? L("На связи\nс Parkouka.by") : L("Ваша история.\nВ одном месте."))
          .font(
            .system(size: 32, weight: .bold, design: .rounded))
        if !model.loggedIn {
          TextField(L("Электронная почта"), text: $email).textContentType(.username).keyboardType(
            .emailAddress
          ).textInputAutocapitalization(.never).autocorrectionDisabled().padding(18).background(
            .white, in: RoundedRectangle(cornerRadius: 18))
          SecureField(L("Пароль"), text: $password).textContentType(.password).padding(18)
            .background(
              .white, in: RoundedRectangle(cornerRadius: 18))
          PrimaryButton(title: L("Подключить кабинет"), icon: "arrow.right", busy: busy) { login() }
            .disabled(email.isEmpty || password.isEmpty)
          InfoNote(
            icon: "lock",
            text:
              L(
                "Вход напрямую в Parkouka.by. Пароль не сохраняется; сессия хранится в защищённом хранилище iPhone."
              )
          )
        } else {
          Label(L("Кабинет подключён"), systemImage: "checkmark.circle.fill").foregroundStyle(
            Palette.green)
          PrimaryButton(title: L("Обновить историю"), icon: "arrow.clockwise", busy: busy) {
            loadHistory()
          }
          if model.history.isEmpty {
            InfoNote(
              text:
                L(
                  "В кабинете пока нет загруженных оплат. Автомобиль должен быть добавлен в этот кабинет, чтобы его оплаты могли появиться в истории."
                )
            )
          }
          ForEach(model.history) { row in
            VStack(alignment: .leading, spacing: 8) {
              Text(row.regplate_full).font(.headline)
              Text(row.name).font(.subheadline)
              Text("\(row.starts_at) — \(row.valid_till)").font(.caption)
              Text("\(row.amount) BYN").font(.headline)
            }.frame(maxWidth: .infinity, alignment: .leading).card()
          }
          Button(L("Отключить кабинет"), role: .destructive) {
            Task {
              await model.api.logout()
              model.loggedIn = false
              model.history = []
            }
          }.frame(maxWidth: .infinity)
        }
        if let error { Text(error).font(.subheadline).foregroundStyle(Palette.orange) }
      }.padding(24)
    }.background(Palette.paper).foregroundStyle(Palette.ink)
  }
  private func login() {
    busy = true
    error = nil
    Task {
      do {
        try await model.api.login(
          email: email.trimmingCharacters(in: .whitespaces), password: password)
        password = ""
        model.loggedIn = true
        model.history = try await model.api.history()
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
  private func loadHistory() {
    busy = true
    error = nil
    Task {
      do { model.history = try await model.api.history() } catch {
        self.error = error.localizedDescription
      }
      busy = false
    }
  }
}
