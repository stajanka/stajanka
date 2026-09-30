# Privacy label review — 2026-09-30

The publisher confirmed that testing of the updated payment window and payment-page data processing completed successfully. The reported result is web analytics without advertising tracking. This is publisher-provided validation, not a claim that the developer independently audited every external bank.

The native app has no developer-operated backend, analytics SDK, advertising identifier access or advertising. Calculation, payment creation and paid-time verification use external services without a Parkouka account. Vehicles and local parking history are stored in an on-device SQLite database, separately from these requests. There is no cloud synchronization.

The previous questionnaire was published in App Store Connect on 22 September after the publisher explicitly accepted Apple's final declaration. The table below describes the revised app without Parkouka account integration. It does not assert that these revised answers have already been published.

## Changes in the account-free version

The app has no account creation, sign-in, Parkouka email/password input, saved login session, account-history request or remote vehicle registration. Upgrade cleanup removes the app's previous saved login credentials and session cookies. Existing local garage and parking records migrate from legacy UserDefaults to SQLite without deletion.

History contains locally recorded attempts and paid periods observed or confirmed on this device. Public checks may restore a plate's current paid coverage, including parking purchased elsewhere, without retrieving a complete transaction history or unknown amounts. A garage deletion keeps parking records; full local-data deletion removes vehicles, history, reminders and payment web data. Neither operation deletes records held by external services or reverses a payment.

Removing login does not mean that no data is collected. Public payment requests still send a plate, zone, duration, start time and tariff. Provider and bank pages still process payments, perform security checks and use web analytics. No Parkouka app-account purpose should remain in the metadata or review credentials fields.

## App Store questionnaire

| Data type | Purpose | Linked to user | Advertising tracking |
| --- | --- | --- | --- |
| Name | App functionality: cardholder/payment processing | Yes | No |
| Email address | App functionality: receipt/payment-provider processing when requested | Yes | No |
| Payment information | App functionality: embedded card checkout | Yes | No |
| Coarse location | App functionality: selected parking payment zone | Yes | No |
| Device ID | App functionality/security and provider web analytics identifiers | Yes | No |
| Purchase history | App functionality: parking payments | Yes | No |
| Product interaction | Provider analytics and app functionality | Yes | No |
| Other data | App functionality: plate and parking parameters | Yes | No |

Linked-data answers reflect that service data and web identifiers are not anonymized before transmission. Coarse location describes the selected parking zone; the app does not transmit device GPS coordinates to Parkouka or a developer server. Device identifiers refer to provider/browser identifiers, not native IDFA access.

The former User ID entry was justified by the optional Parkouka account and is not justified by the new native app. Before removing that entry from App Store Connect, verify that the previously tested payment-provider flow does not collect a separate user/account identifier. A provider identifier should be disclosed for its actual purpose even though native sign-in was removed. Email, payment information and purchase history must not be removed merely because their native account-history source disappeared; payment pages can still collect them.

On-device data and Apple's own framework processing are distinct from third-party collection. The public and bundled policies explicitly disclose payment-page analytics, cookies/browser identifiers, page interactions, security and parking-zone processing. No advertising-tracking declaration is made based merely on the native app lacking an advertising SDK; the no-tracking answer follows the publisher's reported check.

Apple reference: https://developer.apple.com/app-store/app-privacy-details/
