# Play Store Launch Pack — VedAstro AI

Everything you need to fill out the Play Console. Copy/paste from here.

---

## 1. Data Safety Form

### Data collected
| Type | Collected | Shared | Required | Why |
|---|---|---|---|---|
| Name | Yes | No | Optional | Personalized horoscope greeting |
| Email | Yes | No | Required | Account login + receipts |
| Phone (optional) | Yes | No | Optional | Phone-based login |
| User ID | Yes | No | Required | Account identification |
| Date of birth | Yes | No | Required | Astrological calculations |
| Time of birth | Yes | No | Optional | Accurate Kundli generation |
| Place of birth | Yes | No | Required | Astrological calculations |
| Photos (palm reading) | Yes | No | Optional | AI palm analysis |
| Chat messages | Yes | No | Required | Conversation history |
| Crash logs | Yes | No | Required | App stability |
| Device or other IDs | No | — | — | — |
| Precise location | No | — | — | — |
| Contacts | No | — | — | — |
| Financial info | No | — | — | Razorpay handles this directly |

### Security practices (check all that apply)
- [x] Data is encrypted in transit (HTTPS)
- [x] Users can request data deletion (in-app delete account)
- [x] Independent security review: NO (mark NO unless you've done one)

### Data sharing
- **Do you share data with third parties?** YES (specify):
  - Firebase (Google) — for authentication, database, cloud functions
  - Razorpay — for payment processing only
  - Google Generative AI (Gemini) — for AI responses (queries are not used to train models per Gemini's API terms)

---

## 2. Content Rating Answers (IARC questionnaire)

Pick "Utility, Productivity, Communication, or Other" → All answers below should be **NO**:

| Question | Answer |
|---|---|
| Does the app contain violence? | NO |
| Does the app contain sexual content or nudity? | NO |
| Does the app contain profanity or crude humor? | NO |
| Does the app contain controlled substances (drugs, alcohol, tobacco)? | NO |
| Does the app contain gambling or simulated gambling? | NO |
| Does the app encourage user-generated content sharing? | NO |
| Does the app share user location with other users? | NO |
| Does the app allow purchases of digital content? | YES (subscription plans) |
| Does the app share personal info with other users? | NO |

**Expected rating:** Everyone (3+)

---

## 3. Play Store Listing Copy

### App Name (max 30 chars)
```
VedAstro AI: Vedic Astrology
```

### Short Description (max 80 chars)
```
Authentic Vedic astrology, palm reading & daily horoscope. Powered by AI.
```

### Full Description (max 4000 chars)

```
Discover your destiny with VedAstro AI — the only Vedic astrology app powered by classical texts (Brihat Parashara Hora Shastra & Phaladeepika).

🔮 WHAT MAKES US DIFFERENT
Most astrology apps give vague predictions. VedAstro AI cites the exact verse and chapter from sacred texts behind every reading. No black box — just authentic Vedic wisdom delivered through cutting-edge AI.

✨ FEATURES

🪔 AI Astrology Chat
Ask anything about career, love, health, finance, family, or your future. Get personalized answers based on your exact birth chart, current planetary transits, and active dasha period — all backed by classical Vedic texts.

🤚 AI Palm Reading
Upload a photo of your palm and receive a detailed Samudrik Shastra analysis — heart line, head line, life line, and what they reveal about your personality and life path.

📅 Daily / Weekly / Monthly Horoscope
Personalized horoscopes for your Moon sign covering Career, Love, Health, and Finance. Includes lucky color and lucky number for each period.

🌟 Vedic Birth Chart (Kundli)
View your complete North Indian style Kundli with all 9 planets, 12 houses, ascendant, and active Vimshottari Dasha period. Calculated using precise astronomical data.

📿 Authentic Knowledge Base
Every reading references:
• Brihat Parashara Hora Shastra (BPHS) — the foundational Vedic astrology text
• Phaladeepika by Mantreshwar — predictive astrology masterwork
• Brighu Sanhita — remedial measures and karmic patterns
• Samudrik Shastra — for palm reading

🪔 Personalized Remedies (Upay)
Every reading ends with a practical Vedic remedy — specific mantras, gemstones, charity (daan), or rituals tailored to your chart.

🔮 SUBSCRIPTION PLANS

• Free: 2 chats + 1 palm reading + daily horoscope
• 7-Day Free Trial: 10 chats + 2 palm readings, then ₹99/month
• Standard: ₹199/month — 30 chats, 5 palm readings, family profiles
• Premium: ₹499/month — Unlimited everything + detailed predictions

Subscriptions auto-renew. Cancel anytime in Settings.

🔒 PRIVACY FIRST
• Your birth details are encrypted in transit
• Chat history is private to you
• You can delete your account and all data anytime
• We never share your data with advertisers

🇮🇳 MADE IN INDIA
Built with love by Indian developers, rooted in 5000-year-old Vedic wisdom.

📜 DISCLAIMER
VedAstro AI is for guidance and entertainment. For serious health, legal, or financial decisions, please consult qualified professionals.
```

### Keywords / Tags (Play Console doesn't have them, but useful for ASO)
```
vedic astrology, kundli, horoscope, palm reading, jyotish, panchang,
astrology hindi, daily horoscope, birth chart, samudrik shastra,
brihat parashara, phaladeepika, vedastro, ai astrologer, palm reader
```

### Category
**Lifestyle** (primary) → consider **Personalization** as secondary

### Tags (Play Console)
- Astrology
- Personalization
- AI
- Lifestyle

### Contact details
- Email: [your support email]
- Website: [your website or GitHub Pages URL]
- Privacy Policy: [hosted URL — see #13]

---

## 4. Screenshots Needed

You need to upload these. Sizes:
- **Phone:** 9 screenshots, 1080 × 1920 px (portrait)
- **7" tablet:** 1-8 screenshots (optional)
- **10" tablet:** 1-8 screenshots (optional)

### Recommended screenshot order:
1. Home screen (the new 2x2 grid with magenta gradient)
2. Chat screen showing a personalized response
3. Palm reading result
4. Kundli chart
5. Daily horoscope
6. Weekly horoscope
7. Monthly horoscope
8. Subscription/paywall screen
9. Settings

### Capture tip
Use your test device to record screen → extract frames at 1080×1920.
Or use the Flutter web preview, resize browser to 360×640, screenshot, upscale.

---

## 5. Feature Graphic
- **1024 × 500 px PNG**
- Should show: app name, key visual (palm/zodiac/stars), CTA tagline
- Suggested tagline: *"Your Personal Vedic Astrologer"*

---

## 6. App Icon
- **512 × 512 px PNG (32-bit, with alpha)**
- Already configured in `flutter_launcher_icons` (pubspec.yaml)
- Source: `assets/icon/app_icon.png` (must be 1024×1024 source)

---

## 7. Pricing & Distribution
- **Free** with in-app purchases
- Available countries: **India** (start there for compliance simplicity)
- Then expand to: US, UK, Canada, Australia, UAE, Singapore (Indian diaspora)

---

## 8. Required Declarations

### Government App
- NO

### News
- NO

### Public health emergency
- NO

### COVID-19
- NO

### Financial features
- **YES** — Subscriptions (in-app)
- **NOT** a financial product

### Ads
- **NO ads** (or YES if you decide to add AdMob later — declare upfront)

### App access
- **All functionality is available without restrictions** (or "Some functionality is restricted" if you keep a paywall)

---

## 9. Pre-launch Checklist

- [ ] App icon configured (1024×1024 source)
- [ ] Splash screen configured
- [ ] All screens tested on real device
- [ ] Crash-free for 24 hours of use
- [ ] Subscription test flow works (Razorpay test mode)
- [ ] Account deletion works end-to-end
- [ ] Privacy policy hosted at public URL
- [ ] Terms of service hosted at public URL
- [ ] Signing keystore generated + stored securely
- [ ] GitHub secrets configured for release builds
- [ ] Internal testing track set up in Play Console
- [ ] At least 12 testers added for closed testing (Play Console requirement)
- [ ] 14-day testing period completed (for new accounts)

---

## 10. After Submission

- **First review:** typically 7 days (can be up to 14)
- Check email daily for Play Console messages
- If rejected, fix issues and resubmit (no penalty)
- Once approved, app goes live in ~2 hours

---

Generated for: VedAstro AI
Updated: April 2026
