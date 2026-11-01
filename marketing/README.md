# Clavity Marketing Creative Specs & Campaign Copy Staging

Central inventory, creative briefs, specification manifests, and draft copy for Clavity marketing campaigns.

## 1. Directory Structure

```text
marketing/
├── README.md                          # Asset inventory & specifications
├── assets/                            # Creative production specifications
│   ├── logo/spec.md                   # Vector & raster logo variants
│   ├── screenshots/spec.md            # Terminal screenshots & recording captures
│   ├── videos/spec.md                 # 60s & long-form video briefs
│   ├── diagrams/spec.md               # Architecture & workflow visual assets
│   └── social/spec.md                 # Social cards (OG, banners, avatars)
└── campaigns/                         # Staged launch copy drafts
    ├── guidelines.md                  # Campaign messaging rules & guidelines
    ├── beta-announcement.md           # Universal public beta announcement
    ├── beta-tester-invitation.md      # Direct tester outreach email
    ├── hacker-news/show-hn.md         # Show HN submission copy
    ├── reddit/post.md                 # r/ClaudeAI & r/programming post copy
    ├── product-hunt/listing.md        # Product Hunt launch copy
    ├── linkedin/announcement.md       # LinkedIn technical post
    └── x/thread.md                    # X (Twitter) launch thread
```

## 2. Comprehensive Asset Inventory

| Asset Name | Target Dimensions | Format | Purpose | Status |
|---|---|---|---|---|
| `clavity.svg` | Scalable Vector | SVG | Primary brand vector logo | **Available** (`site/assets/clavity.svg`) |
| `banner.webp` | 1670 x 941 | WebP | Hero glowing bridge illustration | **Available** (`site/assets/banner.webp`) |
| `og.jpg` | 1200 x 630 | JPEG | OpenGraph social preview card | **Available** (`site/assets/og.jpg`) |
| `profile.png` | 96 x 96 | PNG | Brand emblem / avatar | **Available** (`site/assets/profile.png`) |
| `terminal-split-screenshot` | 1920 x 1080 | PNG (24-bit) | Split terminal screenshot (Claude vs Antigravity) | *Staged Specification* |
| `capstone-diff-screenshot` | 1920 x 1080 | PNG (24-bit) | Showing before/after code review fold | *Staged Specification* |
| `terminal-split-demo-short` | 1080 x 1920 & 1920 x 1080 | MP4 (H.264) | 60-second video demo showing pairing | *Scripted Specification* |
| `architecture-diagram` | 1600 x 900 | SVG / PNG | Language Server MCP stdio protocol diagram | *Mermaid Drafted* |
| `review-stages-diagram` | 1600 x 600 | SVG / PNG | 6-stage lifecycle visual diagram | *HTML/CSS Implemented* |
| `x-header-banner` | 1500 x 500 | PNG | X (Twitter) profile header | *Staged Specification* |

## 3. Brand Identity Rules

- **Palette Dominance:** Background dark navy (`#020713`), Driver orange (`#ff4b18`), Peer cyan (`#00cfff`).
- **Typography:** Modern clean sans-serif (system-ui) paired with crisp monospaced code (SF Mono, Menlo, Consolas).
- **Voice:** Honest, technical, precise, zero AI hype words (never use "revolutionary", "seamless", "blazingly fast", or fabricated claims).
