# Purpose Money

**Money for home, spent the way your family agreed.**

Siblings abroad pool money into one **family pot** for their parents. The pot is a **Sputnik DAO on NEAR**, locked to purposes (food, rent, school fees). Parents pay shops they already use; the shop receives a normal **naira bank transfer through Paystack**. An **AI guardian** checks every payment against the family's rules before any money moves, and anything unusual goes to the siblings for a vote.

One Flutter app runs on **Android, iOS and the web**.

---

## How it fits together

```
 Flutter app (Android · iOS · Web)
   │  reads live data ───────────────► Firebase Firestore (free Spark plan)
   │  sign-in ───────────────────────► Firebase Auth (email + password)
   │  every write / money action ───► Cloudflare Worker (free plan)
                                          │
                ┌─────────────────────────┼──────────────────────────────┐
                ▼                         ▼                              ▼
     NEAR testnet (Sputnik DAO)     Paystack (test mode)        NEAR Intents 1Click API
     • one DAO per family           • bank list                  • cross-chain funding quotes
     • guardian role: may only      • verify account name        • deposit address + status
       approve/reject transfers     • transfer recipients
     • transfer proposals + votes   • naira transfers + webhook
```

### Why the Worker?
Firebase's free Spark plan can't run Cloud Functions that call outside APIs, and the Paystack secret key and NEAR keys must never ship inside an app. The Worker holds them, verifies each user's Firebase ID token, and writes to Firestore with a service account. The app can only **read** family data; Firestore rules block every client write except a user's own display name.

### A payment, step by step
1. A parent picks an approved shop and an amount. The app calls `POST /api/payments`.
2. The **guardian rule engine** (`worker/src/guardian.ts`) runs 11 checks:
   - **Blocks:** pot not live, shop not approved, purpose missing, purpose budget exceeded, pot balance too low.
   - **Asks the siblings:** above the auto-approve limit, over the per-shop daily cap, too many payments today, shop still in its cooling-off period, bank name doesn't match the shop name, amount far above this shop's usual.
3. **Approved:** the operator account adds a `Transfer` proposal to the family DAO, and the guardian votes `VoteApprove` using a **function-call key that can only call `act_proposal` on that one DAO**. The DAO releases the NEAR to the settlement treasury, and Paystack sends naira to the shop.
4. **Escalated:** siblings vote in the app. When enough approve, the family council (relayed by the operator on testnet) approves the proposal on-chain and the payout runs.
5. **Blocked:** nothing moves. The receipt shows exactly which rule failed.

Every receipt links to the proposal and approval transactions on NearBlocks.

### Honest notes on this build
- **NEAR runs on testnet.** The pot holds test NEAR, and naira values use a fixed `NGN_PER_USD` rate plus the live NEAR price from 1Click (fallback `NEAR_USD_FALLBACK`).
- **Paystack runs in test mode.** Account verification returns Paystack's test data, and test transfers always report success; no real naira moves. Switching to live keys needs a verified Paystack business account with transfers enabled and a funded balance.
- **NEAR Intents is mainnet-only.** With a 1Click API key, siblings get a real cross-chain quote and deposit address. When 1Click reports `SUCCESS`, the Worker credits the family pot by sending the equivalent test NEAR to the DAO (a "testnet mirror"). Without a key, use the **testnet top-up** button.
- **Sibling votes are collected in the app** and relayed on-chain by the operator, which is the DAO's council. With wallet sign-in, siblings could vote on-chain directly.
- **The AI note is optional.** Rules decide; an OpenAI-compatible model (for example NEAR AI Cloud) only writes a one-line explanation when `AI_*` settings are present.

---

## Folder layout

```
purpose-money/
├── lib/        Flutter app (all Dart code)
├── worker/     Cloudflare Worker (TypeScript) + tests
└── firebase/   Firestore rules, indexes, hosting config
```

---

## Setup

You need: **Flutter 3.35+**, **Node 20+**, a **Firebase** project, a free **Cloudflare** account, a **Paystack** account (test keys are fine), and two **NEAR testnet** accounts.

### 1. Firebase (free Spark plan)
1. Create a project at <https://console.firebase.google.com>.
2. **Authentication → Sign-in method →** enable **Email/Password**.
3. **Firestore Database →** create it (production mode, any region).
4. Deploy the security rules:
   ```bash
   cd firebase
   npx firebase-tools login
   npx firebase-tools use --add          # pick your project
   npx firebase-tools deploy --only firestore:rules
   ```
5. **Project settings → Service accounts → Generate new private key.** Save the JSON as `service-account.json` (outside the repo or git-ignored). The Worker uses it.

### 2. NEAR testnet accounts
Create two accounts: an **operator** (creates DAOs, proposes payments, holds the settlement treasury) and a **guardian** (only approves). They must be different accounts. For example, with near-cli-rs:

```bash
npx near-cli-rs account create-account sponsor-by-faucet-service pm-operator-yourname.testnet autogenerate-new-keypair save-to-legacy-keychain network-config testnet create
npx near-cli-rs account create-account sponsor-by-faucet-service pm-guardian-yourname.testnet autogenerate-new-keypair save-to-legacy-keychain network-config testnet create
```

The private keys are saved in `~/.near-credentials/testnet/<account>.json` (`private_key` field, starting with `ed25519:`). You can also create accounts in the MyNearWallet testnet site and export the keys.

**Funding:** each new family DAO costs `DAO_CREATE_DEPOSIT_NEAR` (6 test NEAR by default) from the operator, and test top-ups also come from the operator. Send the operator extra test NEAR from a faucet if needed. The guardian only needs about 1 NEAR, because each family gets a 0.5 NEAR gas allowance on its guardian key.

### 3. Paystack
1. Use your **test secret key** (`sk_test_…`) from **Settings → API Keys & Webhooks**.
2. Turn off **"Confirm transfers before sending"** (Transfer approvals) so automated transfers don't wait for an OTP.
3. Set the webhook URL to `https://<your-worker>/webhooks/paystack` once the Worker is deployed.

### 4. NEAR Intents (optional)
To enable cross-chain funding, get a 1Click API key from the NEAR Intents partner portal (see <https://docs.near-intents.org>). You'll set:
- `ONECLICK_API_KEY`: the key.
- `INTENTS_RECIPIENT`: a **mainnet** NEAR account you control, which receives the USDC.

### 5. Cloudflare Worker
```bash
cd worker
npm install
npm test                      # 27 tests: NEAR tx encoding vs near-api-js, guardian rules, full flow
npx wrangler login

npx wrangler secret put FIREBASE_SERVICE_ACCOUNT < /path/to/service-account.json
npx wrangler secret put PAYSTACK_SECRET_KEY
npx wrangler secret put OPERATOR_ACCOUNT_ID
npx wrangler secret put OPERATOR_PRIVATE_KEY
npx wrangler secret put GUARDIAN_ACCOUNT_ID
npx wrangler secret put GUARDIAN_PRIVATE_KEY
# optional
npx wrangler secret put ONECLICK_API_KEY
npx wrangler secret put INTENTS_RECIPIENT

npm run deploy
```
Open `https://purpose-money-api.<your-subdomain>.workers.dev/api/health` to check every setting shows up. Non-secret settings (rate, deposits, RPC URL) are in `wrangler.toml`.

For local development, copy `.dev.vars.example` to `.dev.vars`, fill it in, and run `npm run dev`.

### 6. Flutter app
```bash
cd app
flutter create . --platforms=android,ios,web --project-name purpose_money   # adds platform folders, keeps lib/
dart pub global activate flutterfire_cli
flutterfire configure            # pick your Firebase project + Android, iOS, Web; replaces lib/firebase_options.dart
flutter pub get

# Web
flutter run -d chrome --dart-define=API_URL=https://purpose-money-api.<your-subdomain>.workers.dev
# Android / iOS
flutter run --dart-define=API_URL=https://purpose-money-api.<your-subdomain>.workers.dev
```
Platform notes:
- **Android:** if the build asks for a higher `minSdk`, set `minSdk = 23` in `android/app/build.gradle(.kts)`. For release builds, add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml`.
- **iOS:** if CocoaPods complains about the deployment target, set `platform :ios, '15.0'` in `ios/Podfile`, then run `pod install` in `ios/`.

**Host the web app free** on Firebase Hosting:
```bash
flutter build web --dart-define=API_URL=https://purpose-money-api.<your-subdomain>.workers.dev
cd ../firebase && npx firebase-tools deploy --only hosting
```

## API (Worker)
All routes need `Authorization: Bearer <Firebase ID token>`, except `/api/health` and the Paystack webhook.

| Route | Who | What |
|---|---|---|
| `GET /api/banks` | any | Paystack bank list |
| `POST /api/families` | user | Create family + DAO |
| `POST /api/families/join` | user | Join with invite code as sibling or parent |
| `POST /api/families/leave` | member | Leave the family |
| `POST /api/families/retry-dao` | sibling | Retry DAO setup |
| `POST /api/families/chain` | member | DAO balance, roles, proposals |
| `POST /api/merchants/resolve` | member | Verify account name |
| `POST /api/merchants` | member | Add shop (verifies + creates Paystack recipient) |
| `POST /api/merchants/vote` | sibling | Approve or decline a shop |
| `POST /api/payments` | member | Request payment → guardian decision |
| `POST /api/payments/vote` | sibling | Vote on an escalated payment |
| `POST /api/payments/retry-payout` | sibling | Retry a failed bank payout |
| `POST /api/changes` / `vote` | sibling | Budgets, rules, new month |
| `GET /api/fund/tokens` | member | Funding options |
| `POST /api/fund/quote` / `status` | sibling | NEAR Intents deposit + tracking |
| `POST /api/fund/testnet` | sibling | Testnet top-up |
| `POST /webhooks/paystack` | Paystack | Signed transfer events |

## Security summary
- Secrets live only in the Worker. The app ships no keys besides Firebase's public config.
- Firestore rules: members can read their family; clients can't write family data. Guardian keys sit in a `_secrets` collection that no client can read.
- On-chain: the guardian role may only `VoteApprove`/`VoteReject` transfers, and its per-family key can only call `act_proposal` on that DAO, with a capped gas allowance.
- Paystack webhooks are verified with HMAC-SHA512. Transfer references are idempotent, so retries never double-pay.
