'use strict';

// Offline regression test for the aisave-dev/1 writer (newNonce + buildMarkdown) alone,
// using a tiny synthetic ChatGPT-like DOM. Does NOT modify content.js: it evaluates the
// real source in a minimal jsdom window and drives it through the public scrape() API,
// exactly like scrape.test.js does against the real fixture.

const test = require('node:test');
const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');

const { installAiSaveDev, extractTurnMarkers, extractEndMarker } = require('./helpers');

const SYNTHETIC_URL = 'https://chatgpt.com/c/00000000-0000-0000-0000-000000000000';

// The assistant's own reply contains a paragraph, then an <hr> and an <h2>Assistant</h2>
// heading, then another paragraph. htmlToMarkdown() renders <hr> as "\n\n---\n\n" and <h2>
// as "\n\n## <text>\n\n", so after the outer "\n{3,}" -> "\n\n" collapse this reply's own
// markdown content contains the literal substring "\n\n---\n\n## Assistant\n\n" - a fake
// turn separator + heading baked into the reply text itself, not a real turn boundary.
// No whitespace between the assistant's inner tags: an indented multi-line source would
// insert whitespace-only text nodes between <p>/<hr>/<h2> that survive htmlToMarkdown's
// text-node handling (it collapses tabs/spaces but keeps newlines) and break the exact
// substring below - real ChatGPT markup is unindented for the same reason.
const SYNTHETIC_HTML = `<!doctype html>
<html>
<head><title>Fake heading regression</title></head>
<body>
<div data-message-author-role="user"><p>Please review this diff.</p></div>
<div data-message-author-role="assistant"><p>Sure, here it is.</p><hr><h2>Assistant</h2><p>This fake heading is embedded in my own reply text, not a real second turn.</p></div>
</body>
</html>`;

function scrapeSynthetic() {
  const dom = new JSDOM(SYNTHETIC_HTML, { url: SYNTHETIC_URL, runScripts: 'outside-only' });
  const aiSaveDev = installAiSaveDev(dom.window);
  const result = aiSaveDev.scrape();
  dom.window.close();
  return result;
}

test('a reply whose own text contains "\\n\\n---\\n\\n## Assistant\\n\\n" still yields ' +
     'exactly 2 turn markers, and the fake heading stays inside turn 2\'s content', () => {
  const { error, markdown } = scrapeSynthetic();
  assert.equal(error, undefined);
  assert.equal(typeof markdown, 'string');

  // Precondition: prove the fake heading text is actually present verbatim, so this test
  // would fail loudly if htmlToMarkdown's rendering ever changes shape.
  assert.ok(
    markdown.includes('\n\n---\n\n## Assistant\n\n'),
    'fixture setup assumption failed: expected the assistant\'s own content to render the fake separator+heading'
  );

  const markers = extractTurnMarkers(markdown);
  assert.equal(markers.length, 2, `expected exactly 2 turn markers, found ${markers.length}`);
  assert.equal(markers[0].turn, 1);
  assert.equal(markers[0].role, 'human');
  assert.equal(markers[1].turn, 2);
  assert.equal(markers[1].role, 'assistant');

  const endMarker = extractEndMarker(markdown);
  assert.ok(endMarker, 'expected an end marker');

  // The fake heading text must land strictly inside turn 2's content span (after the
  // turn=2 marker, before the end marker) - i.e. it was never treated as a real boundary.
  const fakeHeadingIndex = markdown.indexOf('\n\n---\n\n## Assistant\n\n');
  assert.ok(
    fakeHeadingIndex > markers[1].index,
    'fake heading must appear after the real turn=2 marker'
  );
  assert.ok(
    fakeHeadingIndex < endMarker.index,
    'fake heading must appear before the end marker'
  );
});
