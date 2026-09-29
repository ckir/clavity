'use strict';

const saveBtn = document.getElementById('save-btn');
const statusEl = document.getElementById('status');
const badgeEl  = document.getElementById('platform-badge');

let activeTab = null;

// Must mirror the REGISTRY order in content.js (more specific first)
const PLATFORM_RULES = [
  { pattern: /platform\.openai\.com\/(playground|assistants)/, id: 'oai-playground' },
  { pattern: /chat\.openai\.com|chatgpt\.com/,                 id: 'chatgpt' },
  { pattern: /claude\.ai/,                                     id: 'claude' },
  { pattern: /gemini\.google\.com/,                            id: 'gemini' },
  { pattern: /perplexity\.ai/,                                 id: 'perplexity' },
  { pattern: /copilot\.microsoft\.com|bing\.com\/(chat|copilot)/, id: 'copilot' },
  { pattern: /character\.ai/,                                  id: 'characterai' },
  { pattern: /huggingface\.co\/chat/,                          id: 'hf-chat' },
  { pattern: /meta\.ai|ai\.meta\.com/,                         id: 'meta-ai' },
  { pattern: /grok\.com|x\.com\/i\/grok|twitter\.com\/i\/grok/, id: 'grok' },
  { pattern: /duck\.ai|duckduckgo\.com\/(duckchat|chat)/,       id: 'duckduckgo-ai' },
  { pattern: /chat\.qwen\.ai|qwen\.ai/,                         id: 'qwen' },
];

const PLATFORM_LABELS = {
  'chatgpt':       'ChatGPT',
  'claude':        'Claude.ai',
  'gemini':        'Gemini',
  'perplexity':    'Perplexity',
  'copilot':       'Copilot',
  'characterai':   'Character.AI',
  'oai-playground':'OAI Playground',
  'hf-chat':       'HuggingFace Chat',
  'meta-ai':       'Meta AI',
  'grok':          'Grok',
  'duckduckgo-ai': 'DuckDuckGo AI',
  'qwen':          'Qwen Studio',
  'generic':       'Generic site',
  'unsupported':   'Unsupported',
};

function detectPlatform(url = '') {
  if (/^(chrome|about|moz-extension|edge):/.test(url)) return 'unsupported';
  for (const { pattern, id } of PLATFORM_RULES) {
    if (pattern.test(url)) return id;
  }
  return 'generic';
}

async function init() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  activeTab = tab;

  const platform = detectPlatform(tab.url);
  badgeEl.textContent = PLATFORM_LABELS[platform] ?? platform;
  badgeEl.className   = `badge ${platform}`;

  if (platform === 'unsupported') {
    badgeEl.className = 'badge error';
    showStatus('Browser pages cannot be scraped.', 'error');
  } else {
    saveBtn.disabled = false;
  }
}

saveBtn.addEventListener('click', async () => {
  saveBtn.disabled = true;
  showStatus('Reading conversation…', 'info');

  try {
    // Inject content script — idempotent (content.js guards against double-run)
    await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      files: ['content.js'],
    });

    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: activeTab.id },
      func: () => window.__aiSaveDev?.scrape() ?? null,
    });

    if (!result) throw new Error('Content script did not respond.');
    if (result.error) throw new Error(result.error);
    if (!result.markdown) throw new Error('No conversation content found.');

    const date     = new Date().toISOString().split('T')[0];
    const filename = `${date}_${sanitizeFilename(result.title)}.md`;
    const blob     = new Blob([result.markdown], { type: 'text/markdown;charset=utf-8' });
    const url      = URL.createObjectURL(blob);

    await chrome.downloads.download({ url, filename, saveAs: false });
    URL.revokeObjectURL(url);

    showStatus(`Saved: ${filename}`, 'success');
  } catch (err) {
    showStatus(err.message || 'Unexpected error.', 'error');
  } finally {
    saveBtn.disabled = false;
  }
});

function sanitizeFilename(name) {
  return (name || 'conversation')
    .replace(/[<>:"/\\|?*\x00-\x1f]/g, '-')
    .replace(/\s+/g, '_')
    .replace(/-{2,}/g, '-')
    .trim()
    .slice(0, 80) || 'conversation';
}

function showStatus(text, type) {
  statusEl.textContent = text;
  statusEl.className   = `status ${type}`;
}

init();
