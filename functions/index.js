// VedAstro AI — Cloud Functions
// All endpoints require Firebase Auth (verified via ID token).
// Rate-limited per UID. Horoscope responses cached server-side per (sign, period, date).

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const cors = require('cors')({ origin: true });
const Razorpay = require('razorpay');
const crypto = require('crypto');

admin.initializeApp();

// ════════════════════════════════════════════════════════════════════
//   CONFIG
// ════════════════════════════════════════════════════════════════════

const PLAN_IDS = {
  trial:    'plan_trial_99',
  standard: 'plan_standard_199',
  premium:  'plan_premium_499',
};

// Per-day rate limits per UID (rolling 24h window)
const RATE_LIMITS = {
  free:     { chat: 5,   palm: 1,  horoscope: 30 },
  trial:    { chat: 50,  palm: 5,  horoscope: 60 },
  standard: { chat: 100, palm: 15, horoscope: 100 },
  premium:  { chat: 500, palm: 50, horoscope: 500 },
};

// Hard caps to prevent prompt-injection cost attacks
const MAX_QUESTION_LEN = 500;     // chars
const MAX_HISTORY_MSGS = 10;
const MAX_PALM_BYTES = 5 * 1024 * 1024;  // 5 MB

function isAdminEmail(email) {
  if (!email) return false;
  const cfg = (functions.config().admin && functions.config().admin.emails) ||
              process.env.ADMIN_EMAILS || '';
  const list = cfg.split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  return list.includes(email.toLowerCase());
}

function getRazorpay() {
  const cfg = functions.config().razorpay || {};
  const keyId = cfg.key_id || process.env.RAZORPAY_KEY_ID;
  const keySecret = cfg.key_secret || process.env.RAZORPAY_KEY_SECRET;
  if (!keyId || !keySecret) throw new Error('Razorpay credentials not configured');
  return new Razorpay({ key_id: keyId, key_secret: keySecret });
}

function getGenAI() {
  const apiKey = (functions.config().gemini && functions.config().gemini.key) ||
                 process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY not configured');
  return new GoogleGenerativeAI(apiKey);
}

// ════════════════════════════════════════════════════════════════════
//   AUTH MIDDLEWARE — every endpoint must verify Firebase ID token
// ════════════════════════════════════════════════════════════════════

/**
 * Verifies Authorization: Bearer <Firebase ID token>.
 * Returns { uid, email, plan } on success.
 * Sends 401 and returns null on failure.
 */
async function verifyAuth(req, res) {
  const authHeader = req.headers.authorization || '';
  const match = authHeader.match(/^Bearer\s+(.+)$/);
  if (!match) {
    res.status(401).json({ error: 'Missing or invalid Authorization header' });
    return null;
  }
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    // Look up user's plan from usage/{uid}
    let plan = 'free';
    try {
      const usageDoc = await admin.firestore().doc(`usage/${decoded.uid}`).get();
      if (usageDoc.exists && usageDoc.data().plan) plan = usageDoc.data().plan;
    } catch (_) {}
    return { uid: decoded.uid, email: decoded.email, plan };
  } catch (e) {
    console.error('Auth verification failed:', e.message);
    res.status(401).json({ error: 'Invalid or expired token' });
    return null;
  }
}

/**
 * Per-UID rate limiter using Firestore transaction.
 * Increments counter for today; rejects if over limit.
 * Returns true if allowed, sends 429 and returns false otherwise.
 */
async function rateLimit(req, res, auth, action) {
  const limit = (RATE_LIMITS[auth.plan] || RATE_LIMITS.free)[action];
  if (limit === undefined || limit < 0) return true;  // unlimited

  const today = new Date().toISOString().slice(0, 10);  // YYYY-MM-DD UTC
  const ref = admin.firestore().doc(`rate_limits/${auth.uid}_${today}`);

  try {
    const result = await admin.firestore().runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      const data = doc.exists ? doc.data() : {};
      const used = data[action] || 0;
      if (used >= limit) return { allowed: false, used, limit };
      tx.set(ref, {
        ...data,
        [action]: used + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        // 48h TTL — Firestore TTL deletes old entries automatically
        expiresAt: new Date(Date.now() + 48 * 60 * 60 * 1000),
      }, { merge: true });
      return { allowed: true, used: used + 1, limit };
    });

    if (!result.allowed) {
      res.status(429).json({
        error: `Daily ${action} limit reached (${result.used}/${result.limit}). Upgrade your plan for more.`,
        used: result.used,
        limit: result.limit,
        plan: auth.plan,
      });
      return false;
    }
    return true;
  } catch (e) {
    console.error('Rate limit error:', e);
    return true;  // fail open — don't block users on infra error
  }
}

// ════════════════════════════════════════════════════════════════════
//   KNOWLEDGE BASE
// ════════════════════════════════════════════════════════════════════

let knowledgeBase = null;
function loadKnowledgeBase() {
  if (knowledgeBase) return knowledgeBase;
  try {
    knowledgeBase = require('./knowledge_base.json');
    console.log(`Knowledge base loaded: ${knowledgeBase.length} chunks`);
  } catch (e) {
    console.error('Failed to load knowledge base:', e.message);
    knowledgeBase = [];
  }
  return knowledgeBase;
}

function cosineSimilarity(a, b) {
  let dot = 0, magA = 0, magB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    magA += a[i] * a[i];
    magB += b[i] * b[i];
  }
  return dot / (Math.sqrt(magA) * Math.sqrt(magB));
}

function findRelevantChunks(queryEmbedding, chunks, topK = 8) {
  const scored = chunks.map(chunk => ({
    ...chunk,
    score: cosineSimilarity(queryEmbedding, chunk.embedding),
  }));
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, topK);
}

async function getQueryEmbedding(text) {
  const model = getGenAI().getGenerativeModel({ model: 'gemini-embedding-001' });
  const result = await model.embedContent({
    content: { parts: [{ text }] },
    taskType: 'RETRIEVAL_QUERY',
  });
  return result.embedding.values;
}

async function generateResponse(prompt) {
  const model = getGenAI().getGenerativeModel({ model: 'gemini-2.0-flash' });
  const result = await model.generateContent(prompt);
  return result.response.text();
}

// ════════════════════════════════════════════════════════════════════
//   PROMPT BUILDERS
// ════════════════════════════════════════════════════════════════════

function buildChatPrompt(question, relevantChunks, userProfile, chatHistory) {
  const versesContext = relevantChunks
    .map((c, i) => `[Source ${i + 1}: ${c.book} Ch.${c.chapter} "${c.chapter_name}", Verses ${c.verse_range}]\n${c.text}`)
    .join('\n\n---\n\n');

  const profileContext = userProfile ? `USER'S BIRTH DETAILS:
Name: ${userProfile.name || 'Not provided'}
Date of Birth: ${userProfile.dateOfBirth || 'Not provided'}
Time of Birth: ${userProfile.timeOfBirth || 'Not provided'}
Place of Birth: ${userProfile.placeOfBirth || 'Not provided'}
Western Sign: ${userProfile.westernSign || 'Not provided'}
Vedic Sign: ${userProfile.sunSign || 'Not provided'}` : 'No birth details available.';

  const historyContext = chatHistory && chatHistory.length > 0
    ? 'RECENT CONVERSATION:\n' + chatHistory.slice(-MAX_HISTORY_MSGS).map(m => `${m.role}: ${m.text}`).join('\n')
    : '';

  return `You are Jyotishi, a wise and compassionate Vedic astrologer trained in the traditions of Brihat Parashara Hora Shastra and Phaladeepika. You speak warmly, like a trusted family pandit.

IMPORTANT RULES:
- Answer ONLY using information from the sacred verses provided below
- Cite the specific source (book, chapter, verse) for every claim you make
- Keep responses between 150-300 words
- Write naturally in simple English, avoid jargon unless explaining it
- Never predict death, severe illness, or create fear
- Always end with one practical, positive remedy or suggestion
- If the question is outside Vedic astrology, politely redirect
- Do not use em dashes, use commas or periods instead
- Match the user's language (English, Hindi, or Hinglish)

${profileContext}

${historyContext}

RELEVANT VERSES FROM SACRED TEXTS:
${versesContext}

USER QUESTION: ${question}

Respond as Jyotishi, citing sources naturally within your answer.`;
}

function buildHoroscopePrompt(relevantChunks, sign, type) {
  const versesContext = relevantChunks
    .map(c => `[${c.book} Ch.${c.chapter}, Verses ${c.verse_range}]\n${c.text}`)
    .join('\n\n---\n\n');

  const periodLabel = type === 'daily' ? 'today' : type === 'weekly' ? 'this week' : 'this month';

  return `You are a Vedic astrologer creating a ${type} horoscope for ${sign} sign for ${periodLabel}.

Use ONLY the following Vedic texts. Make the horoscope feel personal and specific to ${sign}, NOT generic.

VERSES:
${versesContext}

Generate JSON with this exact format (no markdown, no code blocks):
{
  "sign": "${sign}",
  "period": "${type}",
  "career": "2-3 sentences specific to ${sign} for ${periodLabel}",
  "love": "2-3 sentences specific to ${sign} for ${periodLabel}",
  "health": "2-3 sentences specific to ${sign} for ${periodLabel}",
  "finance": "2-3 sentences specific to ${sign} for ${periodLabel}",
  "luckyColor": "one color appropriate for ${sign}",
  "luckyNumber": a number between 1 and 27,
  "remedy": "one simple practical remedy from the texts"
}`;
}

// ════════════════════════════════════════════════════════════════════
//   CHAT ENDPOINT
// ════════════════════════════════════════════════════════════════════

exports.chat = functions
  .region('us-central1')
  .runWith({ memory: '512MB', timeoutSeconds: 60, minInstances: 1 })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

      const auth = await verifyAuth(req, res);
      if (!auth) return;

      if (!await rateLimit(req, res, auth, 'chat')) return;

      try {
        let { question, userProfile, chatHistory } = req.body || {};

        if (!question || typeof question !== 'string') {
          return res.status(400).json({ error: 'question is required' });
        }
        if (question.length > MAX_QUESTION_LEN) {
          return res.status(400).json({ error: `Question too long (max ${MAX_QUESTION_LEN} chars)` });
        }

        const chunks = loadKnowledgeBase();
        if (chunks.length === 0) {
          return res.status(503).json({ error: 'Knowledge base unavailable' });
        }

        const queryEmbedding = await getQueryEmbedding(question);
        const relevant = findRelevantChunks(queryEmbedding, chunks, 8);
        const prompt = buildChatPrompt(question, relevant, userProfile, chatHistory);
        const answer = await generateResponse(prompt);

        const sources = relevant.slice(0, 5).map(c => ({
          book: c.book,
          chapter: c.chapter,
          chapterName: c.chapter_name,
          verseRange: c.verse_range,
          score: Math.round(c.score * 100) / 100,
        }));

        // Log to user's chat history (server-side, not client-writable)
        try {
          await admin.firestore()
            .collection(`users/${auth.uid}/chats`)
            .add({
              question, answer, sources,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } catch (_) {}

        return res.status(200).json({ answer, sources });
      } catch (err) {
        console.error('Chat error:', err);
        return res.status(500).json({ error: 'Chat service error' });
      }
    });
  });

// ════════════════════════════════════════════════════════════════════
//   HOROSCOPE ENDPOINT — server-side cached per (sign × period × date)
// ════════════════════════════════════════════════════════════════════

function horoscopePeriodKey(type, now) {
  const d = now || new Date();
  if (type === 'daily') return d.toISOString().slice(0, 10);   // YYYY-MM-DD
  if (type === 'weekly') {
    // ISO week number
    const tmp = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
    const dayNum = (tmp.getUTCDay() + 6) % 7;
    tmp.setUTCDate(tmp.getUTCDate() - dayNum + 3);
    const firstThursday = tmp.getTime();
    tmp.setUTCMonth(0, 1);
    if (tmp.getUTCDay() !== 4) tmp.setUTCMonth(0, 1 + ((4 - tmp.getUTCDay()) + 7) % 7);
    const week = 1 + Math.ceil((firstThursday - tmp) / 604800000);
    return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
  }
  if (type === 'monthly') return d.toISOString().slice(0, 7);  // YYYY-MM
  return d.toISOString().slice(0, 10);
}

exports.horoscope = functions
  .region('us-central1')
  .runWith({ memory: '512MB', timeoutSeconds: 60, minInstances: 1 })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

      const auth = await verifyAuth(req, res);
      if (!auth) return;

      if (!await rateLimit(req, res, auth, 'horoscope')) return;

      try {
        const { userProfile, type = 'daily' } = req.body || {};
        if (!['daily', 'weekly', 'monthly'].includes(type)) {
          return res.status(400).json({ error: 'type must be daily|weekly|monthly' });
        }

        const sign = (userProfile?.sunSign || userProfile?.westernSign || 'Aries').trim();
        const periodKey = horoscopePeriodKey(type);
        const cacheKey = `${sign.toLowerCase()}_${type}_${periodKey}`.replace(/\s+/g, '_');
        const cacheRef = admin.firestore().doc(`horoscope_cache/${cacheKey}`);

        // Check cache first
        const cached = await cacheRef.get();
        if (cached.exists) {
          const data = cached.data();
          return res.status(200).json({ ...data, cached: true });
        }

        // Generate fresh
        const chunks = loadKnowledgeBase();
        const query = `${sign} ${type} horoscope career love health transits`;
        const queryEmbedding = await getQueryEmbedding(query);
        const relevant = findRelevantChunks(queryEmbedding, chunks, 10);

        const prompt = buildHoroscopePrompt(relevant, sign, type);
        const responseText = await generateResponse(prompt);

        let horoscope;
        try {
          const clean = responseText.replace(/```json?\n?/g, '').replace(/```\n?/g, '').trim();
          horoscope = JSON.parse(clean);
        } catch (e) {
          horoscope = {
            sign, period: type,
            career: 'Unable to parse this period\'s horoscope. Please try again.',
            love: '', health: '', finance: '',
            luckyColor: 'Yellow', luckyNumber: 7, remedy: 'Chant Om Gurave Namah 108 times.',
          };
        }

        const sources = relevant.slice(0, 5).map(c => ({
          book: c.book,
          chapter: c.chapter,
          chapterName: c.chapter_name,
          verseRange: c.verse_range,
        }));

        const result = { ...horoscope, sources };

        // Cache for next user (TTL via expiresAt + Firestore TTL policy)
        const ttlHours = type === 'daily' ? 24 : type === 'weekly' ? 24 * 7 : 24 * 30;
        try {
          await cacheRef.set({
            ...result,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: new Date(Date.now() + ttlHours * 60 * 60 * 1000),
          });
        } catch (_) {}

        return res.status(200).json({ ...result, cached: false });
      } catch (err) {
        console.error('Horoscope error:', err);
        return res.status(500).json({ error: 'Horoscope service error' });
      }
    });
  });

// ════════════════════════════════════════════════════════════════════
//   PALM READING ENDPOINT (server-side, replaces client-direct Gemini)
// ════════════════════════════════════════════════════════════════════

const PALM_PROMPT = `You are a Vedic palm reading expert versed in Samudrik Shastra.

FIRST: Check if the image actually shows a human palm/hand. If NOT, return EXACTLY this JSON:
{"error":"NOT_A_PALM","message":"This image does not show a hand. Please upload a clear photo of your palm with fingers spread."}

If it IS a palm, analyze:
1. Heart Line (Hridaya Rekha): Love, emotions, relationships
2. Head Line (Buddhi Rekha): Intelligence, thinking style, career approach
3. Life Line (Jeevan Rekha): Vitality, energy, life journey (NOT lifespan)

Return ONLY valid JSON, no markdown:
{
  "loveLine": {"title":"Heart Line","emoji":"❤️","insight":"...","meaning":"...","advice":"..."},
  "careerLine": {"title":"Head Line","emoji":"🧠","insight":"...","meaning":"...","advice":"..."},
  "lifeLine": {"title":"Life Line","emoji":"🧬","insight":"...","meaning":"...","advice":"..."}
}

Each section: 3-4 sentences, warm tone, reference Samudrik Shastra. NEVER predict death or lifespan.`;

exports.palmAnalyze = functions
  .region('us-central1')
  .runWith({ memory: '1GB', timeoutSeconds: 90, minInstances: 0 })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

      const auth = await verifyAuth(req, res);
      if (!auth) return;

      if (!await rateLimit(req, res, auth, 'palm')) return;

      try {
        const { imageBase64, mimeType = 'image/jpeg' } = req.body || {};
        if (!imageBase64 || typeof imageBase64 !== 'string') {
          return res.status(400).json({ error: 'imageBase64 required' });
        }
        // Approx byte size check
        const approxBytes = (imageBase64.length * 3) / 4;
        if (approxBytes > MAX_PALM_BYTES) {
          return res.status(413).json({ error: 'Image too large (max 5MB)' });
        }

        const model = getGenAI().getGenerativeModel({ model: 'gemini-2.0-flash' });
        const result = await model.generateContent([
          PALM_PROMPT,
          { inlineData: { data: imageBase64, mimeType } },
        ]);
        const text = result.response.text();

        let parsed;
        try {
          const clean = text.replace(/```json?\n?/g, '').replace(/```\n?/g, '').trim();
          parsed = JSON.parse(clean);
        } catch (e) {
          console.error('Palm parse failed:', e.message, 'text:', text.slice(0, 200));
          return res.status(502).json({
            error: 'AI returned an unexpected format. Please try again with a clearer photo.',
          });
        }

        // Validate structure to prevent client crashes
        if (parsed.error === 'NOT_A_PALM') {
          return res.status(200).json(parsed);
        }
        const required = ['loveLine', 'careerLine', 'lifeLine'];
        for (const k of required) {
          if (!parsed[k] || typeof parsed[k] !== 'object') {
            return res.status(502).json({ error: 'Incomplete palm reading. Please try again.' });
          }
        }

        // Log reading
        try {
          await admin.firestore()
            .collection(`users/${auth.uid}/palmReadings`)
            .add({
              result: parsed,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } catch (_) {}

        return res.status(200).json(parsed);
      } catch (err) {
        console.error('Palm error:', err);
        return res.status(500).json({ error: 'Palm reading service error' });
      }
    });
  });

// ════════════════════════════════════════════════════════════════════
//   SUBSCRIPTION ENDPOINTS
// ════════════════════════════════════════════════════════════════════

exports.subscriptionCreate = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

      const auth = await verifyAuth(req, res);
      if (!auth) return;

      try {
        const { plan } = req.body || {};
        if (!plan || !PLAN_IDS[plan]) {
          return res.status(400).json({ error: 'Invalid plan' });
        }

        // Use auth-verified email/uid — DO NOT trust client-supplied values
        const userEmail = auth.email;
        const userId = auth.uid;
        if (!userEmail) {
          return res.status(400).json({ error: 'Email not on user account' });
        }

        // Admin bypass
        if (isAdminEmail(userEmail)) {
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: true,
            plan,
            via: 'admin_bypass',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return res.status(200).json({ admin: true });
        }

        const razorpay = getRazorpay();
        const sevenDays = 7 * 24 * 60 * 60;
        const startAt = plan === 'trial'
          ? Math.floor(Date.now() / 1000) + sevenDays
          : Math.floor(Date.now() / 1000);

        const subscription = await razorpay.subscriptions.create({
          plan_id: PLAN_IDS[plan],
          total_count: 12,
          customer_notify: 1,
          start_at: startAt,
          notes: { plan, userId, userEmail },
        });

        await admin.firestore().doc(`subscriptions/${subscription.id}`).set({
          subscriptionId: subscription.id,
          userId, userEmail, plan,
          status: subscription.status,
          startAt,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return res.status(200).json({
          subscriptionId: subscription.id,
          shortUrl: subscription.short_url,
          status: subscription.status,
          startAt,
        });
      } catch (err) {
        console.error('subscriptionCreate error:', err);
        return res.status(500).json({ error: err.message || 'Failed to create subscription' });
      }
    });
  });

exports.subscriptionCancel = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

      const auth = await verifyAuth(req, res);
      if (!auth) return;

      try {
        const { subscriptionId, immediate = false } = req.body || {};
        if (!subscriptionId) return res.status(400).json({ error: 'subscriptionId required' });

        // Verify the subscription belongs to this user
        const subDoc = await admin.firestore().doc(`subscriptions/${subscriptionId}`).get();
        if (!subDoc.exists || subDoc.data().userId !== auth.uid) {
          return res.status(403).json({ error: 'Subscription not found or not yours' });
        }

        const razorpay = getRazorpay();
        const result = await razorpay.subscriptions.cancel(
          subscriptionId,
          immediate ? false : true,
        );

        await admin.firestore().doc(`subscriptions/${subscriptionId}`).set({
          status: result.status,
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancelImmediate: immediate,
        }, { merge: true });

        if (immediate) {
          await admin.firestore().doc(`usage/${auth.uid}`).set({
            isPremium: false,
            plan: 'free',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }

        return res.status(200).json({
          status: result.status,
          cancelled: true,
          immediate,
        });
      } catch (err) {
        console.error('subscriptionCancel error:', err);
        return res.status(500).json({ error: err.message });
      }
    });
  });

// ════════════════════════════════════════════════════════════════════
//   RAZORPAY WEBHOOK — RAW BODY signature verification
// ════════════════════════════════════════════════════════════════════
//
// CRITICAL: Razorpay signs the RAW request body. If we let Express parse
// the JSON first and then re-stringify it, key order and whitespace will
// differ from what Razorpay signed, causing valid signatures to fail.
// We use req.rawBody (Firebase Functions exposes this) for HMAC.

exports.razorpayWebhook = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onRequest(async (req, res) => {
    try {
      const cfg = functions.config().razorpay || {};
      const webhookSecret = cfg.webhook_secret || process.env.RAZORPAY_WEBHOOK_SECRET;
      if (!webhookSecret) {
        console.error('Webhook secret not configured');
        return res.status(500).send('Server misconfigured');
      }

      const signature = req.headers['x-razorpay-signature'];
      if (!signature) return res.status(400).send('Missing signature');

      // Firebase Functions provides req.rawBody as a Buffer
      const rawBody = req.rawBody || Buffer.from(JSON.stringify(req.body));
      const expectedSig = crypto
        .createHmac('sha256', webhookSecret)
        .update(rawBody)
        .digest('hex');

      // Constant-time comparison to prevent timing attacks
      if (signature.length !== expectedSig.length ||
          !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expectedSig))) {
        console.error('Invalid webhook signature');
        return res.status(400).send('Invalid signature');
      }

      const event = req.body.event;
      const payload = req.body.payload || {};
      const sub = payload.subscription && payload.subscription.entity;
      const subscriptionId = sub && sub.id;

      console.log(`Razorpay webhook: ${event} for sub ${subscriptionId}`);

      if (!subscriptionId) return res.status(200).send('No subscription in payload');

      const subDoc = await admin.firestore().doc(`subscriptions/${subscriptionId}`).get();
      if (!subDoc.exists) {
        console.warn(`Subscription ${subscriptionId} not found`);
        return res.status(200).send('ok');
      }
      const userId = subDoc.data().userId;
      const plan = subDoc.data().plan;

      switch (event) {
        case 'subscription.charged':
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: true, plan,
            lastChargedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          await admin.firestore().doc(`subscriptions/${subscriptionId}`).set({
            status: 'active',
            lastChargedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          break;

        case 'subscription.activated':
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: true, plan,
            mandateActivatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          break;

        case 'subscription.cancelled':
        case 'subscription.completed':
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: false, plan: 'free',
            cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          break;

        case 'subscription.halted':
        case 'payment.failed':
          await admin.firestore().doc(`subscriptions/${subscriptionId}`).set({
            lastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: event === 'subscription.halted' ? 'halted' : 'payment_failed',
          }, { merge: true });
          break;

        default:
          console.log(`Unhandled event: ${event}`);
      }

      return res.status(200).send('ok');
    } catch (err) {
      console.error('Webhook error:', err);
      return res.status(500).send('error');
    }
  });

// ════════════════════════════════════════════════════════════════════
//   SEARCH (debug — auth required)
// ════════════════════════════════════════════════════════════════════

exports.search = functions
  .region('us-central1')
  .runWith({ memory: '512MB', timeoutSeconds: 30 })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

      const auth = await verifyAuth(req, res);
      if (!auth) return;

      try {
        const { query, topK = 5 } = req.body || {};
        if (!query) return res.status(400).json({ error: 'query is required' });
        if (query.length > MAX_QUESTION_LEN) {
          return res.status(400).json({ error: 'query too long' });
        }

        const chunks = loadKnowledgeBase();
        const queryEmbedding = await getQueryEmbedding(query);
        const results = findRelevantChunks(queryEmbedding, chunks, topK);

        return res.status(200).json({
          results: results.map(r => ({
            id: r.id,
            book: r.book,
            chapter: r.chapter,
            chapterName: r.chapter_name,
            verseRange: r.verse_range,
            topics: r.topics,
            planets: r.planets,
            text: r.text.substring(0, 500),
            score: Math.round(r.score * 1000) / 1000,
          })),
        });
      } catch (err) {
        console.error('Search error:', err);
        return res.status(500).json({ error: err.message });
      }
    });
  });
