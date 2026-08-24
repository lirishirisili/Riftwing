# Store declarations checklist — RIFTSTRIKE (`com.lishistudio.riftwing`)

## Done via API (this session)

### Google Play
- **Data safety** uploaded for ads (Device IDs, Approximate location, App interactions, Crash/Diagnostics) — collected/shared for Advertising / Fraud prevention / Analytics as applicable.
- CSV saved at `docs/store/play-data-safety-riftwing.csv`.

### App Store Connect
- Age rating **Advertising = true** (already set on live app).
- Privacy Policy URL already points to `https://sites.google.com/view/riftwing/home` (en-US + he).
- Live version is **READY_FOR_SALE**, so some metadata fields are locked until a new editable version exists.

## You must finish manually

### 1) Privacy Policy page (required before upload)
Edit Google Sites: https://sites.google.com/view/riftwing/home  
Replace the whole page with the text in `docs/store/PRIVACY_POLICY.md`  
**Key change:** AdMob → **Unity LevelPlay / Unity Ads / ironSource**; banners + interstitial + rewarded.

### 2) Google Play Console → Policy → App content
Package: `com.lishistudio.riftwing`

1. **Advertising ID** declaration  
   - Does your app use advertising ID? **Yes**  
   - Purposes: **Advertising** (and Analytics if shown)  
2. Confirm **Data safety** form shows the uploaded answers (ads data types).  
3. **Ads** declaration / Contains ads: **Yes** (if asked in store listing or content).  
4. Store listing privacy policy URL: `https://sites.google.com/view/riftwing/home`

### 3) App Store Connect → App Privacy (nutrition labels)
API Key **cannot** upload privacy nutrition labels (Apple requires Apple ID owner/admin UI).

Open the app → **App Privacy** → Declare that you or third-party partners collect data:

| Data type | Linked to user? | Used to track? | Purposes |
|-----------|-----------------|----------------|----------|
| Device ID | No / Not linked (typical for ads IDs unless you have accounts) | **Yes** if ATT/personalized ads | Third-Party Advertising |
| Advertising Data | No | Yes (if used for ads measurement/personalization) | Third-Party Advertising |
| Coarse Location | No | Optional / Yes if used for ads | Third-Party Advertising |
| Product Interaction / Usage Data | No | Optional | Third-Party Advertising / Analytics |
| Diagnostics / Crash | No | No | App Functionality |

Also keep **Advertising** checked in Age Rating (already true).

Privacy Policy URL: `https://sites.google.com/view/riftwing/home`

### 4) Upload binaries
- Android AAB: `build/android/riftwing-release.aab`
- iOS: build/upload via macOS / GitHub Actions after privacy page is updated

## Product naming note
Store display name is **RIFTSTRIKE**; package remains `com.lishistudio.riftwing`. The privacy page may keep “RIFTWING” as the legal/package name and mention Riftstrike as the store title (as in `PRIVACY_POLICY.md`).
