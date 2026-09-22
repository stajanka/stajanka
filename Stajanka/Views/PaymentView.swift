import SwiftUI

struct PaymentView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  let zone: ParkingZone
  @State private var vehicle: Vehicle
  @State private var choosingVehicle = false
  @State private var quoteVehicleID: UUID?
  init(zone: ParkingZone, vehicle: Vehicle) {
    self.zone = zone
    _vehicle = State(initialValue: vehicle)
  }
  private var calculationKey: String { "\(vehicle.id)-\(hours)" }
  @State private var hours = 1
  @State private var quote: ParkingQuote?
  @State private var busy = false
  @State private var error: String?
  @State private var method = 0
  @State private var browser: BrowserLink?
  @State private var launched = false
  @State private var returnedFromCard = false
  @State private var requestID = UUID()
  private var existingPending: Bool {
    model.pending.contains { $0.quote.plate == vehicle.plate && $0.quote.zoneID == zone.paymentID }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 23) {
        SheetHeader(
          title: launched ? L("Проверяем оплату") : L("Время для своих дел"), dismiss: { dismiss() }
        )
        if launched { waitingContent } else { checkoutContent }
      }.padding(24)
    }.background(Palette.paper).foregroundStyle(Palette.ink)
      .task(id: calculationKey) { await calculate() }
      .sheet(isPresented: $choosingVehicle) {
        VehiclePickerView(selectedID: vehicle.id) { selected in
          // Invalidate the old quote synchronously, before the new task is scheduled.
          quote = nil
          quoteVehicleID = nil
          requestID = UUID()
          error = nil
          vehicle = selected
          model.selectedVehicleID = selected.id
        }
      }
      .fullScreenCover(
        item: $browser,
        onDismiss: {
          returnedFromCard = true
          Task { await model.checkPayments() }
        }
      ) { link in
        CardCheckoutView(url: link.url, cookies: link.cookies) { browser = nil }
      }
  }
  private var checkoutContent: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text(L("ЗОНА %@", String(describing: zone.number))).font(.system(size: 11, weight: .bold))
          .tracking(1.3).padding(9)
          .background(Palette.lime, in: Capsule())
        Spacer()
        Button {
          choosingVehicle = true
        } label: {
          HStack(spacing: 6) {
            PlateView(plate: vehicle.plate, countryCode: vehicle.countryCode)
            Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
          }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(L("Сменить автомобиль"))
          .accessibilityValue("\(vehicle.plate), \(vehicle.countryCode)").accessibilityIdentifier(
            "payment-vehicle")
      }
      Text(zone.title).font(.system(size: 20, weight: .semibold, design: .rounded)).fixedSize(
        horizontal: false, vertical: true)
      HStack(alignment: .center, spacing: 18) {
        Button {
          hours = max(1, hours - 1)
        } label: {
          Image(systemName: "minus").font(.title3).frame(width: 48, height: 48).background(
            .white, in: Circle())
        }.disabled(hours == 1).accessibilityLabel(L("Уменьшить время"))
        Spacer()
        VStack(spacing: 3) {
          Text("\(hours)").font(.system(size: 70, weight: .bold, design: .rounded)).tracking(-3)
            .contentTransition(.numericText())
          Text(L10n.hoursWord(hours)).font(.system(size: 15))
            .foregroundStyle(Palette.muted)
        }
        Spacer()
        Button {
          hours = min(24, hours + 1)
        } label: {
          Image(systemName: "plus").font(.title3).frame(width: 48, height: 48).background(
            .white, in: Circle())
        }.disabled(hours == 24).accessibilityLabel(L("Увеличить время"))
      }.padding(.horizontal, 20)
      HStack(spacing: 8) {
        ForEach([1, 2, 3, 5], id: \.self) { h in
          Button {
            withAnimation { hours = h }
          } label: {
            Text(L("%@ ч", String(describing: h))).font(.system(size: 14, weight: .semibold)).frame(
              maxWidth: .infinity
            )
            .padding(.vertical, 12).background(hours == h ? Palette.lime : .white, in: Capsule())
          }.buttonStyle(.plain).accessibilityIdentifier("duration-\(h)")
        }
      }
      VStack(spacing: 14) {
        HStack {
          Text(L("К оплате")).foregroundStyle(Palette.muted)
          Spacer()
          if busy {
            ProgressView()
          } else {
            Text(quote?.amountLabel ?? "—").font(.system(size: 25, weight: .bold, design: .rounded))
          }
        }
        Divider()
        HStack {
          Text(quote?.isExtension == true ? L("Продление до") : L("Парковка до")).foregroundStyle(
            Palette.muted)
          Spacer()
          Text(quote?.endDate.map { ParkingDate.time($0) } ?? "—").font(.headline)
        }
        if let q = quote, q.hours != hours {
          Text(
            L(
              "На закрытой парковке длительность определяет сервис: %@ ч.",
              String(describing: q.hours))
          ).font(.caption)
            .foregroundStyle(Palette.muted)
        }
      }.card()
      Eyebrow(text: L("Как вам удобнее оплатить?"))
      HStack(spacing: 10) {
        paymentMethod(L("ЕРИП"), L("В приложении банка"), icon: "qrcode", index: 0)
        paymentMethod(L("Банковская карта"), L("Через bePaid"), icon: "creditcard", index: 1)
      }
      if let error {
        Text(error).font(.subheadline).foregroundStyle(Palette.orange)
        Button(L("Рассчитать заново")) { Task { await calculate() } }
      }
      if existingPending {
        InfoNote(
          icon: "clock",
          text:
            L(
              "Для этого автомобиля и зоны уже ожидается подтверждение. Проверьте платеж на вкладке «Парковка» перед повторной оплатой."
            )
        )
      }
      PrimaryButton(
        title: quote.map { L("Оплатить %@", String(describing: $0.amountLabel)) }
          ?? L("Получаем стоимость"),
        icon: "arrow.up.right", busy: busy
      ) { launch() }.disabled(
        quote == nil || quoteVehicleID != vehicle.id || busy || existingPending
          || (Decimal(string: quote?.amount ?? "0") ?? 0) <= 0
      ).opacity(quote == nil || existingPending ? 0.5 : 1).accessibilityIdentifier("pay-parking")
      Text(
        L(
          "Проверьте номер автомобиля и зону на знаке. Оплата откроется в банке; после неё вернитесь в Стаянку."
        )
      ).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
    }
  }
  private var waitingContent: some View {
    VStack(alignment: .leading, spacing: 24) {
      Image(
        systemName: paymentConfirmed ? "checkmark.circle.fill" : "clock.arrow.circlepath"
      ).font(.system(size: 66, weight: .light)).foregroundStyle(Palette.green).frame(
        maxWidth: .infinity
      ).padding(.vertical, 22)
      Text(
        paymentConfirmed
          ? L("Время парковки\nподтверждено")
          : returnedFromCard
            ? L("Проверяем\nоплату парковки") : L("Вернитесь после\nоплаты в банке")
      ).font(.system(size: 32, weight: .bold, design: .rounded))
      InfoNote(
        text: model.checkMessage
          ?? L(
            "Мы проверяем оплаченное время на стороне сервиса. Это может занять некоторое время."))
      if let error { InfoNote(icon: "exclamationmark.circle", text: error) }
      if let message = model.accountCheckMessage {
        InfoNote(icon: "person.crop.circle", text: message)
      }
      if paymentConfirmed {
        if let end = model.sessions.first(where: { $0.quote == quote })?.endDate {
          Text(L("Оплачено до %@", String(describing: ParkingDate.time(end)))).font(.title3.bold())
        }
        PrimaryButton(title: L("Готово"), icon: "checkmark") { dismiss() }
      } else {
        PrimaryButton(title: L("Проверить оплату"), icon: "arrow.clockwise", busy: model.checking) {
          Task { await model.checkPayments() }
        }
        Button(L("Вернуться к карте")) { dismiss() }.frame(maxWidth: .infinity)
        Text(
          L(
            "Закрытие платежной страницы не означает успешную оплату. Если банк не подтвердил платеж, проверьте его статус перед повторной попыткой."
          )
        ).font(.caption).foregroundStyle(Palette.muted)
      }
    }
  }
  private var paymentConfirmed: Bool {
    model.sessions.contains { $0.quote == quote && $0.state == .confirmed }
  }
  private func paymentMethod(_ title: String, _ subtitle: String, icon: String, index: Int)
    -> some View
  {
    Button {
      method = index
    } label: {
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Image(systemName: icon).font(.title2)
          Spacer()
          Image(systemName: method == index ? "checkmark.circle.fill" : "circle").foregroundStyle(
            method == index ? Palette.green : Palette.line)
        }
        Text(title).font(.headline)
        Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
      }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(
        .white, in: RoundedRectangle(cornerRadius: 20)
      ).overlay(
        RoundedRectangle(cornerRadius: 20).stroke(
          method == index ? Palette.green : Color.clear, lineWidth: 1.5))
    }.buttonStyle(.plain)
  }
  private func calculate() async {
    let id = UUID()
    requestID = id
    busy = true
    quote = nil
    quoteVehicleID = nil
    error = nil
    do {
      try await Task.sleep(for: .milliseconds(250))
      let value = try await model.parkingQuote(vehicle: vehicle, zone: zone, hours: hours)
      guard requestID == id, !Task.isCancelled else { return }
      quote = value
      quoteVehicleID = vehicle.id
    } catch {
      guard requestID == id, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
    if requestID == id { busy = false }
  }
  private func launch() {
    guard !model.isScreenshotSession else {
      error = L("Демонстрационные данные. Оплата отключена.")
      return
    }
    guard let quote, !busy, quoteVehicleID == vehicle.id, quote.plate == vehicle.plate else {
      return
    }
    guard Date().timeIntervalSince(quote.createdAt) < 90 else {
      error = L("Расчёт устарел. Обновите сумму перед оплатой.")
      self.quote = nil
      Task { await calculate() }
      return
    }
    let url: URL
    if method == 0 {
      guard let s = quote.eripURL, let u = URL(string: s), u.scheme == "https",
        u.host == "pay.raschet.by"
      else {
        error = L("Сервис не вернул ссылку ЕРИП. Попробуйте расчёт ещё раз.")
        return
      }
      url = u
    } else {
      url = quote.cardURL
    }
    model.begin(quote)
    launched = true
    if method == 0 {
      openURL(url) { accepted in
        if !accepted { error = L("Не удалось открыть банк. Платёж сохранён для проверки.") }
      }
    } else {
      busy = true
      Task {
        let cookies = await model.api.checkoutCookies()
        browser = BrowserLink(url: url, cookies: cookies)
        busy = false
      }
    }
  }
}
struct BrowserLink: Identifiable {
  let id = UUID()
  let url: URL
  let cookies: [HTTPCookie]
}
