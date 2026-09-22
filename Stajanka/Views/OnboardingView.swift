import SwiftUI

struct OnboardingView: View {
  let finish: () -> Void
  @State private var step = 0
  @State private var choosingLanguage = false
  private let titles = [
    L("Город ваш.\nМесто найдётся."), L("Ваш автомобиль.\nИ ничего лишнего."),
    L("Оплатили.\nМожно выдохнуть."),
  ]
  private let texts = [
    L("Найдите парковку на карте, узнайте условия и спокойно займитесь своими делами."),
    L("Сохраните номер один раз. Документы, доступ к штрафам и подтверждение владения не нужны."),
    L(
      "Выберите время и оплатите через банк. Мы проверим оплаченное время и напомним об окончании."),
  ]
  var body: some View {
    GeometryReader { geo in
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          HStack(spacing: 8) {
            Image("BrandMark").resizable().frame(width: 30, height: 30).clipShape(
              RoundedRectangle(cornerRadius: 8))
            Text(L("стаянка")).font(.system(size: 24, weight: .bold, design: .rounded))
          }
          Spacer()
          Button {
            choosingLanguage = true
          } label: {
            Image(systemName: "globe").font(.title3).frame(width: 40, height: 44)
          }.accessibilityLabel(L("Выбрать язык")).accessibilityIdentifier("onboarding-language")
          Button(L("Пропустить"), action: finish).accessibilityIdentifier("skip-onboarding").font(
            .subheadline
          ).foregroundStyle(Palette.muted)
        }
        Spacer(minLength: 8)
        ZStack {
          RoundedRectangle(cornerRadius: 48).fill(Palette.lime).rotationEffect(.degrees(-5)).frame(
            width: 250, height: 230)
          Circle().stroke(Palette.ink.opacity(0.08), lineWidth: 1).frame(width: 300, height: 300)
          VStack(spacing: 20) {
            Image(
              systemName: step == 0
                ? "parkingsign.circle.fill" : step == 1 ? "car.side.fill" : "checkmark.circle.fill"
            ).font(.system(size: 90, weight: .light)).foregroundStyle(Palette.ink)
            HStack(spacing: 7) {
              Circle().fill(Palette.green).frame(width: 7, height: 7)
              Text(
                step == 0
                  ? L("МИНСК · В СВОЁМ РИТМЕ")
                  : step == 1 ? L("НОМЕР. И МОЖНО ЕХАТЬ.") : L("ВСЁ ПОД КОНТРОЛЕМ")
              ).font(.system(size: 10, weight: .bold)).tracking(1.5)
            }
          }
          Image(systemName: "location.north.fill").font(.title2).padding(18).background(
            .white, in: RoundedRectangle(cornerRadius: 20)
          ).rotationEffect(.degrees(10)).offset(x: 125, y: -80)
        }.frame(maxWidth: .infinity).frame(height: min(geo.size.height * 0.38, 310))
        Spacer(minLength: 0)
        HStack(spacing: 6) {
          ForEach(0..<3) { i in
            Capsule().fill(i == step ? Palette.ink : Palette.line).frame(
              width: i == step ? 28 : 7, height: 7)
          }
        }
        Text(titles[step]).font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.6)
          .fixedSize(horizontal: false, vertical: true)
        Text(texts[step]).font(.system(size: 17)).foregroundStyle(Palette.muted).lineSpacing(5)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        PrimaryButton(title: step == 2 ? L("Открыть карту") : L("Дальше")) {
          if step < 2 { withAnimation { step += 1 } } else { finish() }
        }
      }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
        .foregroundStyle(Palette.ink)
    }.sheet(isPresented: $choosingLanguage) { LanguagePickerView() }
  }
}

struct GuideView: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        SheetHeader(title: L("Парковка без суеты"), dismiss: { dismiss() })
        Text(L("Три простых шага")).font(.system(size: 32, weight: .bold, design: .rounded))
        guide(
          "01", L("Выберите место"),
          L("Нажмите на участок или найдите улицу. Сверьте номер зоны со знаком на парковке."),
          "map")
        guide(
          "02", L("Проверьте детали"),
          L("Укажите автомобиль и длительность. Точную сумму и срок рассчитает сервис парковок."),
          "slider.horizontal.3")
        guide(
          "03", L("Оплатите через банк"),
          L(
            "ЕРИП откроет банковское приложение, карта — защищённую страницу bePaid. Вернитесь сюда для проверки."
          ),
          "creditcard")
        InfoNote(
          icon: "checkmark.shield",
          text:
            L(
              "«Оплачено» появится только после подтверждения оплаченного времени сервисом. Пока идет проверка, ориентируйтесь на результат в банке."
            )
        )
        InfoNote(
          icon: "location",
          text: L(
            "Геолокация помогает найти парковку рядом. Вы всегда можете выбрать место вручную."))
        PrimaryButton(title: L("Понятно"), icon: "checkmark") { dismiss() }
      }.padding(24)
    }.background(Palette.paper)
  }
  private func guide(_ number: String, _ title: String, _ text: String, _ icon: String) -> some View
  {
    HStack(alignment: .top, spacing: 16) {
      Text(number).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(
        Palette.green
      ).padding(12).background(Palette.lime, in: RoundedRectangle(cornerRadius: 15))
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        Text(text).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(3)
      }
    }
  }
}
