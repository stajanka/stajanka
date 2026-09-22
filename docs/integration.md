# Parkouka integration

Last checked: 22 September 2026. These are observed website endpoints, not a published/versioned API. Their contract may change. Public availability is not a declaration of a third-party distribution license; any required authorization must be established before App Review.

## Map and calculation

`GET /` embeds `window.__BOOTSTRAP__.zonesHash`. The app extracts the balanced JSON object with string/escape handling. Coordinates are latitude/longitude; `windowPos` positions labels. Payment uses `parent_zone_id ?? id`. The initial public snapshot contains 85 areas and six distinct payment-zone IDs.

1. `GET /payments/payg/calc?step=1&regplate=...&zid=...&tmid=...` returns authoritative start/extension information.
2. `GET /payments/payg/calc?step=2&regplate=...&zid=...&t_start=...&hrs=...&ext=...&tmid=...` returns price, expiry and ERIP URL.
3. ERIP uses the returned HTTPS `pay.raschet.by` URL. Card payment opens `/payments/card/start_payment` with the same parameters, redirecting to bePaid.

Timezone plus signs are percent-encoded as `%2B`. Open parking uses `found` for extension; gated parking also requires positive `paid_dur`, and can use server-supplied duration/tariff. Quotes are locally limited to 90 seconds. Plate country is display metadata; no undocumented country parameter is sent.

## Confirmation

A bank return is not payment proof. The app verifies paid coverage for the same plate, payment zone and tariff, through at least the quoted expiry and beyond the original paid starting point. Current coverage cannot retrospectively confirm an expired attempt. Authenticated history may corroborate an exact plate/zone/amount/period match; unknown formats fail closed.

During real user-authorized ERIP and card tests, paid coverage advanced as expected, while the connected account history remained empty. Coverage is therefore the verified fallback. ERIP started its paid period at settlement rather than quote creation: confirmed expiry is stored separately and used for timers and reminders. Outside-app payments can be restored by checking the supported payment-zone IDs for a saved vehicle. No price or precise parking street is invented when restoring coverage.

## Native card return

A dedicated WKWebView displays bePaid and bank/3-D Secure pages. Merchant main-frame documents are concealed before navigation is allowed, including server navigation responses. The callback still executes in the same browser context. On completion the bank sheet dismisses and native coverage verification runs. Session cookies are supplied in an ephemeral WebKit store. No scripts or credential-reading handlers are injected into bank pages.

Real WebKit fixture tests exercise successful/failed returns and verify that callback processing occurs without displaying merchant HTML. Live bank payments validated the provider contract; each materially changed bank-container version still needs device/3-D Secure testing before release.

## Accounts and local storage

Optional login posts credentials to `/users/sign_in` with Rails CSRF. Passwords are not persisted; cookies use Keychain with device-only accessibility. History uses `/account/parking_sessions`. Optional vehicle registration posts only `regplate` and `veh_type` to `/vehicles/add`, omitting documents, owner fields and ownership consent.

The app does not call violation/fine endpoints. Garage/session data are stored in the app's local UserDefaults container. Garage deletion retains parking history and does not cancel payments. Full local-data deletion clears vehicles, history, reminders and the saved login session. External service records remain with those services.

## Verification boundaries

Simulator builds, localization/migration tests, quote/vehicle-selection tests, real WebKit return fixtures and physical-device installation have passed. Network/vendor changes and bank-specific authentication can still affect operation. Foreground polling is not continuous background monitoring. Local notifications require permission and are not a guarantee against parking expiry.
