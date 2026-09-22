# Release status — 2026-09-22

App: Stajanka / Стаянка, `by.stajanka.app`, version 1.0.0 (4).
App Store Connect record: `6814781315`.

## Completed

- Public source and legal documents published at https://github.com/stajanka/stajanka under the stajanka organization.
- Visible garage deletion with confirmation; deleting a garage vehicle preserves parking records. Full local-data deletion is available separately.
- Version 1.0.0 (3) also built with development signing, installed and launched successfully on the paired physical iPhone.
- Bundled privacy, terms and support documents in Belarusian, Russian and English; public support address: sosambus@icloud.com.
- Original icon, signed Release archives and successful App Store Connect uploads. Current build 4 is processed and attached to the submitted version.
- 25 unit/integration tests and 2 UI tests passed. The separate screenshot test passed and exported 18 native simulator screenshots at 1320×2868.
- Screenshots use fictional vehicles; visual inspection and OCR checks passed. Six Russian and six English screenshots were uploaded to the 6.9-inch slots. Belarusian screenshots are retained here because App Store metadata does not offer Belarusian localization.
- Russian and English product metadata, review instructions, categories and 4+ age rating entered. Review credentials are private and are not stored in this repository.
- Non-trader DSA status saved and shown as Active. Manual release after approval selected.
- Free pricing configured for 175 countries/regions; availability shows Available on App Release. Mac and Vision Pro distribution were opted out.
- Localized privacy-policy and privacy-choices URLs are now saved for Russian and English. The documented App Store Connect API accepted both updates with HTTP 200; subsequent independent GET requests confirmed persistence. The existing account API key was used without creating or changing credentials.
- The latest source was rebuilt and launched in the iPhone simulator in normal interactive mode, without screenshot fixtures.

- The publisher reported successful real-payment and payment-page data-processing checks in the updated window, with web analytics and no advertising tracking.
- Version metadata in Russian and English now matches the checked-in descriptions, including explicit transmission of the selected plate and parking parameters. Both were saved and verified through the public API.
- Build 4 includes clarified bundled policies in all three languages; its signed archive was verified against the source documents. Apple processed it successfully, and its attachment to version 1.0.0 was confirmed by an independent API read. The simulator was updated to build 4.
- All 12 App Store screenshot reservations were finalized through the public API with matching MD5 checksums. Every asset is COMPLETE. Display order was separately saved and read back for both localizations.
- All nine App Privacy categories are configured. Empty duplicate name/email records left by timed-out saves were removed through the normal editor, enabling Publish.

## Submitted for review

The publisher explicitly approved Apple's final privacy-publication declaration and submission of 1.0.0 (4). The nine-category App Privacy questionnaire is published; the browser confirms publication by the account holder.

The version was added to its review submission and sent through the documented API. The final independent GET returned **WAITING_FOR_REVIEW** for submission `c9d7a5d4-7b0c-4fd7-83ab-316a8d8c1917` on 2026-09-22.

The app is awaiting Apple's review and is **not yet released on the App Store**. Release is manual after approval. Retain support for the publisher's third-party-content rights declaration if Apple requests it; no official operator partnership is claimed.

Privacy-label reference: https://developer.apple.com/app-store/app-privacy-details/ (including embedded web traffic and third-party collection).

## Resolved policy URL save failure

The web editor's `iris/v1/appInfoLocalizations` PATCH returned an Akamai HTTP 504. It reproduced for Russian and English, for the same public document served from GitHub and an independent CDN, and for an ordinary subtitle edit without any URL. Changing the policy document or hosting did not address the observed failure.

The supported `api.appstoreconnect.apple.com/v1/appInfoLocalizations/{id}` PATCH succeeded, followed by independent reads of both localizations. JWT `scope` supports GET requests; a scope containing PATCH returned HTTP 405. Mutation requests used a standard short-lived JWT with the existing key's permissions, with the local helper restricted to this app's two verified localization IDs. Credentials and tokens were not published or stored in the repository. Browser network diagnostics were disabled after use.

References: https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appinfolocalizations-_id_ and https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests

## Submission validation repairs

The first review-item validation identified uncommitted screenshot uploads and unpublished privacy responses. All screenshots were finalized with their original file checksums and reached COMPLETE; their display order was then saved through the supported API. The privacy editor had retained empty duplicate NAME and EMAIL_ADDRESS records after timed-out saves. Re-saving those categories through the editor removed only the empty duplicates and enabled publication. The final review submission succeeded after these repairs.
