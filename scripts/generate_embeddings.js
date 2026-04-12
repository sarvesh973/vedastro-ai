/**
 * VedAstro AI — Embedding Generator
 *
 * Takes the extracted knowledge base chunks and generates
 * vector embeddings using Gemini Embedding API.
 * Output: chunks_with_embeddings.json (ready for Cloud Function)
 *
 * Usage: node scripts/generate_embeddings.js
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

// --- CONFIG ---
const API_KEY = fs.readFileSync(path.join(__dirname, '.env'), 'utf8')
  .split('\n')
  .find(l => l.startsWith('GEMINI_API_KEY='))
  ?.split('=')[1]
  ?.trim();

if (!API_KEY) {
  console.error('ERROR: GEMINI_API_KEY not found in scripts/.env');
  process.exit(1);
}

const MODEL = 'gemini-embedding-001';
const BATCH_SIZE = 3; // 3 parallel for speed
const INPUT_FILE = path.join(__dirname, '..', 'knowledge_base', 'all_chunks.json');
const OUTPUT_FILE = path.join(__dirname, '..', 'knowledge_base', 'chunks_with_embeddings.json');

// --- GEMINI EMBEDDING API ---
function embedSingle(text) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: `models/${MODEL}`,
      content: { parts: [{ text }] },
      taskType: 'RETRIEVAL_DOCUMENT',
    });

    const url = new URL(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:embedContent?key=${API_KEY}`
    );

    const options = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode !== 200) {
          reject(new Error(`API error ${res.statusCode}: ${data.substring(0, 300)}`));
          return;
        }
        try {
          const parsed = JSON.parse(data);
          resolve(parsed.embedding.values);
        } catch (e) {
          reject(new Error(`Parse error: ${e.message}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function embedWithRetry(text) {
  for (let retries = 0; retries < 5; retries++) {
    try {
      return await embedSingle(text);
    } catch (err) {
      if (err.message.includes('429') && retries < 4) {
        const waitTime = Math.pow(2, retries) * 5000;
        process.stdout.write(`[429, wait ${waitTime/1000}s] `);
        await sleep(waitTime);
      } else {
        throw err;
      }
    }
  }
}

async function embedBatch(texts) {
  return Promise.all(texts.map(t => embedWithRetry(t)));
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// --- MAIN ---
async function main() {
  console.log('VedAstro AI — Embedding Generator');
  console.log('==================================\n');

  // Load chunks
  const chunks = JSON.parse(fs.readFileSync(INPUT_FILE, 'utf8'));
  console.log(`Loaded ${chunks.length} chunks from knowledge base\n`);

  // Check for existing progress
  let processed = [];
  if (fs.existsSync(OUTPUT_FILE)) {
    processed = JSON.parse(fs.readFileSync(OUTPUT_FILE, 'utf8'));
    console.log(`Found ${processed.length} already embedded chunks (resuming)\n`);
  }

  const startFrom = processed.length;
  const remaining = chunks.slice(startFrom);

  if (remaining.length === 0) {
    console.log('All chunks already have embeddings!');
    return;
  }

  console.log(`Generating embeddings for ${remaining.length} chunks...`);
  console.log(`Batch size: ${BATCH_SIZE} | Estimated batches: ${Math.ceil(remaining.length / BATCH_SIZE)}\n`);

  // Process in batches
  for (let i = 0; i < remaining.length; i += BATCH_SIZE) {
    const batch = remaining.slice(i, i + BATCH_SIZE);
    const batchNum = Math.floor(i / BATCH_SIZE) + 1;
    const totalBatches = Math.ceil(remaining.length / BATCH_SIZE);

    // Prepare text for embedding (combine key fields for better retrieval)
    const texts = batch.map(chunk => {
      const topicStr = chunk.topics.length > 0 ? `Topics: ${chunk.topics.join(', ')}. ` : '';
      const planetStr = chunk.planets.length > 0 ? `Planets: ${chunk.planets.join(', ')}. ` : '';
      return `${chunk.book} Chapter ${chunk.chapter}: ${chunk.chapter_name}. ${topicStr}${planetStr}${chunk.text}`;
    });

    try {
      process.stdout.write(`  Batch ${batchNum}/${totalBatches} (${batch.length} chunks)... `);
      const embeddings = await embedBatch(texts);

      // Attach embeddings to chunks
      for (let j = 0; j < batch.length; j++) {
        processed.push({
          ...batch[j],
          embedding: embeddings[j],
        });
      }

      console.log(`done (${embeddings[0].length}-dim vectors)`);

      // Save progress after each batch
      fs.writeFileSync(OUTPUT_FILE, JSON.stringify(processed));

      // Brief pause between batches
      if (i + BATCH_SIZE < remaining.length) {
        await sleep(800);
      }
    } catch (err) {
      console.error(`\nERROR on batch ${batchNum}: ${err.message}`);
      console.log(`Progress saved: ${processed.length}/${chunks.length} chunks`);
      console.log('Re-run this script to resume from where it stopped.');
      fs.writeFileSync(OUTPUT_FILE, JSON.stringify(processed));
      process.exit(1);
    }
  }

  // Final save with pretty formatting info
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(processed));

  const fileSizeMB = (fs.statSync(OUTPUT_FILE).size / 1024 / 1024).toFixed(2);
  console.log(`\n==================================`);
  console.log(`Embedding generation complete!`);
  console.log(`Total chunks: ${processed.length}`);
  console.log(`Vector dimensions: ${processed[0].embedding.length}`);
  console.log(`Output file: ${OUTPUT_FILE}`);
  console.log(`File size: ${fileSizeMB} MB`);
}

main().catch(console.error);
