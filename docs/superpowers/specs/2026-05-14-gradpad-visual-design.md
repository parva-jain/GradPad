# GradPad Visual Design Spec

**Date:** 2026-05-14
**Status:** Approved
**Scope:** Visual design language, component patterns, and v0.dev prompts for every page of the GradPad frontend.

This spec is the design authority that all component generation (v0.dev and frontend-design skill) must follow. Any AI tool generating UI for GradPad should be given the relevant section of this doc as context.

---

## Design Language

**Style:** Glassmorphism — frosted glass cards on a warm near-black background with ambient amber glow.

**Personality:** Premium DeFi product. Serious and data-forward, but with warmth from the amber palette. Not a meme site. Feels trustworthy enough for real money, distinctive enough to remember.

**Reference:** The approved mockup lives at `.superpowers/brainstorm/*/content/full-mockup.html`.

---

## Color Tokens

```
Background         #0c0a06          Near-black, warm-tinted
Surface card       rgba(255,255,255,0.025)   Glassmorphism card fill
Surface hover      rgba(255,255,255,0.04)    Card hover state
Border default     rgba(255,255,255,0.07)    Card border at rest
Border amber       rgba(251,191,36,0.15)     Amber-tinted border (stat cards)
Border hover       rgba(251,191,36,0.2)      Card border on hover

Accent primary     #fbbf24          Amber — badges, labels, connect btn
Accent mid         #f59e0b          Amber — gradient midpoint
Accent dark        #d97706          Amber — gradient start, progress fill
Accent gradient    linear-gradient(90deg, #d97706, #fbbf24)

Success            #34d399          Emerald — graduated state
Success bg         rgba(16,185,129,0.12)
Success border     rgba(16,185,129,0.2)

Text primary       #ffffff
Text secondary     #9ca3af
Text muted         #6b7280
Text amber         #fbbf24          Stat labels, active nav

Navbar bg          rgba(12,10,6,0.8)  + backdrop-filter: blur(20px)
Ambient glow       radial-gradient(ellipse 60% 40% at 20% 0%, rgba(251,191,36,0.07) 0%, transparent 60%)
                   radial-gradient(ellipse 40% 30% at 80% 100%, rgba(251,191,36,0.04) 0%, transparent 60%)
```

---

## Typography

**Font:** Plus Jakarta Sans (Google Fonts)
**Import:** `@import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap')`

| Role | Weight | Size | Letter-spacing |
|---|---|---|---|
| Logo / Hero | 800 | 17–22px | -0.3px to -0.5px |
| Page title | 800 | 22px | -0.3px |
| Card title | 700 | 15px | default |
| Stat value | 800 | 20px | -0.5px |
| Body | 400–500 | 13–14px | default |
| Label (uppercase) | 600 | 10px | 0.5px |
| Badge | 700 | 9px | 0.5px |

**Logo treatment:** amber gradient text — `background: linear-gradient(90deg, #fbbf24, #f59e0b); -webkit-background-clip: text; -webkit-text-fill-color: transparent`

---

## Component Patterns

### Card (base)
```css
background: rgba(255,255,255,0.025);
border: 1px solid rgba(255,255,255,0.07);
border-radius: 16px;
position: relative; overflow: hidden;

/* Top shimmer line */
::before {
  content: '';
  position: absolute; top: 0; left: 0; right: 0; height: 1px;
  background: linear-gradient(90deg, transparent, rgba(251,191,36,0.2), transparent);
}

/* Hover */
:hover {
  border-color: rgba(251,191,36,0.2);
  background: rgba(255,255,255,0.04);
  transform: translateY(-1px);
  box-shadow: 0 8px 32px rgba(0,0,0,0.3), 0 0 0 1px rgba(251,191,36,0.1);
}
```

### Navbar
```css
background: rgba(12,10,6,0.8);
backdrop-filter: blur(20px);
border-bottom: 1px solid rgba(251,191,36,0.08);
height: 56px; position: sticky; top: 0; z-index: 100;
```

### Connect Wallet button
```css
background: rgba(251,191,36,0.12);
border: 1px solid rgba(251,191,36,0.3);
color: #fbbf24; font-weight: 600; border-radius: 10px;
```

### Badge — Bonding
```css
background: rgba(251,191,36,0.12);
border: 1px solid rgba(251,191,36,0.2);
color: #fbbf24; border-radius: 5px;
font-size: 9px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;
```

### Badge — Graduated
```css
background: rgba(16,185,129,0.12);
border: 1px solid rgba(16,185,129,0.2);
color: #34d399;
```

### Progress bar — Bonding
```css
/* Track */
background: rgba(255,255,255,0.06); height: 4px; border-radius: 4px;
/* Fill */
background: linear-gradient(90deg, #d97706, #fbbf24);
box-shadow: 0 0 10px rgba(251,191,36,0.4);
```

### Progress bar — Graduated (full)
```css
background: linear-gradient(90deg, #059669, #34d399);
box-shadow: 0 0 10px rgba(16,185,129,0.4);
```

### Sort tabs / mode toggle
```css
/* Container */
background: rgba(255,255,255,0.04);
border: 1px solid rgba(255,255,255,0.06);
border-radius: 10px; padding: 3px;
/* Active tab */
background: rgba(251,191,36,0.12); color: #fbbf24;
/* Inactive tab */
color: #6b7280;
```

### Stat card
```css
background: rgba(255,255,255,0.03);
border: 1px solid rgba(251,191,36,0.1);
border-radius: 12px; padding: 14px 16px;
```

---

## Page Layouts

### Discover (`/`)
- Sticky amber-glow navbar
- Page header: "Discover Tokens" title left, sort tabs (Newest / Volume / Trades) right
- Stats bar: 3 stat cards (Total Volume, Tokens Launched, Active Traders)
- Token grid: 3 columns on desktop, 2 on tablet, 1 on mobile
- Each TokenCard: name + symbol, phase badge, progress bar with %, three stats (Volume / Trades / Price)

### Token Detail (`/token/[address]`)
- 2/3 + 1/3 column layout on desktop
- Left: token name + symbol header, price line chart (amber line, dark grid), bonding progress bar, tokenomics section (vesting timeline bars per bucket)
- Right: trade panel card (Buy/Sell tabs), ClaimPanel below (only if wallet is a bucket recipient)
- Bonding → graduated state: trade panel switches, progress bar turns green, "Graduated" badge

### Create (`/create`)
- Single centered card, max-width 680px
- Token name + symbol inputs side-by-side
- Mode toggle: Meme / Structured
- Structured: bucket rows (name, %, recipient, cliff, vesting) + Add Bucket button
- Allocation bar below buckets: amber segments for non-liquidity, brighter amber for liquidity; turns red if ≠ 100%
- Preset buttons: Fair Launch, VC-Backed
- Launch Token CTA button (full width, amber)

### Faucet (`/faucet`)
- Centered card, max-width 400px
- "Mock USDC Faucet" heading + description
- Daily remaining meter
- Mint button + BaseScan tx link

### Profile (`/profile`)
- Wallet address as heading (shortened)
- "Tokens Launched" section: same TokenCard grid
- "Recent Trades" section: table with Token / Side / Amount In / Amount Out / Phase columns

---

## v0.dev Prompts

Use these prompts verbatim at **v0.dev**. Paste the shared style preamble before each page-specific prompt so every component inherits the same visual language.

---

### Shared Style Preamble
> Paste this before EVERY prompt below:

```
Design system rules (apply to all components):
- Font: Plus Jakarta Sans (import from Google Fonts)
- Background: #0c0a06 (warm near-black)
- Glassmorphism cards: background rgba(255,255,255,0.025), border 1px solid rgba(255,255,255,0.07), border-radius 16px. Add a ::before top shimmer: linear-gradient(90deg, transparent, rgba(251,191,36,0.2), transparent), 1px height.
- Card hover: border-color rgba(251,191,36,0.2), translateY(-1px), box-shadow 0 8px 32px rgba(0,0,0,0.3)
- Accent color: amber — #fbbf24 primary, gradient linear-gradient(90deg, #d97706, #fbbf24)
- Graduated/success color: emerald #34d399
- Navbar: sticky, background rgba(12,10,6,0.8), backdrop-filter blur(20px), border-bottom 1px solid rgba(251,191,36,0.08)
- Connect Wallet button: background rgba(251,191,36,0.12), border 1px solid rgba(251,191,36,0.3), color #fbbf24
- Logo: "GradPad" in amber gradient text (linear-gradient 90deg #fbbf24 → #f59e0b, background-clip text)
- Ambient page glow: fixed background radial-gradient at top-left corner, rgba(251,191,36,0.07)
- Text: white primary, #9ca3af secondary, #6b7280 muted
- Bonding badge: amber tint. Graduated badge: emerald tint.
- Progress bars: amber gradient + glow for bonding, emerald gradient for graduated
- Tailwind CSS + shadcn/ui components. Next.js App Router. TypeScript.
```

---

### Prompt 1 — Navbar + Discover Page

```
[paste shared preamble]

Build a token discovery page for GradPad — a DeFi token launchpad on Base mainnet.

NAVBAR:
- Sticky top. Logo "GradPad" left (amber gradient text). Nav links center: Discover (active), Create, Faucet, Profile. "Connect Wallet" button right (amber ghost style).

PAGE HEADER:
- "Discover Tokens" title left. Sort tabs right: Newest / Volume / Trades (pill toggle, amber active state).

STATS BAR (3 cards, full width):
- Total Volume: "$2.4M" / "all time"
- Tokens Launched: "142" / "47 graduated"
- Active Traders: "1,830" / "last 7 days"
- Each stat card: amber uppercase label (10px, 600 weight), large white number (800 weight), muted subtext.

TOKEN GRID (3 columns):
Each token card contains:
- Top row: token name (700 weight) + symbol (muted, 11px) left. Phase badge right: "BONDING" (amber) or "GRADUATED" (emerald).
- Progress label row: "Progress to graduation" left, percentage right (muted, 10px).
- Progress bar: amber gradient fill with amber glow. Graduated tokens show 100% emerald.
- Stats row: Volume / Trades / Price — each with muted 10px label and 700-weight value.

Show 6 cards: 3 bonding (at ~28%, 51%, 73%), 2 graduated (100% emerald), 1 bonding at 9%.
```

---

### Prompt 2 — Token Detail Page

```
[paste shared preamble]

Build a token detail page for GradPad.

LAYOUT: 2/3 + 1/3 column grid on desktop.

LEFT COLUMN:
1. Header: token name (800 weight, 24px) + symbol below (muted).
2. Price chart: show a placeholder line chart shape (SVG or CSS) — amber line, dark background, dark grid lines (rgba(255,255,255,0.05)), no dots. Tooltip styled dark (background #18181b, amber border). The real chart will be wired with Recharts separately — just nail the visual container and line style.
3. Bonding progress bar: label row "Bonding progress" left, "73% to graduation" right. Amber gradient fill with glow. Full-width, 6px tall, rounded.
4. Tokenomics section heading. Per-bucket vesting timeline rows — each row: bucket name + % allocation right, horizontal bar below (grey segment for cliff period, amber segment for vested portion), cliff duration + vest duration labels below bar.

RIGHT COLUMN (sticky):
Trade panel card (glassmorphism):
- "Trade — Bonding Curve" label.
- Buy / Sell tabs (shadcn Tabs, amber active).
- Buy tab: "You pay (mUSDC)" label + balance right, number input, "Buy [SYMBOL]" button (amber filled).
- Sell tab: mirror of buy but "Sell [SYMBOL]" button (red/destructive).
- BaseScan tx link below on success.

Below trade panel (if graduated): ClaimPanel showing user's vesting positions with Claim buttons.
```

---

### Prompt 3 — Create Page (TokenomicsBuilder)

```
[paste shared preamble]

Build a token creation page for GradPad. Centered card, max-width 680px.

HEADER: "Launch a Token" (800 weight).

INPUTS: Token Name + Symbol side-by-side (shadcn Input, dark background rgba(255,255,255,0.05), amber focus ring).

MODE TOGGLE: "Meme" | "Structured" pill tabs (amber active).

STRUCTURED MODE shows:
- Preset buttons row: "Fair Launch" and "VC-Backed" (small ghost buttons).
- Column headers: Name / % / Recipient / Cliff / Vesting (10px muted labels).
- Bucket rows: name dropdown, % number input, recipient address input (monospace), cliff dropdown, vesting dropdown, remove X button.
- "Add Bucket" button (outline, amber border).

ALLOCATION BAR (full width, always visible):
- Horizontal segmented bar — each bucket is a colored segment proportional to its %. Liquidity bucket is bright amber, others slightly muted amber.
- Below bar: "X% / 100%" — green text if valid, red if not.

LAUNCH TOKEN CTA: Full-width amber filled button at bottom.
```

---

### Prompt 4 — Faucet Page

```
[paste shared preamble]

Build a faucet page for GradPad. Single glassmorphism card, max-width 400px, centered vertically on page.

CARD CONTENTS:
- Title: "Mock USDC Faucet" (700 weight).
- Subtitle: "Mint up to 1,000 mUSDC per day to trade on GradPad (Base mainnet)." (muted).
- Info row: "Remaining today" label left, "1,000 mUSDC" right (white).
- Daily limit bar: amber progress bar showing how much has been minted today.
- "Mint 1000 mUSDC" button: full width, amber filled.
- On success: BaseScan link in amber, small text, centered.
- If not connected: show ConnectButton instead of the above.
```

---

### Prompt 5 — Profile Page

```
[paste shared preamble]

Build a profile page for GradPad.

HEADER: Wallet address (shortened: 0x1234…abcd) as page title. Muted subtitle: "Base Mainnet".

TOKENS LAUNCHED SECTION:
- Section heading "Tokens Launched" (700 weight).
- Same 3-column TokenCard grid as Discover page.
- Empty state: "No tokens launched yet. Launch one →" with amber link.

RECENT TRADES SECTION:
- Section heading "Recent Trades".
- Dark table (no outer border, rows divided by rgba(255,255,255,0.06) lines):
  - Columns: Token (amber link) / Side (green "Buy" or red "Sell") / Amount In / Amount Out / Phase badge.
- Empty state: "No trades yet."
```

---

## Workflow: Hybrid AI Design Process

1. **v0.dev phase** (30–60 min)
   - Open v0.dev
   - For each page: paste shared preamble + page-specific prompt
   - Iterate until visual output matches the mockup aesthetic
   - Screenshot or export the component shell

2. **frontend-design skill phase** (per implementation task)
   - When implementing each Task in the plan, invoke `frontend-design:frontend-design`
   - Include this in the prompt: *"Follow the GradPad design spec: glassmorphism cards (rgba(255,255,255,0.025) bg, rgba(255,255,255,0.07) border, 16px radius), amber accent (#fbbf24), Plus Jakarta Sans, amber gradient progress bars. Match the component shell from v0.dev."*
   - Claude writes the component directly into the codebase with correct types and contract wiring

3. **Consistency check**
   - After each new component is built, compare against the full-mockup.html reference
   - Run `npm run dev` and visually verify before committing

---

## shadcn/ui Component Map

| UI element | shadcn component |
|---|---|
| Buttons | `Button` (variant: default/outline/destructive/ghost) |
| Inputs | `Input` |
| Dropdowns | `Select` + `SelectTrigger` + `SelectContent` + `SelectItem` |
| Buy/Sell toggle | `Tabs` + `TabsList` + `TabsTrigger` + `TabsContent` |
| Cards | `Card` + `CardHeader` + `CardContent` (or raw div with card CSS above) |
| Tooltips | `Tooltip` |
| Progress | `Progress` (or raw div — gives more style control) |
| Badges | `Badge` (or raw span — gives more style control for amber/emerald variants) |
| Dialogs | `Dialog` (for tx confirmation, error states) |

---

## Tailwind Config Additions

Add to `tailwind.config.ts` after scaffolding to ensure amber tokens are available:

```ts
theme: {
  extend: {
    colors: {
      amber: {
        glow: 'rgba(251,191,36,0.12)',
      },
    },
    fontFamily: {
      sans: ['Plus Jakarta Sans', 'sans-serif'],
    },
    backgroundImage: {
      'amber-grad': 'linear-gradient(90deg, #d97706, #fbbf24)',
      'emerald-grad': 'linear-gradient(90deg, #059669, #34d399)',
    },
  },
},
```

Also add to `app/src/app/globals.css`:
```css
@import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap');

body {
  font-family: 'Plus Jakarta Sans', sans-serif;
  background: #0c0a06;
}
```
