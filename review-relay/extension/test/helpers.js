'use strict';

// Shared helpers for the AiSaveDev offline tests. content.js is NEVER modified for testability: the real
// source is evaluated inside a jsdom window. For byte-stable output, the window's crypto.getRandomValues
// (content.js newNonce) and Date (content.js buildMarkdown) are replaced BEFORE the source is evaluated.

const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const CONTENT_JS_PATH = path.join(__dirname, '..', 'aisavedev', 'content.js');
const SYNTHETIC_PATH = path.join(__dirname, 'fixtures', 'chatgpt-synthetic.html');
const GOLDEN_PATH = path.join(__dirname, 'fixtures', 'expected-aisave-dev.md');
const SYNTHETIC_URL = 'https://chatgpt.com/c/00000000-0000-0000-0000-000000000000';
const FIXED_NONCE_BYTES = [0x9f, 0x2c, 0x41, 0xd7, 0xe0, 0xb3]; // nonce 9f2c41d7e0b3
const FIXED_TIME_MS = Date.UTC(2026, 8, 29, 12, 0, 0);          // date 2026-09-29

// Evaluates the unmodified content.js inside the given jsdom window and returns window.__aiSaveDev.
function installAiSaveDev(window) {
  if (typeof window.crypto?.getRandomValues !== 'function') {
    const nodeCrypto = require('node:crypto');
    window.crypto = window.crypto || {};
    window.crypto.getRandomValues = arr => nodeCrypto.webcrypto.getRandomValues(arr);
  }
  window.eval(fs.readFileSync(CONTENT_JS_PATH, 'utf8'));
  if (!window.__aiSaveDev) {
    throw new Error('content.js did not install window.__aiSaveDev');
  }
  return window.__aiSaveDev;
}

// Pins the two nondeterministic inputs content.js reads through the window's globals.
function pinNonceAndDate(window) {
  Object.defineProperty(window, 'crypto', {
    configurable: true,
    value: { getRandomValues: arr => { arr.set(FIXED_NONCE_BYTES.slice(0, arr.length)); return arr; } },
  });
  const RealDate = window.Date;
  window.Date = class extends RealDate {
    constructor(...args) { if (args.length === 0) { super(FIXED_TIME_MS); } else { super(...args); } }
    static now() { return FIXED_TIME_MS; }
  };
}

// Scrapes fixtures/chatgpt-synthetic.html with the nonce and date pinned. Returns { error, markdown }.
function scrapeSyntheticDeterministic() {
  const html = fs.readFileSync(SYNTHETIC_PATH, 'utf8');
  const dom = new JSDOM(html, { url: SYNTHETIC_URL, runScripts: 'outside-only' });
  pinNonceAndDate(dom.window);
  const result = installAiSaveDev(dom.window).scrape();
  dom.window.close();
  return result;
}

// Returns an ordered array of { nonce, turn, role, index, markerLine } for every turn marker.
function extractTurnMarkers(markdown) {
  const re = /<!-- aisave:([0-9a-f]{12}) turn=(\d+) role=(\w+) -->/g;
  const out = [];
  let m;
  while ((m = re.exec(markdown)) !== null) {
    out.push({ nonce: m[1], turn: Number(m[2]), role: m[3], index: m.index, markerLine: m[0] });
  }
  return out;
}

// Returns { nonce, index, markerLine } for the end marker, or null.
function extractEndMarker(markdown) {
  const m = markdown.match(/<!-- aisave:([0-9a-f]{12}) end -->/);
  if (!m) return null;
  return { nonce: m[1], index: m.index, markerLine: m[0] };
}

module.exports = {
  CONTENT_JS_PATH,
  GOLDEN_PATH,
  installAiSaveDev,
  scrapeSyntheticDeterministic,
  extractTurnMarkers,
  extractEndMarker,
};
