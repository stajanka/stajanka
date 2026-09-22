# Release status — 2026-09-22

App: Stajanka / Стаянка, `by.stajanka.app`, version 1.0.0 (3).
App Store Connect record: `6814781315`.

## Completed

- Public source and legal documents published at https://github.com/stajanka/stajanka under the stajanka organization.
- Visible garage deletion with confirmation; deleting a garage vehicle preserves parking records. Full local-data deletion is available separately.
- Bundled privacy, terms and support documents in Belarusian, Russian and English; public support address: sosambus@icloud.com.
- Original icon, signed Release archive and successful App Store Connect upload. Apple processed build 3; it was selected for the version.
- 25 unit/integration tests and 2 UI tests passed. The separate screenshot test passed and exported 18 native simulator screenshots at 1320×2868.
- Screenshots use fictional vehicles; visual inspection and OCR checks passed. Six Russian and six English screenshots were uploaded to the 6.9-inch slots. Belarusian screenshots are retained here because App Store metadata does not offer Belarusian localization.
- Russian and English product metadata, review instructions, categories and 4+ age rating entered. Review credentials are private and are not stored in this repository.
- Non-trader DSA status saved and shown as Active. Manual release after approval selected.
- Free pricing configured for 175 countries/regions; availability shows Available on App Release. Mac and Vision Pro distribution were opted out.

## Still required before submission

- Finish and publish App Privacy answers. Six known data types are saved as a draft: name, email, payment information, user ID, purchases and other data (including vehicle/parking information). These are not a completed or published privacy label. Confirm the analytics/tracking behavior of embedded provider pages before finalizing purposes and tracking declarations.
- Save localized privacy-policy URLs in App Store Connect. The public documents are reachable, but the editor returned an error after multiple save attempts, including with a direct raw-document URL.
- Verify persistence of the selected build and the last metadata edits after App Store Connect recovers. Arrange screenshot order so map, zone and payment are the first three images.
- Exercise an actual card/3-D Secure payment through the current WKWebView container on a physical device. Previous real payments and current native callback fixtures passed, but the current container has not completed that final live-device check.
- Establish any necessary third-party service rights; do not infer an official partnership or permission from public accessibility alone.

The app has **not been submitted for review or released**. Upload success does not mean App Review approval.

Privacy-label reference: https://developer.apple.com/app-store/app-privacy-details/ (including embedded web traffic and third-party collection).
