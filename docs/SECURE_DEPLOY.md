# Secure Deploy Checklist — VedAstro AI

After the security overhaul, follow these steps in order before launching to Play Store.

---

## 1. Set Cloud Function Secrets (one-time)

In your local `vedastro-ai` folder:

```bash
firebase functions:config:set ^
  gemini.key="AIza-YOUR-GEMINI-KEY" ^
  razorpay.key_id="rzp_live_YOUR_KEY" ^
  razorpay.key_secret="YOUR_SECRET" ^
  razorpay.webhook_secret="YOUR_WEBHOOK_SECRET" ^
  admin.emails="your@email.com,cofounder@email.com"
```

Verify:
```bash
firebase functions:config:get
```

---

## 2. Generate Knowledge Base (one-time, before each deploy if texts change)

The knowledge base file is gitignored (too large). You generate it locally:

```bash
cd functions
node ../scripts/extract_knowledge_base.js
node ../scripts/generate_embeddings.js
# This produces functions/knowledge_base.json (~50-200 MB)
```

Confirm the file exists:
```bash
ls -lh functions/knowledge_base.json
```

If missing, all `/chat` and `/horoscope` calls will return 503.

---

## 3. Deploy Cloud Functions

```bash
firebase deploy --only functions
```

This deploys:
- `chat` — auth-gated, rate-limited, RAG-backed
- `horoscope` — server-cached per (sign × period × date)
- `palmAnalyze` — server-side Gemini Vision (replaces client-direct)
- `subscriptionCreate` / `subscriptionCancel` — auth-gated
- `razorpayWebhook` — raw-body signature verified
- `search` — auth-gated debug endpoint

Wait for "✓ Deploy complete!"

---

## 4. Deploy Firestore Rules

```bash
firebase deploy --only firestore:rules
```

This locks down `usage/*` and `subscriptions/*` so clients can no longer self-promote to premium.

---

## 5. Configure Firestore TTL (one-time)

In Firebase Console → Firestore → TTL Policies, add:

| Collection | Field | What it cleans up |
|---|---|---|
| `rate_limits` | `expiresAt` | Daily counters older than 48h |
| `horoscope_cache` | `expiresAt` | Stale horoscopes after period ends |

This auto-deletes old documents to keep Firestore costs flat.

**Link:** https://console.firebase.google.com/project/vedastro-ai/firestore/ttl

---

## 6. Configure Razorpay Webhook

**Link:** https://dashboard.razorpay.com/app/webhooks

Add webhook:
- URL: `https://us-central1-vedastro-ai.cloudfunctions.net/razorpayWebhook`
- Active events:
  - `subscription.activated`
  - `subscription.charged`
  - `subscription.cancelled`
  - `subscription.completed`
  - `subscription.halted`
  - `payment.failed`
- Secret: same as `razorpay.webhook_secret` in functions config

---

## 7. Test End-to-End

### Chat
- Sign up → ask a question → confirm answer comes back with sources
- Check Cloud Functions logs: `firebase functions:log --only chat`

### Horoscope
- View daily horoscope → check `horoscope_cache` collection in Firestore
- View again immediately → should return faster (cached: true)

### Subscription (use Razorpay test mode first!)
- Switch app to test Razorpay key
- Tap "Start Free Trial" → should see ₹0 today, mandate registered
- Razorpay test mode: charge happens after test interval

### Account Deletion
- Settings → Delete Account → confirm
- Verify: Firebase Auth user deleted, Firestore data cleared, subscription cancelled

---

## 8. Smoke-test Rate Limits

```bash
# Free tier: 5 chats/day. The 6th should return 429.
for i in {1..6}; do
  curl -X POST https://us-central1-vedastro-ai.cloudfunctions.net/chat \
    -H "Authorization: Bearer YOUR_TEST_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"question":"test"}'
done
```

---

## 9. Set Budget Alerts (CRITICAL)

**Link:** https://console.cloud.google.com/billing/budgets

Create budget:
- Amount: ₹1,000/month for first 2 weeks (then increase)
- Alert at 50%, 75%, 90%, 100%
- Email to founder + cofounder

---

## 10. Verify Build Pipeline

Push any commit → check the GitHub Actions run produces:
- `VedAstro-AI-release-aab` — signed AAB (upload to Play Store)
- `VedAstro-AI-release-apk` — for sideload testing
- `VedAstro-AI-debug-symbols` — upload to Crashlytics for de-obfuscation

---

## 11. Internal Testing (mandatory for Play Store)

1. Play Console → Internal Testing → New Release
2. Upload the AAB
3. Add 12+ testers (Google Play requires this for new accounts)
4. Test for at least 14 days
5. Then promote to Closed → Open → Production

---

## Common Issues

| Symptom | Fix |
|---|---|
| 401 from /chat | User not logged in — Firebase Auth token missing |
| 429 from /chat | User hit daily limit — upgrade or wait |
| 503 from /chat | knowledge_base.json missing in deploy |
| Webhook signature invalid | Webhook secret in Razorpay ≠ functions config |
| App crash on release only | Check ProGuard logs in Play Console |
| Crashlytics shows unreadable stack | Upload debug symbols artifact |

---

## What Changed (Audit Trail)

| Before | After |
|---|---|
| Anyone could call `/chat` | Auth required |
| Anyone could spam unlimited | Rate-limited per UID per day |
| Horoscopes regenerated every call | Server cache per (sign × period × date) |
| `usage/*` writable by clients | Server-only writes (admin SDK) |
| Webhook used parsed body | Raw body HMAC + timing-safe compare |
| Palm parser crashed on null | Defensive null checks |
| `INTERNET` permission missing | Added |
| R8 disabled | Enabled with `--obfuscate` |
| Gemini key in APK | Still in APK as fallback (TODO: remove fallback path) |
