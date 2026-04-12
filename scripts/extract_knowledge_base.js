/**
 * VedAstro AI — Knowledge Base Extractor
 *
 * Extracts text from BPHS and Phaladeepika PDFs,
 * chunks them by chapter/topic, and outputs JSON
 * ready for Firestore + embedding generation.
 *
 * Usage: node scripts/extract_knowledge_base.js
 */

const pdfjsLib = require('pdfjs-dist/legacy/build/pdf.js');
const fs = require('fs');
const path = require('path');

// --- CONFIG ---
const BPHS_PATH = 'C:/Users/user/OneDrive/Desktop/brihat_parashara_hora_shastra_english_v.pdf';
const PHALA_PATH = 'C:/Users/user/Downloads/pdfcoffee.com_phaladeepika-9-pdf-free.pdf';
const OUTPUT_DIR = path.join(__dirname, '..', 'knowledge_base');

// Topic keywords for tagging chunks
const TOPIC_KEYWORDS = {
  'marriage': ['marriage', 'spouse', 'wife', 'husband', 'kalatra', 'yuvati', '7th house', 'seventh house', 'matrimon'],
  'career': ['career', 'profession', 'livelihood', 'karm bhava', '10th house', 'tenth house', 'occupation', 'vocation', 'trade'],
  'wealth': ['wealth', 'money', 'dhan', 'finance', 'fortune', 'riches', 'prosperity', '2nd house', 'second house', '11th house', 'eleventh house'],
  'health': ['disease', 'health', 'illness', 'ailment', 'sick', 'longevity', 'death', 'marak'],
  'children': ['children', 'progeny', 'putr', 'offspring', 'son', 'daughter', 'issue', '5th house', 'fifth house'],
  'education': ['education', 'learning', 'knowledge', 'vidya', 'intellig', 'study'],
  'love': ['love', 'romance', 'relationship', 'attraction', 'passion', 'affair'],
  'spirituality': ['spiritual', 'moksha', 'liberation', 'ascetic', 'renunciation', 'dharma', 'religion', 'pilgrim'],
  'property': ['property', 'land', 'house', 'vehicle', 'home', 'bandhu', '4th house', 'fourth house'],
  'travel': ['travel', 'journey', 'foreign', 'abroad', 'pilgrim', 'voyage'],
  'enemies': ['enemy', 'enemies', 'ari', 'obstacle', 'litigation', 'dispute', '6th house', 'sixth house'],
  'yogas': ['yoga', 'rajayoga', 'dhana yoga', 'combination'],
  'dashas': ['dasha', 'bhukti', 'antar', 'mahadasha', 'vimshottari', 'period'],
  'transits': ['transit', 'gochara', 'gochar'],
  'remedies': ['remedy', 'remedial', 'propitiat', 'worship', 'mantra', 'donation'],
  'ashtakavarga': ['ashtakavarga', 'ashtaka', 'bindu'],
  'shadbala': ['shadbala', 'strength', 'bala'],
  'nakshatras': ['nakshatra', 'asterism', 'star', 'constellation'],
  'signs': ['mesha', 'vrishabha', 'mithuna', 'karkataka', 'simha', 'kanya', 'tula', 'vrischika', 'dhanus', 'makara', 'kumbha', 'meena', 'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo', 'libra', 'scorpio', 'sagittar', 'capricorn', 'aquarius', 'pisces'],
};

const PLANET_KEYWORDS = {
  'sun': ['sun', 'surya', 'sūrya', 'ravi'],
  'moon': ['moon', 'candr', 'chandra', 'soma'],
  'mars': ['mars', 'mangal', 'kuja', 'angaraka'],
  'mercury': ['mercury', 'budh', 'budha'],
  'jupiter': ['jupiter', 'guru', 'brihaspati', 'bṛhaspati'],
  'venus': ['venus', 'shukr', 'śukr'],
  'saturn': ['saturn', 'shani', 'śani'],
  'rahu': ['rahu', 'rāhu', 'north node', 'dragon head'],
  'ketu': ['ketu', 'south node', 'dragon tail'],
};

const HOUSE_PATTERNS = [
  { house: 1, patterns: ['1st house', 'first house', 'tanu bhava', 'lagna', 'ascendant'] },
  { house: 2, patterns: ['2nd house', 'second house', 'dhan bhava', 'dhana'] },
  { house: 3, patterns: ['3rd house', 'third house', 'sahaj bhava'] },
  { house: 4, patterns: ['4th house', 'fourth house', 'bandhu bhava', 'sukha'] },
  { house: 5, patterns: ['5th house', 'fifth house', 'putr bhava', 'putra'] },
  { house: 6, patterns: ['6th house', 'sixth house', 'ari bhava', 'ripu'] },
  { house: 7, patterns: ['7th house', 'seventh house', 'yuvati bhava', 'kalatra'] },
  { house: 8, patterns: ['8th house', 'eighth house', 'randhr bhava', 'randhra'] },
  { house: 9, patterns: ['9th house', 'ninth house', 'dharm bhava', 'dharma', 'bhagya'] },
  { house: 10, patterns: ['10th house', 'tenth house', 'karm bhava', 'karma'] },
  { house: 11, patterns: ['11th house', 'eleventh house', 'labh bhava', 'labha'] },
  { house: 12, patterns: ['12th house', 'twelfth house', 'vyaya bhava'] },
];

// --- EXTRACT TEXT FROM PDF ---
async function extractPdfText(filePath) {
  const data = new Uint8Array(fs.readFileSync(filePath));
  const doc = await pdfjsLib.getDocument({ data }).promise;
  const pages = [];

  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    const text = content.items.map(item => item.str).join(' ');
    pages.push(text);
  }

  return pages;
}

// --- SPLIT INTO CHAPTERS ---
function splitIntoChapters(pages, book) {
  const fullText = pages.join('\n\n');
  const chapters = [];

  if (book === 'BPHS') {
    // BPHS chapters: "Ch. N. Title" — skip TOC (first ~3000 chars)
    // Find actual content start (after TOC, begins with verse numbers like "1-4.")
    const contentStart = fullText.indexOf('Ch. 1. The Creation');
    const textToProcess = contentStart > 0 ? fullText.substring(contentStart) : fullText;

    // Match "Ch. N. Title" but limit title to ~80 chars before next "Ch."
    const chapterPattern = /Ch\.\s*(\d+)\.\s*/g;
    let matches = [...textToProcess.matchAll(chapterPattern)];

    // Deduplicate: keep only the LAST occurrence of each chapter number
    // (first occurrences are from TOC, last is the actual chapter)
    const chapterMap = new Map();
    for (const m of matches) {
      const chNum = parseInt(m[1]);
      chapterMap.set(chNum, m);
    }
    matches = [...chapterMap.values()].sort((a, b) => a.index - b.index);

    for (let i = 0; i < matches.length; i++) {
      const chNum = parseInt(matches[i][1]);
      const startIdx = matches[i].index;
      const endIdx = i < matches.length - 1 ? matches[i + 1].index : textToProcess.length;
      const chText = textToProcess.substring(startIdx, endIdx).trim();

      // Extract title: text between "Ch. N." and first verse number
      const titleMatch = chText.match(/^Ch\.\s*\d+\.\s*([A-Za-zāūīśṛ\s,'-]+)/);
      const chTitle = titleMatch
        ? titleMatch[1].trim().replace(/\s+/g, ' ').substring(0, 80)
        : `Chapter ${chNum}`;

      if (chText.length > 100) {
        chapters.push({
          chapter: chNum,
          title: chTitle,
          text: chText,
        });
      }
    }
  } else {
    // Phaladeepika chapters: "ADHYAYA – N" or chapter headers
    const chapterPattern = /ADHYAYA\s*[–-]\s*([IVXLC]+)/gi;
    let matches = [...fullText.matchAll(chapterPattern)];

    if (matches.length === 0) {
      // Fallback: split by "Sloka 1" patterns after chapter indicators
      const altPattern = /(?:Chapter|Adhyaya)\s*(\d+)/gi;
      matches = [...fullText.matchAll(altPattern)];
    }

    for (let i = 0; i < matches.length; i++) {
      const chNumStr = matches[i][1];
      const chNum = romanToInt(chNumStr) || parseInt(chNumStr) || (i + 1);
      const startIdx = matches[i].index;
      const endIdx = i < matches.length - 1 ? matches[i + 1].index : fullText.length;
      const chText = fullText.substring(startIdx, endIdx).trim();

      if (chText.length > 100) {
        chapters.push({
          chapter: chNum,
          title: getPhalaChapterTitle(chNum),
          text: chText,
        });
      }
    }
  }

  return chapters;
}

function romanToInt(str) {
  const map = { I: 1, V: 5, X: 10, L: 50, C: 100 };
  let result = 0;
  const s = str.toUpperCase();
  for (let i = 0; i < s.length; i++) {
    const curr = map[s[i]];
    const next = map[s[i + 1]];
    if (!curr) return null;
    if (next && curr < next) {
      result -= curr;
    } else {
      result += curr;
    }
  }
  return result;
}

function getPhalaChapterTitle(num) {
  const titles = {
    1: 'Definitions', 2: 'Planets and Their Varieties', 3: 'Divisions of the Zodiac',
    4: 'Determination of Shadbalas', 5: 'Profession and Livelihood', 6: 'Yogas',
    7: 'Maharajayogas', 8: 'Effects of Planets in the 12 Bhavas',
    9: 'Effects of Signs as Lagna', 10: 'Kalatrabhava or the 7th House',
    11: 'Horoscopes of Women', 12: 'Issues or Children', 13: 'Length of Life',
    14: 'Diseases, Death, Past and Future Births', 15: 'Method of Studying Bhava Effects',
    16: 'General Effects of the 12 Bhavas', 17: 'Exit from the World',
    18: 'Conjunctions of Two Planets', 19: 'Dashas and Their Effects',
    20: 'Dashas of Bhava Lords and Bhuktis', 21: 'Sub-divisions of Dashas',
    22: 'Kalachakra Dasha', 23: 'Ashtakavarga',
    24: 'Ashtakavarga Effects from Horasara', 25: 'Upagrahas',
    26: 'Transits of Planets', 27: 'Ascetic Yogas', 28: 'Conclusion',
  };
  return titles[num] || `Chapter ${num}`;
}

// --- CHUNK CHAPTERS ---
function chunkChapter(chapter, book) {
  const chunks = [];
  const text = chapter.text;

  // Split by slokas/verses if present
  let sections;
  if (book === 'BPHS') {
    // BPHS uses numbered verses like "1-4." or "5."
    sections = text.split(/(?=\b\d{1,3}[-–]\d{1,3}\.\s|\b\d{1,3}\.\s(?=[A-Z]))/);
  } else {
    // Phaladeepika uses "Sloka N :"
    sections = text.split(/(?=Sloka\s+\d+)/i);
  }

  // Group small sections together (target ~300-500 words per chunk)
  let currentChunk = '';
  let currentVerseStart = '';
  let currentVerseEnd = '';
  let chunkIndex = 0;

  for (const section of sections) {
    const trimmed = section.trim();
    if (!trimmed || trimmed.length < 20) continue;

    // Extract verse number
    const verseMatch = trimmed.match(/^(?:Sloka\s+)?(\d+)[-–]?(\d+)?/);
    const verse = verseMatch ? verseMatch[1] : '';

    if (!currentVerseStart && verse) currentVerseStart = verse;
    if (verse) currentVerseEnd = verseMatch[2] || verse;

    currentChunk += ' ' + trimmed;

    // Create chunk when it reaches ~300-500 words
    const wordCount = currentChunk.split(/\s+/).length;
    if (wordCount >= 300 || section === sections[sections.length - 1]) {
      if (currentChunk.trim().length > 50) {
        chunkIndex++;
        const verseRange = currentVerseStart
          ? (currentVerseEnd && currentVerseEnd !== currentVerseStart
            ? `${currentVerseStart}-${currentVerseEnd}`
            : currentVerseStart)
          : `part${chunkIndex}`;

        const chunkText = currentChunk.trim()
          .replace(/\s+/g, ' ')
          .substring(0, 2000); // Max 2000 chars per chunk

        chunks.push({
          id: `${book.toLowerCase()}_ch${chapter.chapter}_v${verseRange}`,
          book: book,
          chapter: chapter.chapter,
          chapter_name: chapter.title,
          verse_range: verseRange,
          topics: extractTopics(chunkText),
          planets: extractPlanets(chunkText),
          houses: extractHouses(chunkText),
          text: chunkText,
        });
      }

      currentChunk = '';
      currentVerseStart = '';
      currentVerseEnd = '';
    }
  }

  return chunks;
}

function extractTopics(text) {
  const lower = text.toLowerCase();
  const topics = [];
  for (const [topic, keywords] of Object.entries(TOPIC_KEYWORDS)) {
    if (keywords.some(kw => lower.includes(kw))) {
      topics.push(topic);
    }
  }
  return topics;
}

function extractPlanets(text) {
  const lower = text.toLowerCase();
  const planets = [];
  for (const [planet, keywords] of Object.entries(PLANET_KEYWORDS)) {
    if (keywords.some(kw => lower.includes(kw))) {
      planets.push(planet);
    }
  }
  return planets;
}

function extractHouses(text) {
  const lower = text.toLowerCase();
  const houses = [];
  for (const { house, patterns } of HOUSE_PATTERNS) {
    if (patterns.some(p => lower.includes(p))) {
      houses.push(house);
    }
  }
  return [...new Set(houses)];
}

// --- MAIN ---
async function main() {
  console.log('VedAstro AI Knowledge Base Extractor');
  console.log('====================================\n');

  // Ensure output directory exists
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  const allChunks = [];

  // Process BPHS
  if (fs.existsSync(BPHS_PATH)) {
    console.log('Extracting BPHS...');
    const bphsPages = await extractPdfText(BPHS_PATH);
    console.log(`  ${bphsPages.length} pages extracted`);

    const bphsChapters = splitIntoChapters(bphsPages, 'BPHS');
    console.log(`  ${bphsChapters.length} chapters found`);

    let bphsChunks = [];
    for (const ch of bphsChapters) {
      const chunks = chunkChapter(ch, 'BPHS');
      bphsChunks.push(...chunks);
    }
    console.log(`  ${bphsChunks.length} chunks created`);

    fs.writeFileSync(
      path.join(OUTPUT_DIR, 'bphs_extracted.json'),
      JSON.stringify(bphsChunks, null, 2)
    );
    console.log('  Saved to knowledge_base/bphs_extracted.json\n');
    allChunks.push(...bphsChunks);
  } else {
    console.log('BPHS PDF not found at:', BPHS_PATH);
  }

  // Process Phaladeepika
  if (fs.existsSync(PHALA_PATH)) {
    console.log('Extracting Phaladeepika...');
    const phalaPages = await extractPdfText(PHALA_PATH);
    console.log(`  ${phalaPages.length} pages extracted`);

    const phalaChapters = splitIntoChapters(phalaPages, 'Phaladeepika');
    console.log(`  ${phalaChapters.length} chapters found`);

    let phalaChunks = [];
    for (const ch of phalaChapters) {
      const chunks = chunkChapter(ch, 'Phaladeepika');
      phalaChunks.push(...chunks);
    }
    console.log(`  ${phalaChunks.length} chunks created`);

    fs.writeFileSync(
      path.join(OUTPUT_DIR, 'phaladeepika_extracted.json'),
      JSON.stringify(phalaChunks, null, 2)
    );
    console.log('  Saved to knowledge_base/phaladeepika_extracted.json\n');
    allChunks.push(...phalaChunks);
  } else {
    console.log('Phaladeepika PDF not found at:', PHALA_PATH);
  }

  // Save combined
  fs.writeFileSync(
    path.join(OUTPUT_DIR, 'all_chunks.json'),
    JSON.stringify(allChunks, null, 2)
  );

  // Print summary
  console.log('====================================');
  console.log(`Total chunks: ${allChunks.length}`);
  console.log(`Saved to: knowledge_base/all_chunks.json`);

  // Topic distribution
  const topicCounts = {};
  allChunks.forEach(c => c.topics.forEach(t => {
    topicCounts[t] = (topicCounts[t] || 0) + 1;
  }));
  console.log('\nTopic distribution:');
  Object.entries(topicCounts)
    .sort((a, b) => b[1] - a[1])
    .forEach(([topic, count]) => console.log(`  ${topic}: ${count} chunks`));
}

main().catch(console.error);
