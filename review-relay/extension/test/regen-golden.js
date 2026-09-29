'use strict';

// Regenerates fixtures/expected-aisave-dev.md from the real content.js. Run ONLY after a deliberate format
// change, then review the diff by eye and re-run both the node and the Pester suites.
const fs = require('node:fs');
const { GOLDEN_PATH, scrapeSyntheticDeterministic } = require('./helpers');

const { error, markdown } = scrapeSyntheticDeterministic();
if (error) { console.error(`scrape failed: ${error}`); process.exit(1); }
fs.writeFileSync(GOLDEN_PATH, markdown);
console.log(`wrote ${GOLDEN_PATH} (${Buffer.byteLength(markdown)} bytes)`);
