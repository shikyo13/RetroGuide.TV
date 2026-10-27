# Purchase attribution

First-party Apple Ads acquisition and StoreKit purchase measurement. StoreKit remains the sole authority for Pro access. The service does not grant, restore, or revoke entitlements in the app.

## Collection

The app generates a random identifier and secret in its Keychain. Purchases include the identifier as StoreKit's `appAccountToken`. Verified signed transactions enter a bounded local queue and are sent independently of the purchase and restore flows. Failed delivery retries with backoff and resumes on a subsequent launch or foreground activation.

On iPhone and iPad, Apple's AdServices token is exchanged on the server for acquisition information. Apple TV purchases can match an earlier acquisition when Apple supplies the same signed app transaction identity and there is a single eligible campaign. Missing or ambiguous matches remain unattributed. No device fingerprinting or media library information is used.

The service verifies app transactions, purchase transactions, and App Store Server Notifications using Apple's App Store Server Library and trusted Apple root certificates. Production and Sandbox require separate deployments and databases. Xcode's locally signed StoreKit test purchases are not accepted by the production verifier.

## Run

Use Python 3.13 and install `requirements.txt` (`requirements-dev.txt` for tests). Obtain the Apple root certificates from [Apple PKI](https://www.apple.com/certificateauthority/) and store the DER `.cer` files in a protected directory outside this repository.

Set `ATTRIBUTION_DATABASE` to a persistent SQLite path, `APPLE_ROOT_CERTIFICATES` to that certificate directory, and `STORE_ENVIRONMENT` to `Production` or `Sandbox`. The bundle, app, product, and advertising organization identifiers are in `attribution/config.py`.

```sh
uvicorn attribution.api:create_app --factory --host 127.0.0.1 --port 8084 --no-access-log --limit-concurrency 32
```

Alternatively, use `docker compose up --build -d`. The container binds to loopback only. Publish through a trusted HTTPS reverse proxy with a 96 KiB request limit and request rate limiting. Do not log authorization headers or request bodies. Keep the SQLite volume and backups private. Reports and advertising credentials are available only to local administration, never through the public ingestion API.

Configure App Store Server Notifications V2 to POST to `/v1/notifications/apple` for refund updates. Both the outer notification and its nested transaction are verified. Repeated notifications and restores are idempotent. An older transaction cannot undo a newer refund.

Configure the app's `RetroGuideAttributionURL` Info.plist value with the HTTPS service base URL. With no value, collection is disabled and purchases have no measurement token. Before enabling collection in a distributed app, publish the corresponding privacy policy and App Store privacy disclosures for purchase history, the random identifier, and advertising attribution data.

## Reports

```sh
python -m attribution.cli revenue --start 2026-10-01 --end 2026-10-31
python -m attribution.cli sync-ads --campaign 123456 --start 2026-10-01 --end 2026-10-31
```

Dates are inclusive UTC calendar dates. Revenue is selected by purchase date, with the latest verified refund status. Amounts are transaction prices in their original currency, before Apple's commission and tax adjustments. Different currencies remain separate. Unknown prices are reported explicitly. Family Sharing does not count as another sale.

Ad reports use Apple's Platform API, paginate all results, retry temporary failures within a fixed limit, and replace daily snapshots atomically. Re-running a range does not double count spend. `APPLE_ADS_ACCOUNT_ID` selects the ad account. `APPLE_ADS_ACCESS_TOKEN_FILE` points to a mode-600 file containing a valid access token issued for the registered OAuth client. The reporting client accepts a token provider so credential renewal can run separately from ingestion.

[Apple's authorization documentation](https://ads.apple.com/maps/apple-ads/help/campaigns/0022-use-apple-ads-platform-api) describes registration for service-provider OAuth clients. The report reader does not create an OAuth registration or change account roles. A token issuer must renew access for unattended reporting.

Campaign and keyword totals are separate reporting levels and must not be added together. A missing keyword ID stays unknown rather than being assigned to a guessed search term. An unattributed purchase is not necessarily organic. Sales in a date range can come from ads served earlier, so period sales divided by period spend is not acquisition-cohort ROAS or profit.

## Verification

```sh
python -m pytest tests
```

The tests cover signature rejection at the ingestion boundary, authorization, body limits, attribution outages, deduplication, refund ordering, cross-device identity matching, reporting pagination, atomic refreshes, and throttling. The Swift `PurchaseOutboxTests` cover failed delivery, persistence, bounded storage, and updates arriving during delivery.
