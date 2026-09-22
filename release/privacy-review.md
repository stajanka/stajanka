# Privacy label review — 2026-09-22

The publisher confirmed that testing of the updated payment window and payment-page data processing completed successfully. The reported result is web analytics without advertising tracking. This is publisher-provided validation, not a claim that the developer independently audited every external bank.

The native app has no developer-operated backend, analytics SDK, advertising identifier access or advertising. Account authentication, calculation, payment creation and paid-time verification use external services. Local garage storage is separate from these requests.

The prepared answers were published in App Store Connect after the publisher explicitly accepted Apple's final declaration.

## App Store questionnaire

| Data type | Purpose | Linked to user | Advertising tracking |
| --- | --- | --- | --- |
| Name | App functionality: cardholder/payment processing | Yes | No |
| Email address | App functionality: optional account/receipt | Yes | No |
| Payment information | App functionality: embedded card checkout | Yes | No |
| Coarse location | App functionality: selected parking payment zone | Yes | No |
| User ID | App functionality: external service account | Yes | No |
| Device ID | App functionality/security and provider web analytics identifiers | Yes | No |
| Purchase history | App functionality: parking payments | Yes | No |
| Product interaction | Provider analytics and app functionality | Yes | No |
| Other data | App functionality: plate and parking parameters | Yes | No |

Linked-data answers reflect that service data and web identifiers are not anonymized before transmission. Coarse location describes the selected parking zone; the app does not transmit device GPS coordinates to Parkouka or a developer server. Device identifiers refer to provider/browser identifiers, not native IDFA access.

On-device data and Apple's own framework processing are distinct from third-party collection. The public and bundled policies explicitly disclose payment-page analytics, cookies/browser identifiers, page interactions, security and parking-zone processing. No advertising-tracking declaration is made based merely on the native app lacking an advertising SDK; the no-tracking answer follows the publisher's reported check.

Apple reference: https://developer.apple.com/app-store/app-privacy-details/
