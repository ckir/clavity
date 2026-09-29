'use strict';

// CONTRACT TEST (spec section 5). The REAL content.js, run on fixtures/chatgpt-synthetic.html with the
// nonce and date pinned, must produce fixtures/expected-aisave-dev.md BYTE FOR BYTE. review-relay's
// Pester suite parses the SAME golden file (scripts/tests/review-relay-lib.Tests.ps1, Describe
// 'aisave-dev/1 golden capture (the extension contract)'), so a change on either side of the format
// turns one of the two red.
// After a DELIBERATE format change only: `node regen-golden.js`, then re-run BOTH suites.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const { GOLDEN_PATH, scrapeSyntheticDeterministic } = require('./helpers');

test('the synthetic ChatGPT page produces the golden aisave-dev/1 capture byte for byte', () => {
  const { error, markdown } = scrapeSyntheticDeterministic();
  assert.equal(error, undefined);
  assert.equal(markdown, fs.readFileSync(GOLDEN_PATH, 'utf8'));
});

test('the golden file on disk is LF-only (the .gitattributes eol=lf rule held on checkout)', () => {
  assert.equal(fs.readFileSync(GOLDEN_PATH).includes(0x0d), false,
    'expected-aisave-dev.md contains a CR byte - check .gitattributes for review-relay/extension/test/fixtures/**');
});
