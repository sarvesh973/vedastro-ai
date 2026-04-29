const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const cors = require('cors')({ origin: true });
const Razorpay = require('razorpay');
const crypto = require('crypto');

admin.initializeApp();

// ─── RAZORPAY CONFIG ──────────────────────────────────────────────
// Set these via:
//   firebase functions:config:set razorpay.key_id="rzp_live_xxx" \
//                                   razorpay.key_secret="xxx" \
//                                   razorpay.webhook_secret="xxx"
function getRazorpay() {
  const cfg = functions.config().razorpay || {};
  const keyId = cfg.key_id || process.env.RAZORPAY_KEY_ID;
  const keySecret = cfg.key_secret || process.env.RAZORPAY_KEY_SECRET;
  if (!keyId || !keySecret) {
    throw new Error('Razorpay credentials not configured');
  }
  return new Razorpay({ key_id: keyId, key_secret: keySecret });
}

// Razorpay plan IDs configured in dashboard.razorpay.com → Subscriptions → Plans
// IMPORTANT: trial_99 must be ₹99/month with NO trial period set in the plan.
// Server controls the 7-day delay via start_at parameter.
const PLAN_IDS = {
  trial:    'plan_trial_99',     // ₹99/month, but 7-day free trial via start_at
  standard: 'plan_standard_199', // ₹199/month
  premium:  'plan_premium_499',  // ₹499/month
};

// Comma-separated list of admin emails who skip payment.
// Set via: firebase functions:config:set admin.emails="you@x.com,founder@y.com"
function isAdminEmail(email) {
  if (!email) return false;
  const cfg = (functions.config().admin && functions.config().admin.emails) ||
              process.env.ADMIN_EMAILS || '';
  const list = cfg.split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  return list.includes(email.toLowerCase());
}

// --- LOAD KNOWLEDGE BASE ---
// Loaded once on cold start, stays in memory
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

// --- VECTOR SIMILARITY ---
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

// --- GEMINI HELPERS ---
function getGenAI() {
  const apiKey = functions.config().gemini?.key || process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY not configured');
  return new GoogleGenerativeAI(apiKey);
}

async function getQueryEmbedding(text) {
  const genAI = getGenAI();
  const model = genAI.getGenerativeModel({ model: 'gemini-embedding-001' });
  const result = await model.embedContent({
    content: { parts: [{ text }] },
    taskType: 'RETRIEVAL_QUERY',
  });
  return result.embedding.values;
}

async function generateResponse(prompt) {
  const genAI = getGenAI();
  const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
  const result = await model.generateContent(prompt);
  return result.response.text();
}

// --- BUILD PROMPTS ---
function buildChatPrompt(question, relevantChunks, userProfile, chatHistory) {
  const versesContext = relevantChunks
    .map((c, i) => `[Source ${i + 1}: ${c.book} Ch.${c.chapter} "${c.chapter_name}", Verses ${c.verse_range}]\n${c.text}`)
    .join('\n\n---\n\n');

  const profileContext = userProfile
    ? `USER'S BIRTH DETAILS:
Name: ${userProfile.name || 'Not provided'}
Date of Birth: ${userProfile.dateOfBirth || 'Not provided'}
Time of Birth: ${userProfile.timeOfBirth || 'Not provided'}
Place of Birth: ${userProfile.placeOfBirth || 'Not provided'}
Western Sign: ${userProfile.westernSign || 'Not provided'}
Vedic Sign: ${userProfile.sunSign || 'Not provided'}`
    : 'No birth details available.';

  const historyContext = chatHistory && chatHistory.length > 0
    ? 'RECENT CONVERSATION:\n' + chatHistory.map(m => `${m.role}: ${m.text}`).join('\n')
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
- Do not use em dashes (—), use commas or periods instead
- Do not use forced emoji section headers

${profileContext}

${historyContext}

RELEVANT VERSES FROM SACRED TEXTS:
${versesContext}

USER QUESTION: ${question}

Respond as Jyotishi, citing sources naturally within your answer (e.g., "According to BPHS Chapter 18..."). Be warm, specific, and helpful.`;
}

function buildHoroscopePrompt(relevantChunks, userProfile, type) {
  const versesContext = relevantChunks
    .map(c => `[${c.book} Ch.${c.chapter}, Verses ${c.verse_range}]\n${c.text}`)
    .join('\n\n---\n\n');

  const sign = userProfile?.sunSign || userProfile?.westernSign || 'Aries';
  const periodLabel = type === 'daily' ? 'today' : type === 'weekly' ? 'this week' : 'this month';

  return `You are a Vedic astrologer creating a ${type} horoscope for ${sign} sign.

Using ONLY the following Vedic texts as your source, generate a horoscope for ${periodLabel}.

VERSES:
${versesContext}

Generate a JSON response with this exact format:
{
  "sign": "${sign}",
  "period": "${type}",
  "career": "2-3 sentences about career and finance based on the verses",
  "love": "2-3 sentences about love and relationships based on the verses",
  "health": "2-3 sentences about health and wellness based on the verses",
  "finance": "2-3 sentences about money and wealth based on the verses",
  "luckyColor": "one color",
  "luckyNumber": a number between 1 and 27,
  "remedy": "one simple remedy from the texts",
  "sources": ["list of source citations used"]
}

Return ONLY valid JSON, no markdown code blocks.`;
}

// =========================================
// CLOUD FUNCTION ENDPOINTS
// =========================================

/**
 * POST /api/chat
 * Body: { question, userProfile?, chatHistory? }
 * Returns: { answer, sources }
 */
exports.chat = functions
  .runWith({ memory: '512MB', timeoutSeconds: 60 })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      try {
        const { question, userProfile, chatHistory } = req.body;

        if (!question || typeof question !== 'string') {
          return res.status(400).json({ error: 'question is required' });
        }

        // 1. Load knowledge base
        const chunks = loadKnowledgeBase();

        // 2. Get query embedding
        const queryEmbedding = await getQueryEmbedding(question);

        // 3. Find relevant verses
        const relevant = findRelevantChunks(queryEmbedding, chunks, 8);

        // 4. Build prompt and generate response
        const prompt = buildChatPrompt(question, relevant, userProfile, chatHistory);
        const answer = await generateResponse(prompt);

        // 5. Extract source citations
        const sources = relevant.slice(0, 5).map(c => ({
          book: c.book,
          chapter: c.chapter,
          chapterName: c.chapter_name,
          verseRange: c.verse_range,
          score: Math.round(c.score * 100) / 100,
        }));

        return res.status(200).json({ answer, sources });
      } catch (err) {
        console.error('Chat error:', err);
        return res.status(500).json({ error: err.message });
      }
    });
  });

/**
 * POST /api/horoscope
 * Body: { userProfile, type: "daily"|"weekly"|"monthly" }
 * Returns: { career, love, health, finance, luckyColor, luckyNumber, remedy, sources }
 */
exports.horoscope = functions
  .runWith({ memory: '512MB', timeoutSeconds: 60 })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      try {
        const { userProfile, type = 'daily' } = req.body;

        if (!['daily', 'weekly', 'monthly'].includes(type)) {
          return res.status(400).json({ error: 'type must be daily, weekly, or monthly' });
        }

        // 1. Load knowledge base
        const chunks = loadKnowledgeBase();

        // 2. Build query based on type
        const sign = userProfile?.sunSign || userProfile?.westernSign || 'Aries';
        const query = `${sign} horoscope ${type} predictions career love health transits effects`;
        const queryEmbedding = await getQueryEmbedding(query);

        // 3. Find relevant transit and effect verses
        const relevant = findRelevantChunks(queryEmbedding, chunks, 10);

        // 4. Generate horoscope
        const prompt = buildHoroscopePrompt(relevant, userProfile, type);
        const responseText = await generateResponse(prompt);

        // 5. Parse JSON response
        let horoscope;
        try {
          // Strip any markdown code fences if present
          const clean = responseText.replace(/```json?\n?/g, '').replace(/```\n?/g, '').trim();
          horoscope = JSON.parse(clean);
        } catch (e) {
          // If JSON parse fails, return raw text
          horoscope = { raw: responseText, error: 'Failed to parse structured response' };
        }

        const sources = relevant.slice(0, 5).map(c => ({
          book: c.book,
          chapter: c.chapter,
          chapterName: c.chapter_name,
          verseRange: c.verse_range,
        }));

        return res.status(200).json({ ...horoscope, sources });
      } catch (err) {
        console.error('Horoscope error:', err);
        return res.status(500).json({ error: err.message });
      }
    });
  });

/**
 * POST /api/search
 * Body: { query, topK? }
 * Returns: { results: [{ book, chapter, text, score }] }
 * Useful for debugging and testing retrieval quality
 */
exports.search = functions
  .runWith({ memory: '512MB', timeoutSeconds: 30 })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      try {
        const { query, topK = 5 } = req.body;

        if (!query) {
          return res.status(400).json({ error: 'query is required' });
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

// ════════════════════════════════════════════════════════════════════
//   SUBSCRIPTION ENDPOINTS — Razorpay
// ════════════════════════════════════════════════════════════════════

/**
 * POST /subscription/create
 * Body: { plan: 'trial'|'standard'|'premium', userEmail, userId }
 * Returns: { subscriptionId, shortUrl } OR { admin: true }
 *
 * For 'trial' plan: server passes start_at = now + 7 days,
 * so Razorpay e-mandate is registered today (₹0) and first ₹99
 * is auto-debited on day 7. Then ₹99/month recurring.
 */
exports.subscriptionCreate = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }
      try {
        const { plan, userEmail, userId } = req.body || {};
        if (!plan || !PLAN_IDS[plan]) {
          return res.status(400).json({ error: 'Invalid plan. Use trial|standard|premium' });
        }
        if (!userEmail || !userId) {
          return res.status(400).json({ error: 'userEmail and userId required' });
        }

        // Admin bypass — no payment required
        if (isAdminEmail(userEmail)) {
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: true,
            plan: plan,
            via: 'admin_bypass',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return res.status(200).json({ admin: true });
        }

        const razorpay = getRazorpay();

        // For trial: delay first charge by 7 days.
        // For standard/premium: charge immediately.
        const sevenDays = 7 * 24 * 60 * 60;
        const startAt = plan === 'trial'
          ? Math.floor(Date.now() / 1000) + sevenDays
          : Math.floor(Date.now() / 1000);

        const subscription = await razorpay.subscriptions.create({
          plan_id: PLAN_IDS[plan],
          total_count: 12,           // Run for 12 cycles (1 year)
          customer_notify: 1,        // Razorpay sends email/SMS on each charge
          start_at: startAt,
          notes: {
            plan: plan,
            userId: userId,
            userEmail: userEmail,
          },
        });

        // Persist subscription mapping in Firestore so we can look it up
        // when the webhook fires (webhook only knows subscription_id).
        await admin.firestore().doc(`subscriptions/${subscription.id}`).set({
          subscriptionId: subscription.id,
          userId: userId,
          userEmail: userEmail,
          plan: plan,
          status: subscription.status,
          startAt: startAt,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return res.status(200).json({
          subscriptionId: subscription.id,
          shortUrl: subscription.short_url,
          status: subscription.status,
          startAt: startAt,
        });
      } catch (err) {
        console.error('subscriptionCreate error:', err);
        return res.status(500).json({
          error: err.message || 'Failed to create subscription',
        });
      }
    });
  });

/**
 * POST /subscription/cancel
 * Body: { subscriptionId, userEmail, immediate? }
 * Default: cancel at end of current billing period (RBI-compliant).
 */
exports.subscriptionCancel = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onRequest((req, res) => {
    cors(req, res, async () => {
      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }
      try {
        const { subscriptionId, userEmail, immediate = false } = req.body || {};
        if (!subscriptionId) {
          return res.status(400).json({ error: 'subscriptionId required' });
        }

        const razorpay = getRazorpay();
        const result = await razorpay.subscriptions.cancel(
          subscriptionId,
          immediate ? false : true,  // cancel_at_cycle_end = true unless immediate
        );

        // Update Firestore mapping
        await admin.firestore().doc(`subscriptions/${subscriptionId}`).set({
          status: result.status,
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancelImmediate: immediate,
        }, { merge: true });

        // If immediate, revoke premium right now. Otherwise let webhook
        // handle it when the period ends.
        if (immediate) {
          const sub = await admin.firestore()
            .doc(`subscriptions/${subscriptionId}`).get();
          const userId = sub.data()?.userId;
          if (userId) {
            await admin.firestore().doc(`usage/${userId}`).set({
              isPremium: false,
              plan: 'free',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
        }

        return res.status(200).json({
          status: result.status,
          cancelled: true,
          immediate: immediate,
        });
      } catch (err) {
        console.error('subscriptionCancel error:', err);
        return res.status(500).json({ error: err.message });
      }
    });
  });

/**
 * POST /razorpay/webhook
 * Razorpay fires this on subscription events.
 * Configure webhook URL + secret in Razorpay dashboard.
 *
 * Events handled:
 *   subscription.charged    → mark user premium (first ₹99 debit on day 7)
 *   subscription.activated  → mandate registered (₹0 today)
 *   subscription.cancelled  → revoke premium
 *   subscription.completed  → 12 cycles done, free again
 *   payment.failed          → log + future: notify user
 */
exports.razorpayWebhook = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onRequest(async (req, res) => {
    try {
      // 1. Verify webhook signature
      const cfg = functions.config().razorpay || {};
      const webhookSecret = cfg.webhook_secret || process.env.RAZORPAY_WEBHOOK_SECRET;
      if (!webhookSecret) {
        console.error('Webhook secret not configured');
        return res.status(500).send('Server misconfigured');
      }
      const signature = req.headers['x-razorpay-signature'];
      const body = JSON.stringify(req.body);
      const expectedSig = crypto
        .createHmac('sha256', webhookSecret)
        .update(body)
        .digest('hex');
      if (signature !== expectedSig) {
        console.error('Invalid webhook signature');
        return res.status(400).send('Invalid signature');
      }

      const event = req.body.event;
      const payload = req.body.payload || {};
      const sub = payload.subscription && payload.subscription.entity;
      const subscriptionId = sub?.id;

      console.log(`Razorpay webhook: ${event} for sub ${subscriptionId}`);

      if (!subscriptionId) {
        return res.status(200).send('No subscription in payload');
      }

      // Look up our Firestore record to find userId
      const subDoc = await admin.firestore()
        .doc(`subscriptions/${subscriptionId}`).get();
      if (!subDoc.exists) {
        console.warn(`Subscription ${subscriptionId} not found in Firestore`);
        return res.status(200).send('ok');
      }
      const userId = subDoc.data().userId;
      const plan = subDoc.data().plan;

      switch (event) {
        case 'subscription.charged':
          // First real ₹99 debit on day 7, then monthly recurring
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: true,
            plan: plan,
            lastChargedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          await admin.firestore()
            .doc(`subscriptions/${subscriptionId}`).set({
              status: 'active',
              lastChargedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          break;

        case 'subscription.activated':
          // E-mandate registered (today, ₹0). For trial: user gets premium
          // ACCESS during 7-day trial; for paid plans: immediate access.
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: true,
            plan: plan,
            mandateActivatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          break;

        case 'subscription.cancelled':
        case 'subscription.completed':
          await admin.firestore().doc(`usage/${userId}`).set({
            isPremium: false,
            plan: 'free',
            cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          break;

        case 'subscription.halted':
        case 'payment.failed':
          // Don't revoke premium yet — Razorpay will retry. Just log.
          await admin.firestore()
            .doc(`subscriptions/${subscriptionId}`).set({
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
