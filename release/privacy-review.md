# Privacy label review

The App Store privacy questionnaire is a draft, not a published label.

The native app has no developer-operated backend, analytics SDK, advertising identifier access or advertising. Local garage data and local history are distinct from requests sent to the parking operator. Account authentication, parking calculation, payment creation and paid-time verification send data to external services.

Known draft categories: name (cardholder), email (optional account/receipt), payment information (embedded checkout), user ID (external account), purchases (parking payments), and other data (vehicle plate and parking parameters). Data is not anonymized before these service requests. Exact collection purposes and provider tracking still need verification before publishing the label.

On 2026-09-22, an unauthenticated inspection of the Parkouka homepage found Google Tag Manager and `gtag` code, plus Yandex map scripts. The card container allows the merchant return to execute while hiding its HTML. Hiding a page is not equivalent to preventing its network processing. bePaid's marketing homepage also contains analytics code; that alone does not establish what its checkout collects. No card fields were read or exported during this audit.

Confirm checkout/return-page analytics, identifiers and retention with the providers or a controlled network audit. Do not infer “no tracking” just from the native app having no advertising SDK. Security/fraud processing must be distinguished from advertising tracking.

Apple requires embedded web traffic and integrated third-party collection to be considered in the privacy label. Data handled solely on the device and Apple's own framework collection are treated separately: https://developer.apple.com/app-store/app-privacy-details/

The public privacy documents explain the observed native behavior and provider boundary. They do not claim to replace the operator's, payment processor's or bank's privacy notices.
