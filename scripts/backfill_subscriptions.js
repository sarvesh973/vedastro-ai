/**
 * One-shot backfill: heal `users/{uid}/subscription/current` for every
 * paying user whose record was never written (Render webhook never ran,
 * or ran before `razorpaySubscriptionId` was tracked).
 *
 * Reads every doc in `subscriptions/`, finds the most recent
 * non-cancelled one per user, and writes the canonical doc the Flutter
 * app reads.
 *
 * USAGE (run once after deploying the updated functions/index.js):
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/service-account.json \
 *     node scripts/backfill_subscriptions.js
 *
 * Idempotent — safe to re-run.
 */
const admin = require('firebase-admin');

admin.initializeApp({
  projectId: process.env.FIREBASE_PROJECT_ID || 'vedastro-ai',
});

const db = admin.firestore();

async function main() {
  const snap = await db.collection('subscriptions').get();
  console.log(`Scanning ${snap.size} subscription docs…`);

  // Pick the most recent non-cancelled subscription per user.
  const byUser = new Map();
  snap.forEach((doc) => {
    const d = doc.data();
    if (!d.userId || !d.subscriptionId) return;
    if (d.status === 'cancelled' || d.status === 'completed') return;
    const prev = byUser.get(d.userId);
    const created = d.createdAt ? d.createdAt.toMillis() : 0;
    const prevCreated = prev && prev.createdAt ? prev.createdAt.toMillis() : 0;
    if (!prev || created > prevCreated) {
      byUser.set(d.userId, d);
    }
  });

  console.log(`Found ${byUser.size} users to backfill.`);

  let written = 0;
  let skipped = 0;
  for (const [userId, sub] of byUser.entries()) {
    const ref = db.doc(`users/${userId}/subscription/current`);
    const existing = await ref.get();
    if (existing.exists && existing.data().razorpaySubscriptionId) {
      skipped += 1;
      continue;
    }
    await ref.set(
      {
        plan: sub.plan,
        state: existing.exists && existing.data().state
          ? existing.data().state
          : 'active',
        razorpaySubscriptionId: sub.subscriptionId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        backfilledAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    written += 1;
    console.log(`  ✓ ${userId} ← ${sub.subscriptionId} (${sub.plan})`);
  }

  console.log(`Done. Wrote ${written}, skipped ${skipped}.`);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
