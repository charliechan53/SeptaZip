# SeptaZip Mac App Store Readiness

Date: 2026-03-15

This note summarizes the current gap between the local build and a Mac App Store release.

## What Apple requires in practice

Reference links:
- Apple Developer Program overview: https://developer.apple.com/programs/
- App Sandbox for macOS apps: https://developer.apple.com/documentation/security/app-sandbox
- App Store Connect pricing: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
- Submit an app for review: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

Key points:
- You need an Apple Developer Program membership to ship on the Mac App Store.
- Mac App Store apps must be appropriately sandboxed and delivered as self-contained app bundles.
- A free app is supported by setting the app price to a free tier in App Store Connect.
- The app must be signed for App Store distribution and submitted through App Store Connect for review.

## SeptaZip status today

Ready:
- Native macOS app build
- Finder Sync extension target
- Bundled `7zz` engine
- DMG packaging for direct distribution

Not ready for App Store submission:
- App Sandbox is not enabled for the app or the extension.
- File-access behavior has not been validated under sandbox restrictions.
- Signing is local ad-hoc signing, not App Store distribution signing.
- Password handling through command-line arguments should be treated as a security review item before submission.

## Recommended path

1. Join or use an existing Apple Developer Program team account.
2. Turn on App Sandbox for the app and extension, then rework any flows that fail under sandbox rules.
3. Build with App Store distribution signing from Xcode.
4. Create the app record in App Store Connect and set pricing to free.
5. Upload the archive, complete metadata, and submit for App Review.

## Recommendation for this repo

Direct distribution is already workable with DMG packaging.

Mac App Store distribution is possible, but it should be treated as a separate hardening milestone, not just a publishing checkbox.
