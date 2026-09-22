# Release materials

Version: 1.0.0, build 3. Bundle: `by.stajanka.app`. Supported target: iPhone, iOS 17+.

This directory contains public-safe policies, branding, App Store metadata and simulator screenshots. No personal account, payment token or real user plate belongs here.

## Before review

- Validate the archive, privacy manifest and App Store privacy answers against actual native and embedded-web processing.
- Confirm current permission/terms for third-party Parkouka access. Do not claim an operator partnership or permission that has not been established.
- Provide truthful review access for optional external-account features; never include a personal password in this repository.
- Resolve App Store Connect trader status/availability and any required declarations.
- Verify a real payment through the current bank container on a physical device.
- Inspect all screenshots and scan for real plate numbers before publishing.

## Screenshots

The `StajankaScreenshots` scheme uses a separate simulator and Debug-only fictional data. Release builds exclude the screenshot scenario. Capture only `StajankaUITests/AppStoreScreenshots/testCaptureStoreScreens`; ordinary tests skip it. No payment is submitted by screenshot tests.

## Legal documents

Run `python3 scripts/build_legal_documents.py` to keep bundled and public versions consistent. Public privacy/support documents are hosted directly in this repository; no separate website or domain is required.
