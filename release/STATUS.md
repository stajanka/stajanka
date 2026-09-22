# Release status — 2026-09-22

App: Stajanka / Стаянка, `by.stajanka.app`, version 1.0.0 (4).
App Store Connect record: `6814781315`.

## Completed

- Public source and legal documents published at https://github.com/stajanka/stajanka under the stajanka organization.
- Visible garage deletion with confirmation; deleting a garage vehicle preserves parking records. Full local-data deletion is available separately.
- Version 1.0.0 (3) also built with development signing, installed and launched successfully on the paired physical iPhone.
- Bundled privacy, terms and support documents in Belarusian, Russian and English; public support address: sosambus@icloud.com.
- Original icon, signed Release archive and successful App Store Connect upload. Apple processed build 3; its attachment to the version was verified after reloading the page.
- 25 unit/integration tests and 2 UI tests passed. The separate screenshot test passed and exported 18 native simulator screenshots at 1320×2868.
- Screenshots use fictional vehicles; visual inspection and OCR checks passed. Six Russian and six English screenshots were uploaded to the 6.9-inch slots. Belarusian screenshots are retained here because App Store metadata does not offer Belarusian localization.
- Russian and English product metadata, review instructions, categories and 4+ age rating entered. Review credentials are private and are not stored in this repository.
- Non-trader DSA status saved and shown as Active. Manual release after approval selected.
- Free pricing configured for 175 countries/regions; availability shows Available on App Release. Mac and Vision Pro distribution were opted out.
- Localized privacy-policy and privacy-choices URLs are now saved for Russian and English. The documented App Store Connect API accepted both updates with HTTP 200; subsequent independent GET requests confirmed persistence. The existing account API key was used without creating or changing credentials.
- The latest source was rebuilt and launched in the iPhone simulator in normal interactive mode, without screenshot fixtures.

- The publisher reported successful real-payment and payment-page data-processing checks in the updated window, with web analytics and no advertising tracking.
- Version metadata in Russian and English now matches the checked-in descriptions, including explicit transmission of the selected plate and parking parameters. Both were saved and verified through the public API.
- Build 4 includes clarified bundled policies in all three languages; its signed archive was verified against the source documents.

## Still required before submission

- Finish and publish the nine-category App Privacy questionnaire described in privacy-review.md.


- Establish any necessary third-party service rights; do not infer an official partnership or permission from public accessibility alone.

The app has **not been submitted for review or released**. Upload success does not mean App Review approval.

Privacy-label reference: https://developer.apple.com/app-store/app-privacy-details/ (including embedded web traffic and third-party collection).

## Resolved policy URL save failure

The web editor's `iris/v1/appInfoLocalizations` PATCH returned an Akamai HTTP 504. It reproduced for Russian and English, for the same public document served from GitHub and an independent CDN, and for an ordinary subtitle edit without any URL. Changing the policy document or hosting did not address the observed failure.

The supported `api.appstoreconnect.apple.com/v1/appInfoLocalizations/{id}` PATCH succeeded, followed by independent reads of both localizations. JWT `scope` supports GET requests; a scope containing PATCH returned HTTP 405. Mutation requests used a standard short-lived JWT with the existing key's permissions, with the local helper restricted to this app's two verified localization IDs. Credentials and tokens were not published or stored in the repository. Browser network diagnostics were disabled after use.

References: https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appinfolocalizations-_id_ and https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
