# Стаянка / Stajanka

Independent native iOS parking companion for Minsk, built with SwiftUI and MapKit. Belarusian is the default interface language; Russian and English are available in the garage and onboarding.

## Features

- Parking polygons, street/zone search, optional foreground location and accessible zoom controls.
- Local garage with countries and flags, visible removal controls and checkout vehicle switching.
- Server-calculated parking quotes; ERIP or secure bePaid checkout for real-world parking.
- Paid-time verification, current parking restoration and local expiry reminders.
- Optional connection to an existing Parkouka.by account; device-only Keychain session storage.
- In-app privacy information, terms, support and local data deletion.

Stajanka is an independent client and is not represented as an official product of Parkouka.by, a parking operator, bePaid or Apple. The app is free; parking fees are paid to the relevant operator. It does not query fines or ask for vehicle ownership documents.

## Build and test

Requires Xcode 26 or later and XcodeGen. Deployment target: iOS 17+. No third-party Swift dependencies.

```sh
xcodegen generate
xcodebuild -project Stajanka.xcodeproj -scheme Stajanka \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
python3 scripts/check_localizations.py
```

Open `Stajanka.xcodeproj` and choose your own signing team for a device build. Signing identities and private provisioning files are not included.

## Documentation and policies

- [Integration contract and limitations](docs/integration.md)
- [Release preparation](release/README.md)
- [Privacy policy](release/policies/privacy-en.md) · [Русский](release/policies/privacy-ru.md) · [Беларуская](release/policies/privacy-be.md)
- [Terms](release/policies/terms-en.md) · [Support](release/policies/support-en.md)

Native translations are in `Stajanka/Resources/{be,ru,en}.lproj`. Legal documents are generated for the app and public Markdown from `scripts/build_legal_documents.py`.

## Privacy of this repository

Screenshots use fictional demonstration vehicles in an isolated simulator. Real plate numbers, payment tokens, account cookies, captured traffic, developer device identifiers and private local investigation records are excluded. The public support address is intentionally included.
