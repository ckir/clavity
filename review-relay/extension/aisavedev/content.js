'use strict';

// Guard against double-injection across multiple popup opens in the same tab
if (!window.__aiSaveDev) {
  window.__aiSaveDev = (() => {

    // ── Platform registry ─────────────────────────────────────────────────────
    // Order matters: more specific URL patterns must come before broader ones.
    const REGISTRY = [
      {
        id: 'oai-playground',
        test: u => /platform\.openai\.com\/(playground|assistants)/.test(u),
        scrape: scrapeOAIPlayground,
      },
      {
        id: 'chatgpt',
        test: u => /chat\.openai\.com|chatgpt\.com/.test(u),
        scrape: scrapeChatGPT,
      },
      {
        id: 'claude',
        test: u => /claude\.ai/.test(u),
        scrape: scrapeClaude,
      },
      {
        id: 'gemini',
        test: u => /gemini\.google\.com/.test(u),
        scrape: scrapeGemini,
      },
      {
        id: 'perplexity',
        test: u => /perplexity\.ai/.test(u),
        scrape: scrapePerplexity,
      },
      {
        id: 'copilot',
        // copilot.microsoft.com and Bing's /chat or /copilot path
        test: u => /copilot\.microsoft\.com|bing\.com\/(chat|copilot)/.test(u),
        scrape: scrapeCopilot,
      },
      {
        id: 'characterai',
        test: u => /character\.ai/.test(u),
        scrape: scrapeCharacterAI,
      },
      {
        id: 'hf-chat',
        test: u => /huggingface\.co\/chat/.test(u),
        scrape: scrapeHFChat,
      },
      {
        id: 'meta-ai',
        test: u => /meta\.ai|ai\.meta\.com/.test(u),
        scrape: scrapeMetaAI,
      },
      {
        id: 'grok',
        // grok.com (standalone) and x.com/i/grok (Twitter integration)
        test: u => /grok\.com|x\.com\/i\/grok|twitter\.com\/i\/grok/.test(u),
        scrape: scrapeGrok,
      },
      {
        id: 'duckduckgo-ai',
        test: u => /duck\.ai|duckduckgo\.com\/(duckchat|chat)/.test(u),
        scrape: scrapeDuckAI,
      },
      {
        id: 'qwen',
        test: u => /chat\.qwen\.ai|qwen\.ai/.test(u),
        scrape: scrapeQwen,
      },
    ];

    function detect() {
      const url = location.href;
      for (const entry of REGISTRY) {
        if (entry.test(url)) return entry;
      }
      return { id: 'generic', scrape: scrapeGeneric };
    }

    // ── HTML → Markdown ────────────────────────────────────────────────────────

    function htmlToMarkdown(root) {
      function walk(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          return node.textContent.replace(/[\t ]+/g, ' ');
        }
        if (node.nodeType !== Node.ELEMENT_NODE) return '';

        const tag = node.tagName.toLowerCase();

        if (['script', 'style', 'noscript', 'svg', 'button', 'form'].includes(tag)) return '';
        try {
          const cs = getComputedStyle(node);
          if (cs.display === 'none' || cs.visibility === 'hidden') return '';
        } catch (_) {}

        // Code blocks: bypass recursive walk to preserve raw indentation
        if (tag === 'pre') {
          const codeEl = node.querySelector('code');
          const langClass = (codeEl || node).getAttribute('class') || '';
          const lang = langClass.match(/language-(\w+)/)?.[1] ?? '';
          const text = (codeEl || node).textContent;
          return `\n\n\`\`\`${lang}\n${text.replace(/\n$/, '')}\n\`\`\`\n\n`;
        }

        const kids = Array.from(node.childNodes).map(walk).join('');

        switch (tag) {
          case 'p':         return `\n\n${kids.trim()}\n\n`;
          case 'br':        return '\n';
          case 'hr':        return '\n\n---\n\n';
          case 'strong':
          case 'b':         return `**${kids}**`;
          case 'em':
          case 'i':         return `*${kids}*`;
          case 'del':
          case 's':         return `~~${kids}~~`;
          case 'code':      return `\`${kids.replace(/`/g, '\\`')}\``;
          case 'h1':        return `\n\n# ${kids.trim()}\n\n`;
          case 'h2':        return `\n\n## ${kids.trim()}\n\n`;
          case 'h3':        return `\n\n### ${kids.trim()}\n\n`;
          case 'h4':        return `\n\n#### ${kids.trim()}\n\n`;
          case 'h5':        return `\n\n##### ${kids.trim()}\n\n`;
          case 'h6':        return `\n\n###### ${kids.trim()}\n\n`;
          case 'ul': {
            const items = Array.from(node.children).map(li => `- ${walk(li).trim()}`).join('\n');
            return `\n\n${items}\n\n`;
          }
          case 'ol': {
            const items = Array.from(node.children).map((li, i) => `${i + 1}. ${walk(li).trim()}`).join('\n');
            return `\n\n${items}\n\n`;
          }
          case 'li':        return kids;
          case 'a': {
            const href = node.getAttribute('href') || '';
            return href ? `[${kids}](${href})` : kids;
          }
          case 'img': {
            const alt = node.getAttribute('alt') || '';
            return alt ? `![${alt}]` : '';
          }
          case 'blockquote': {
            const inner = kids.trim().split('\n').map(l => `> ${l}`).join('\n');
            return `\n\n${inner}\n\n`;
          }
          case 'table':     return tableToMarkdown(node);
          case 'thead': case 'tbody': case 'tfoot':
          case 'tr': case 'th': case 'td':
            return kids;
          default:          return kids;
        }
      }

      function tableToMarkdown(table) {
        const rows = Array.from(table.querySelectorAll('tr'));
        if (!rows.length) return '';
        const cells = rows.map(row =>
          Array.from(row.querySelectorAll('th, td'))
            .map(cell => walk(cell).trim().replace(/\|/g, '\\|').replace(/\n+/g, ' '))
        );
        if (!cells[0]?.length) return '';
        const header = `| ${cells[0].join(' | ')} |`;
        const sep    = `| ${cells[0].map(() => '---').join(' | ')} |`;
        const body   = cells.slice(1).map(r => `| ${r.join(' | ')} |`).join('\n');
        return '\n\n' + [header, sep, body].filter(Boolean).join('\n') + '\n\n';
      }

      return walk(root).replace(/\n{3,}/g, '\n\n').trim();
    }

    // ── Shared helpers ────────────────────────────────────────────────────────

    // Try each selector in order; return elements from the first one that matches.
    function firstMatch(selectors) {
      for (const sel of selectors) {
        try {
          const els = [...document.querySelectorAll(sel)];
          if (els.length) return els;
        } catch (_) {}
      }
      return [];
    }

    // Build a sorted, deduplicated message list from two sets of element selectors.
    // Removes any element that is a descendant of another selected element (prevents
    // double-capturing nested containers on sites that match at multiple levels).
    // Returns null if either side is missing — callers must fall back to scrapeGeneric()
    // so the user always gets the full conversation, not just one role.
    function scrapeByTurns(humanSels, aiSels) {
      const humanEls = firstMatch(humanSels);
      const aiEls    = firstMatch(aiSels);
      if (!humanEls.length || !aiEls.length) return null;

      const pool = [
        ...humanEls.map(el => ({ el, label: 'Human' })),
        ...aiEls.map(el => ({ el, label: 'Assistant' })),
      ];

      const deduped = pool.filter(({ el }) =>
        !pool.some(({ el: other }) => other !== el && other.contains(el))
      );

      return deduped
        .sort((a, b) =>
          a.el.compareDocumentPosition(b.el) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1
        )
        .map(({ el, label }) => ({ label, content: htmlToMarkdown(el) }))
        .filter(m => m.content.trim());
    }

    function cleanTitle(raw, strip) {
      return raw.replace(strip, '').trim() || null;
    }

    // ── Platform scrapers ─────────────────────────────────────────────────────

    function scrapeChatGPT() {
      const title =
        cleanTitle(document.title, /^ChatGPT\s*[-–|]\s*/i) || 'ChatGPT Conversation';

      const messages = [];
      // data-message-author-role has been stable since mid-2024
      document.querySelectorAll('[data-message-author-role]').forEach(el => {
        const role    = el.getAttribute('data-message-author-role');
        const label   = role === 'user' ? 'Human' : 'Assistant';
        const content = htmlToMarkdown(el);
        if (content.trim()) messages.push({ label, content: content.trim() });
      });

      return messages.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeClaude() {
      const title =
        cleanTitle(document.title, /\s*[-–|]\s*Claude.*$/i) ||
        cleanTitle(document.title, /^Claude\s*[-–|]\s*/i) ||
        'Claude Conversation';

      const messages = scrapeByTurns(
        [
          '[data-testid="human-turn"]',
          '.human-turn',
          '[class*="HumanTurn"]',
          '[class*="human-message"]',
          '[class*="userMessage"]',
        ],
        [
          '[data-testid="ai-turn"]',
          '[data-testid="assistant-turn"]',
          '.ai-turn',
          '.assistant-turn',
          '[class*="AssistantTurn"]',
          '[class*="aiMessage"]',
          '[class*="assistantMessage"]',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeGemini() {
      const title =
        cleanTitle(document.title, /^Gemini\s*[-–|]\s*/i) ||
        cleanTitle(document.title, /\s*[-–|]\s*Gemini.*$/i) ||
        'Gemini Conversation';

      // Gemini renders turns as custom HTML elements <user-query> and <model-response>
      const messages = scrapeByTurns(
        [
          'user-query',
          '[data-testid="user-query"]',
          '[class*="userQuery"]',
          '[class*="UserQuery"]',
          '.query-content',
        ],
        [
          'model-response',
          '[data-testid="model-response"]',
          '[class*="modelResponse"]',
          '[class*="ModelResponse"]',
          '.response-container',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapePerplexity() {
      // Perplexity puts the question in the page title
      const title =
        cleanTitle(document.title, /\s*[-–|]\s*Perplexity.*$/i) ||
        'Perplexity Conversation';

      const messages = scrapeByTurns(
        [
          '[data-testid="user-message"]',
          '[class*="UserQuery"]',
          '[class*="userQuery"]',
          '[class*="queryText"]',
          '.query-text',
        ],
        [
          // Perplexity renders answers in `.prose` markdown containers
          '[data-testid="answer"]',
          '[class*="AnswerBody"]',
          '[class*="answerBody"]',
          '[class*="answerText"]',
          '.prose',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeCopilot() {
      const title =
        cleanTitle(document.title, /^(Microsoft\s*)?Copilot\s*[-–|]\s*/i) ||
        cleanTitle(document.title, /\s*[-–|]\s*(Microsoft\s*)?Copilot.*$/i) ||
        'Copilot Conversation';

      // ① Try known selector patterns across different Copilot interface versions
      const bySelectors = scrapeByTurns(
        [
          // Confirmed on copilot.microsoft.com (2025)
          '[data-content="user-message"]',
          // Older / alternate Copilot layouts
          '[data-testid="user-message"]',
          '[data-testid*="user"]',
          '[class*="userMessage"]',
          '[class*="UserMessage"]',
          '[class*="user-message"]',
          '[class*="HumanMessage"]',
          '[class*="humanMessage"]',
          // Bing Chat / cib web components
          'cib-message[type="user"]',
          '[role="presentation"][class*="user"]',
        ],
        [
          // Confirmed on copilot.microsoft.com (2025)
          '[data-content="ai-message"]',
          '[data-testid="ai-message"]',
          // Other Copilot / Bing Chat layout variants
          '[data-content="assistant-message"]',
          '[data-content="bot-message"]',
          '[data-content="copilot-message"]',
          '[data-content="response"]',
          '[data-testid="response-message"]',
          '[data-testid="bot-message"]',
          '[class*="botMessage"]',
          '[class*="BotMessage"]',
          '[class*="bot-message"]',
          '[class*="CopilotMessage"]',
          '[class*="copilotMessage"]',
          'cib-message[type="bot"]',
          'cib-message-group',
        ]
      );
      if (bySelectors?.length) return { title, messages: bySelectors };

      // ② Author-heading approach: Copilot labels every turn with a visible
      // author name ("You" for user, "Copilot" / "Microsoft Copilot" for AI).
      // Find those labels, walk up to the turn container, and classify.
      const authorEls = [...document.querySelectorAll(
        'h1,h2,h3,h4,h5,h6,p,span,div,strong,b'
      )].filter(el => {
        const t = el.textContent.trim();
        return /^(you|copilot|microsoft\s+copilot|bing\s+chat)$/i.test(t) &&
               el.children.length === 0; // leaf text node only
      });

      if (authorEls.length >= 2) {
        const turns = authorEls.map(authorEl => {
          const isUser = /^you$/i.test(authorEl.textContent.trim());

          // Walk up until we find a container big enough to be the turn wrapper
          let container = authorEl.parentElement;
          for (let i = 0; i < 6 && container?.parentElement; i++) {
            if (container.children.length >= 2 || container.clientHeight > 60) break;
            container = container.parentElement;
          }

          return {
            label: isUser ? 'Human' : 'Assistant',
            content: htmlToMarkdown(container || authorEl.parentElement),
          };
        }).filter(m => m.content.trim().length > 5);

        const hasHuman = turns.some(t => t.label === 'Human');
        const hasAI    = turns.some(t => t.label === 'Assistant');
        if (hasHuman && hasAI) return { title, messages: turns };
      }

      return scrapeGeneric();
    }

    function scrapeCharacterAI() {
      // Use the character name from the page heading if available
      const charName =
        document.querySelector('[class*="CharacterName"], [class*="character-name"], h1')
          ?.textContent?.trim() || 'Character';

      const rawTitle = document.title.replace(/\s*[-–|]\s*Character\.AI.*$/i, '').trim();
      const title    = rawTitle || `${charName} — Character AI`;

      const messages = scrapeByTurns(
        [
          '[data-testid="user-message"]',
          '[class*="humanBubble"]',
          '[class*="HumanBubble"]',
          '[class*="user-message"]',
          '[class*="UserMessage"]',
        ],
        [
          '[data-testid="ai-message"]',
          '[class*="charBubble"]',
          '[class*="CharBubble"]',
          '[class*="ai-message"]',
          '[class*="CharacterMessage"]',
          '[class*="characterMessage"]',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeOAIPlayground() {
      // OpenAI Playground — Chat and Assistants modes both show role-labelled blocks
      const title = 'OpenAI Playground — ' + new Date().toLocaleString();
      const messages = [];

      // Chat playground: each message block has a role selector and content area
      const blocks = firstMatch([
        '[data-testid="playground-message"]',
        '[class*="PlaygroundMessage"]',
        '[class*="playgroundMessage"]',
        '[class*="message-block"]',
        '.message-block',
      ]);

      if (blocks.length) {
        blocks.forEach(block => {
          // Role is usually displayed as a label/tag within the block
          const roleEl = block.querySelector('[class*="role"], [class*="Role"], [data-role]');
          const role   = (roleEl?.textContent?.trim() || roleEl?.getAttribute('data-role') || 'message')
            .replace(/^(system|user|assistant)$/i, r => ({ system: 'System', user: 'Human', assistant: 'Assistant' }[r.toLowerCase()] || r));
          const content = htmlToMarkdown(block);
          if (content.trim()) messages.push({ label: role, content: content.trim() });
        });
      }

      // Fallback: look for textarea-per-role sections (legacy Completions playground)
      if (!messages.length) {
        document.querySelectorAll('.playground-section, [class*="PlaygroundSection"]').forEach(section => {
          const label = section.querySelector('label, [class*="Label"]')?.textContent?.trim() || 'Message';
          const text  = section.querySelector('textarea')?.value?.trim() || htmlToMarkdown(section);
          if (text.trim()) messages.push({ label, content: text.trim() });
        });
      }

      return messages.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeHFChat() {
      // huggingface.co/chat — the open-source HuggingChat interface
      const title =
        cleanTitle(document.title, /\s*[-–|]\s*HuggingChat.*$/i) ||
        cleanTitle(document.title, /^HuggingChat\s*[-–|]\s*/i) ||
        'HuggingFace Chat';

      const messages = scrapeByTurns(
        [
          '[data-testid="user-message"]',
          '[class*="from-human"]',
          '[class*="fromHuman"]',
          '[class*="user-message"]',
          '[class*="UserMessage"]',
        ],
        [
          '[data-testid="assistant-message"]',
          '[class*="from-assistant"]',
          '[class*="fromAssistant"]',
          '[class*="assistant-message"]',
          '[class*="AssistantMessage"]',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeMetaAI() {
      const title =
        cleanTitle(document.title, /\s*[-–|]\s*Meta AI.*$/i) ||
        cleanTitle(document.title, /^Meta AI\s*[-–|]\s*/i) ||
        'Meta AI Conversation';

      const messages = scrapeByTurns(
        [
          '[data-testid="user-message"]',
          '[class*="UserMessage"]',
          '[class*="userMessage"]',
          '[class*="user-bubble"]',
          '[class*="HumanMessage"]',
        ],
        [
          '[data-testid="ai-message"]',
          '[data-testid="assistant-message"]',
          '[class*="AiMessage"]',
          '[class*="aiMessage"]',
          '[class*="MetaMessage"]',
          '[class*="AssistantMessage"]',
          '[class*="BotMessage"]',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeGrok() {
      const title =
        cleanTitle(document.title, /\s*[-–|]\s*Grok.*$/i) ||
        cleanTitle(document.title, /^Grok\s*[-–|]\s*/i) ||
        'Grok Conversation';

      const messages = scrapeByTurns(
        [
          // grok.com standalone + x.com embedding both use data-testid patterns
          '[data-testid="userMessage"]',
          '[data-testid="user-message"]',
          '[class*="UserMessage"]',
          '[class*="userMessage"]',
          '[class*="HumanTurn"]',
        ],
        [
          '[data-testid="grokMessage"]',
          '[data-testid="bot-message"]',
          '[data-testid="assistant-message"]',
          '[class*="GrokMessage"]',
          '[class*="grokMessage"]',
          '[class*="BotMessage"]',
          '[class*="AssistantMessage"]',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeDuckAI() {
      const title =
        cleanTitle(document.title, /\s*[-–|]\s*DuckDuckGo.*$/i) ||
        cleanTitle(document.title, /^DuckDuckGo\s*[-–|]\s*/i) ||
        'DuckDuckGo AI Chat';

      const messages = scrapeByTurns(
        [
          // User bubble identified by its unique chat-tail SVG (w=12, h=21); the
          // direct-child combinator targets the inner wrapper (p + svg-container).
          'div:has(> div > svg[width="12"][height="21"])',
        ],
        [
          // AI response wrapper carries data-dark-theme on its content container.
          '[data-dark-theme]',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeQwen() {
      const title =
        cleanTitle(document.title, /\s*[-–|]\s*Qwen.*$/i) ||
        cleanTitle(document.title, /^Qwen\s*[-–|]\s*/i) ||
        'Qwen Conversation';

      // Qwen (chat.qwen.ai) uses React with message containers that have role-based attributes.
      // Try multiple selector strategies since class names are hashed.
      const messages = scrapeByTurns(
        [
          // User message selectors - Qwen labels user turns
          '[data-testid="user-turn"]',
          '[class*="userMessage"]',
          '[class*="UserMessage"]',
          '[class*="user-message"]',
          '[class*="UserMessageContent"]',
          '[class*="userBubble"]',
          '[class*="UserBubble"]',
          // React component markers
          'div[class*="message"][class*="user"]',
        ],
        [
          // AI response selectors - Qwen/Qwen model responses
          '[data-testid="assistant-turn"]',
          '[data-testid="ai-turn"]',
          '[class*="assistantMessage"]',
          '[class*="AssistantMessage"]',
          '[class*="ai-message"]',
          '[class*="AiMessage"]',
          '[class*="modelMessage"]',
          '[class*="ModelMessage"]',
          '[class*="responseContainer"]',
          '[class*="ResponseContainer"]',
          // Markdown/content areas in AI responses
          '[class*="markdown"]',
          '[class*="prose"]',
          // React component markers
          'div[class*="message"][class*="assistant"]',
          'div[class*="message"][class*="model"]',
          'div[class*="message"][class*="ai"]',
        ]
      );

      return messages?.length ? { title, messages } : scrapeGeneric();
    }

    function scrapeGeneric() {
      const title = document.title.trim() || 'Conversation';

      // ① Aria-label based role detection — more reliable than class names
      const ariaMessages = scrapeByTurns(
        ['[aria-label*="You said" i]', '[aria-label*="your message" i]'],
        ['[aria-label*="response" i]',  '[aria-label*="AI" i]', '[aria-label*="assistant" i]', '[aria-label*="bot" i]']
      );
      if (ariaMessages?.length) return { title, messages: ariaMessages };

      // ② Keyword scan of common message-like containers
      // Looks at class names, aria-labels, and data attributes for role hints.
      const candidateSelectors = [
        '[class*="message"]:not([class*="input"]):not([class*="compose"]):not([class*="editor"])',
        '[class*="Message"]:not([class*="Input"]):not([class*="Compose"]):not([class*="Editor"])',
        '[class*="chat-item"]', '[class*="ChatItem"]',
        '[class*="turn"]',
        'article',
      ];

      for (const sel of candidateSelectors) {
        try {
          const els = [...document.querySelectorAll(sel)];
          if (els.length < 2) continue;

          const labeled = els.flatMap(el => {
            const hint = [
              el.className,
              el.getAttribute('aria-label')             ?? '',
              el.getAttribute('data-role')              ?? '',
              el.getAttribute('data-author')            ?? '',
              el.getAttribute('data-sender')            ?? '',
              el.getAttribute('data-message-author-role') ?? '',
            ].join(' ').toLowerCase();

            if (/\b(user|human|you|query|member)\b/.test(hint))
              return [{ el, label: 'Human' }];
            if (/\b(ai|assistant|bot|response|gpt|claude|gemini|grok|meta|copilot|character)\b/.test(hint))
              return [{ el, label: 'Assistant' }];
            return [];
          });

          const hasHuman     = labeled.some(m => m.label === 'Human');
          const hasAssistant = labeled.some(m => m.label === 'Assistant');
          if (!hasHuman || !hasAssistant) continue;

          // Deduplicate ancestors, same as scrapeByTurns
          const deduped = labeled.filter(({ el }) =>
            !labeled.some(({ el: other }) => other !== el && other.contains(el))
          );

          const messages = deduped
            .sort((a, b) =>
              a.el.compareDocumentPosition(b.el) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1
            )
            .map(({ el, label }) => ({ label, content: htmlToMarkdown(el) }))
            .filter(m => m.content.trim().length > 5);

          if (messages.length >= 2) return { title, messages };
        } catch (_) {}
      }

      // ③ Last resort: dump the main content area as a single block
      const containerCandidates = [
        '[role="log"]',
        '[aria-label*="conversation" i]',
        '[aria-label*="chat" i]',
        'main', '[role="main"]', '#main', '#content',
      ];
      let container = null;
      for (const sel of containerCandidates) {
        const el = document.querySelector(sel);
        if (el) { container = el; break; }
      }
      if (!container) container = document.body;

      return { title, messages: [{ label: 'Conversation', content: htmlToMarkdown(container) }] };
    }

    // ── Markdown assembly ──────────────────────────────────────────────────────

    // AiSaveDev: every turn is preceded by a marker line carrying a random per-save nonce, and the
    // file ends with an end marker. A reply's own text can contain "## Assistant" or "---" (AiSave's
    // turn heading and separator), but it cannot contain this file's nonce, which is generated after
    // the page text exists. Consumers (review-relay) split on the markers when `format: aisave-dev/1`.
    //   <!-- aisave:<nonce> turn=<n> role=<human|assistant|...> -->
    //   <!-- aisave:<nonce> end -->
    function newNonce() {
      const bytes = new Uint8Array(6);
      crypto.getRandomValues(bytes);
      return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
    }

    function buildMarkdown(title, messages, platform) {
      const date      = new Date().toISOString().split('T')[0];
      const safeTitle = title.replace(/"/g, '\\"');
      const nonce     = newNonce();

      const frontmatter = [
        '---',
        `title: "${safeTitle}"`,
        `date: ${date}`,
        `url: ${location.href}`,
        `platform: ${platform}`,
        'format: aisave-dev/1',
        `nonce: ${nonce}`,
        '---', '', '',
      ].join('\n');

      const body = `# ${title}\n\n` +
        messages
          .map(({ label, content }, i) =>
            `<!-- aisave:${nonce} turn=${i + 1} role=${String(label).toLowerCase()} -->\n## ${label}\n\n${content}`)
          .join('\n\n---\n\n') +
        `\n\n<!-- aisave:${nonce} end -->\n`;

      return frontmatter + body;
    }

    // ── Public API ─────────────────────────────────────────────────────────────

    return {
      scrape() {
        const { id, scrape } = detect();
        let scraped;
        try {
          scraped = scrape();
        } catch (err) {
          return { error: err.message };
        }
        const { title, messages } = scraped;
        if (!messages?.length) return { error: 'No messages found on this page.' };
        return { title, markdown: buildMarkdown(title, messages, id) };
      },
    };

  })();
}
