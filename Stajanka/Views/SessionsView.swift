import SwiftUI

struct SessionsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var removing: ParkingSession?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Eyebrow(text: L("Время под контролем"))
        Text(L("Моя парковка")).font(.system(size: 36, weight: .bold, design: .rounded)).tracking(
          -1)
        if model.sessions.isEmpty {
          VStack(spacing: 18) {
            ZStack {
              Circle().fill(Palette.lime).frame(width: 130, height: 130)
              Image(systemName: "timer").font(.system(size: 62, weight: .light)).foregroundStyle(
                Palette.ink)
            }
            Text(L("Пока можно не спешить")).font(
              .system(size: 22, weight: .bold, design: .rounded))
            Text(L("После оплаты здесь появится\nоставшееся время парковки.")).font(.subheadline)
              .foregroundStyle(Palette.muted).multilineTextAlignment(.center)
          }.padding(.vertical, 35).frame(maxWidth: .infinity).card()
          InfoNote(
            icon: "bell.badge",
            text:
              L(
                "После подтверждения оплаты предложим напомнить за 10 минут до окончания. Проверка оплаты работает, пока приложение открыто."
              )
          )
        }
        ForEach(model.sessions) { entry in sessionCard(entry) }
        if !model.pending.isEmpty {
          PrimaryButton(title: L("Проверить оплату"), icon: "arrow.clockwise", busy: model.checking)
          {
            Task { await model.checkPayments() }
          }
        }
        if let message = model.checkMessage { InfoNote(icon: "info.circle", text: message) }
        if let message = model.accountCheckMessage {
          InfoNote(icon: "person.crop.circle.badge.exclamationmark", text: message)
        }
      }.padding(22)
    }.refreshable {
      await model.checkPayments()
      await model.restoreCurrentParking()
    }.task { await model.restoreCurrentParking() }
      .background(Palette.paper).foregroundStyle(Palette.ink).confirmationDialog(
        L("Убрать ожидание из приложения?"),
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        titleVisibility: .visible
      ) {
        Button(L("Убрать ожидание"), role: .destructive) {
          if let removing { model.sessions.removeAll { $0.id == removing.id } }
          removing = nil
        }
        Button(L("Назад"), role: .cancel) { removing = nil }
      } message: {
        Text(
          L(
            "Это не отменяет платёж в банке и не возвращает деньги. Сначала проверьте результат оплаты."
          )
        )
      }
  }
  private func sessionCard(_ entry: ParkingSession) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Label(
          entry.state == .awaiting
            ? L("ЖДЁМ ПОДТВЕРЖДЕНИЯ")
            : (entry.endDate ?? .distantPast) > Date() ? L("ОПЛАЧЕННОЕ ВРЕМЯ") : L("ЗАВЕРШЕНА"),
          systemImage: entry.state == .awaiting ? "clock" : "checkmark.circle.fill"
        ).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(
          entry.state == .awaiting ? Palette.orange : Palette.green)
        Spacer()
      }
      PlateView(
        plate: entry.quote.plate,
        countryCode: entry.quote.countryCode ?? model.vehicles.first(where: {
          $0.plate == entry.quote.plate
        })?.countryCode ?? "BY")
      Text(entry.quote.displayZoneTitle).font(
        .system(size: 18, weight: .semibold, design: .rounded))
      if entry.state == .confirmed, let end = entry.endDate, end > Date() {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let remaining = max(0, Int(end.timeIntervalSince(context.date)))
          Text(
            String(
              format: "%02d:%02d:%02d", remaining / 3600, remaining % 3600 / 60, remaining % 60)
          ).font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
        }
        Text(
          L(
            "До %@ · %@", String(describing: ParkingDate.time(end)),
            String(describing: entry.quote.amountLabel))
        ).font(.subheadline)
          .foregroundStyle(Palette.muted)
      } else {
        Text(
          entry.state == .awaiting
            ? L(
              "Пока сервис не подтвердил оплаченное время, парковка здесь не считается оплаченной.")
            : entry.quote.amountLabel
        ).font(.subheadline).foregroundStyle(Palette.muted)
      }
      if let checked = entry.lastChecked {
        Text(L("Проверено в %@", String(describing: ParkingDate.time(checked)))).font(.caption)
          .foregroundStyle(
            Palette.muted)
      }
      if entry.confirmationSource == .accountHistory {
        Label(L("Подтверждено историей кабинета"), systemImage: "checkmark.shield")
          .font(.caption).foregroundStyle(Palette.green)
      }
      if entry.state == .awaiting, (entry.endDate ?? .distantPast) <= Date() {
        Text(
          L(
            "Расчётный срок завершился. Проверить прошлую оплату можно по истории кабинета или чеку банка."
          )
        )
        .font(.caption).foregroundStyle(Palette.muted)
      }
      if entry.state == .awaiting {
        Button(L("Оплата не состоялась")) { removing = entry }.font(.caption).foregroundStyle(
          Palette.muted)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).card()
  }
}
