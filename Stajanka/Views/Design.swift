import SwiftUI

enum Palette {
  static let ink = Color(red: 0.09, green: 0.19, blue: 0.17)
  static let green = Color(red: 0.18, green: 0.35, blue: 0.28)
  static let lime = Color(red: 0.81, green: 0.91, blue: 0.51)
  static let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
  static let muted = Color(red: 0.39, green: 0.44, blue: 0.41)
  static let line = Color(red: 0.88, green: 0.9, blue: 0.86)
  static let orange = Color(red: 0.77, green: 0.34, blue: 0.16)
}
struct PrimaryButton: View {
  var title: String
  var icon: String = "arrow.right"
  var busy = false
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack {
        Spacer()
        if busy {
          ProgressView().tint(.white)
        } else {
          Text(title).font(.system(.headline, design: .rounded))
          Image(systemName: icon)
        }
        Spacer()
      }.padding(.vertical, 18).background(Palette.ink, in: RoundedRectangle(cornerRadius: 22))
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain).disabled(busy)
  }
}
struct RoundButton: View {
  let icon: String
  let label: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 19, weight: .semibold)).frame(
        width: 48, height: 48
      ).background(.white, in: Circle()).foregroundStyle(Palette.ink).shadow(
        color: .black.opacity(0.07), radius: 12, y: 4)
    }.buttonStyle(.plain).accessibilityLabel(label)
  }
}
struct Eyebrow: View {
  let text: String
  var body: some View {
    Text(text.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2)
      .foregroundStyle(Palette.muted)
  }
}
struct InfoNote: View {
  var icon = "info.circle"
  let text: String
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon).font(.system(size: 18))
      Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
    }.foregroundStyle(Palette.muted).padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.paper, in: RoundedRectangle(cornerRadius: 18))
  }
}
struct PlateView: View {
  let plate: String
  var countryCode: String = "BY"
  var body: some View {
    HStack(spacing: 8) {
      VStack(spacing: 2) {
        Text(VehicleCountry.flag(countryCode)).font(.system(size: 16))
        Text(countryCode).font(.system(size: 8, weight: .bold))
      }
      Text(plate).font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(1)
    }.padding(.horizontal, 11).padding(.vertical, 8).foregroundStyle(Palette.ink).background(
      .white, in: RoundedRectangle(cornerRadius: 9)
    ).overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
  }
}
struct SheetHeader: View {
  let title: String
  var dismiss: () -> Void
  var body: some View {
    HStack {
      Text(title).font(.system(size: 23, weight: .bold, design: .rounded))
      Spacer()
      Button(action: dismiss) {
        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(
          width: 36, height: 36
        ).background(Palette.paper, in: Circle())
      }.accessibilityLabel(L("Закрыть")).accessibilityIdentifier("sheet-close")
    }.foregroundStyle(Palette.ink)
  }
}
extension View {
  func card() -> some View {
    self.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 26))
  }
}
