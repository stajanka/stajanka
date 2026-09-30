import SwiftUI

struct SessionsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var removing: ParkingSession?
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let active = model.sessions.filter {
        $0.state == .confirmed && ($0.endDate ?? .distantPast) > context.date
      }
      let completed = model.sessions.filter {
        $0.state == .confirmed && ($0.endDate ?? .distantPast) <= context.date
      }.sorted { ($0.endDate ?? $0.quote.createdAt) > ($1.endDate ?? $1.quote.createdAt) }
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
              Text(L("После подтверждения оплаты здесь появятся таймер и запись в истории."))
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            }.padding(.vertical, 35).frame(maxWidth: .infinity).card()
            InfoNote(
              icon: "bell.badge",
              text: L(
                "После подтверждения оплаты предложим напомнить за 10 минут до окончания. Проверка оплаты работает, пока приложение открыто."
              ))
          }
          if let message = model.storageMessage {
            InfoNote(icon: "exclamationmark.triangle", text: message)
          }
          ForEach(active) { entry in sessionCard(entry, now: context.date) }
          if !model.pending.isEmpty {
            Text(L("Ожидают подтверждения")).font(.title3.bold())
            ForEach(model.pending) { entry in sessionCard(entry, now: context.date) }
            PrimaryButton(
              title: L("Проверить оплату"), icon: "arrow.clockwise", busy: model.checking
            ) {
              Task { await model.checkPayments() }
            }
          }
          if let message = model.checkMessage { InfoNote(icon: "info.circle", text: message) }
          VStack(alignment: .leading, spacing: 10) {
            Text(L("История парковок")).font(.title2.bold())
              .accessibilityIdentifier("local-parking-history")
            Text(
              L(
                "История сохраняется только на этом устройстве. Здесь остаются парковки, оплату которых приложение успело подтвердить."
              )
            )
            .font(.subheadline).foregroundStyle(Palette.muted)
          }
          if completed.isEmpty {
            Text(
              L(
                "Завершённые оплаченные парковки появятся здесь. Неподтверждённые попытки в историю не попадают."
              )
            )
            .font(.subheadline).foregroundStyle(Palette.muted).frame(
              maxWidth: .infinity, alignment: .leading
            ).card()
          } else {
            ForEach(completed) { entry in historyCard(entry) }
          }
        }.padding(22)
      }.refreshable {
        await model.checkPayments()
        await model.restoreCurrentParking()
      }
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
          ))
      }
  }
  private func sessionCard(_ entry: ParkingSession, now: Date) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Label(
        entry.state == .awaiting ? L("ЖДЁМ ПОДТВЕРЖДЕНИЯ") : L("ОПЛАЧЕННОЕ ВРЕМЯ"),
        systemImage: entry.state == .awaiting ? "clock" : "checkmark.circle.fill"
      ).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(
        entry.state == .awaiting ? Palette.orange : Palette.green)
      plate(entry)
      Text(entry.quote.displayZoneTitle).font(
        .system(size: 18, weight: .semibold, design: .rounded))
      if entry.state == .confirmed, let end = entry.endDate, end > now {
        let remaining = max(0, Int(end.timeIntervalSince(now)))
        Text(
          String(format: "%02d:%02d:%02d", remaining / 3600, remaining % 3600 / 60, remaining % 60)
        )
        .font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
        Text(L("До %@ · %@", ParkingDate.time(end), amountLabel(entry)))
          .font(.subheadline).foregroundStyle(Palette.muted)
        sourceLabel(entry)
      } else {
        Text(
          L("Пока сервис не подтвердил оплаченное время, парковка здесь не считается оплаченной.")
        )
        .font(.subheadline).foregroundStyle(Palette.muted)
      }
      if let checked = entry.lastChecked {
        Text(L("Проверено: %@", dateTime(checked))).font(.caption).foregroundStyle(Palette.muted)
      }
      if entry.state == .awaiting, (entry.endDate ?? .distantPast) <= now {
        Text(
          L(
            "Расчётный срок завершился. Приложение не успело подтвердить оплату. Проверьте чек в банке; эта попытка не включена в историю оплаченных парковок."
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
  private func historyCard(_ entry: ParkingSession) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(L("ЗАВЕРШЕНА"), systemImage: "checkmark.circle.fill")
        .font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Palette.green)
      plate(entry)
      Text(entry.quote.displayZoneTitle).font(
        .system(size: 18, weight: .semibold, design: .rounded))
      if let start = ParkingDate.parse(entry.quote.start) {
        Text(L("Начало: %@", dateTime(start))).font(.subheadline).foregroundStyle(Palette.muted)
      }
      if let end = entry.endDate {
        Text(L("Окончание: %@", dateTime(end))).font(.subheadline).foregroundStyle(Palette.muted)
      }
      Text(amountLabel(entry)).font(.headline)
      sourceLabel(entry)
    }.frame(maxWidth: .infinity, alignment: .leading).card()
      .accessibilityIdentifier("parking-history-\(entry.id.uuidString)")
  }
  private func plate(_ entry: ParkingSession) -> some View {
    PlateView(
      plate: entry.quote.plate,
      countryCode: entry.quote.countryCode ?? model.vehicles.first(where: {
        $0.plate == entry.quote.plate
      })?.countryCode ?? "BY")
  }
  @ViewBuilder
  private func sourceLabel(_ entry: ParkingSession) -> some View {
    if entry.quote.amount.isEmpty {
      Text(
        L(
          "Оплаченное время найдено по номеру автомобиля. Сумма и способ оплаты сервисом не переданы."
        )
      )
      .font(.caption).foregroundStyle(Palette.muted)
    } else {
      Label(L("Подтверждение сохранено на этом устройстве"), systemImage: "checkmark.shield")
        .font(.caption).foregroundStyle(Palette.green)
    }
  }
  private func amountLabel(_ entry: ParkingSession) -> String {
    entry.quote.amount.isEmpty ? L("Сумма неизвестна") : entry.quote.amountLabel
  }
  private func dateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = L10n.locale
    formatter.timeZone = TimeZone(identifier: "Europe/Minsk")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
