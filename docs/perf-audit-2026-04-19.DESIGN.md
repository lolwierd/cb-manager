# DESIGN.md — The Cost of a Paste

The inner monologue for the performance audit report at `perf-audit-2026-04-19.html`.

---

## The soul of the piece

A performance audit with 14 findings is, fundamentally, an accounting. Each finding is a small tax levied on an action that the user experiences as instant. The natural frame for such a document is a **ledger** — line items, accrued costs, tiers. For a clipboard manager, the editorial title was almost unavoidable: **"The Cost of a Paste."** Specific to the product, opinionated, memorable.

The concept had to pass the 7/10 test. If 10 designers got this brief — "performance audit, dark mode, technical" — seven of them would produce:

- Inter or SF Pro body
- GitHub-dark background (#0d1117) or Notion-dark
- Red/orange/yellow/blue severity pills
- Card-based layout with severity as loud color blocks
- Maybe a shadcn-ish table

I rejected all of that. The editorial/ledger concept let me derive a different vocabulary:

- **Serif body** (Source Serif 4) — signals a considered document, not a dashboard. Screen-optimized, so readable at 17px dark on warm off-white.
- **Serif display** (Fraunces at opsz=144) — the one surface where personality can be loud. Variable axes let a single family cover everything from tiny folio numerals to the cover headline.
- **Warm ink palette** — `#13110f` for the body (deep brown-black, not GitHub blue-black), `#ece3d2` for text (like aged paper, not pure white). Decided against noise/texture overlays — trust the typography.
- **Severity as restrained marginalia** — not JIRA pills. Color-derived from heat and oxidation metaphors (ember, flare, patina, slate). Low saturation, thin 1px borders, tight letterspacing. Reads as document structure, not dashboard alarm.
- **Accrual markers** — the hook. Four tiny glyphs (◉ ▸ ▪▪▪ ∞) next to every finding saying *when* you pay the cost: startup, per-event, per-interaction, or over time. I've never seen this in any perf audit. It's specific to perf work and it makes each finding immediately legible at a glance.

## What I actively rejected

- **Syntax highlighting with the usual VS Code / One Dark palette.** Clashes with the editorial tone and competes with the severity colors. Instead: mono font, weight contrast for identifiers, italic for comments, one accent color (gold) for proposed lines. Austere.
- **A hero chart or data viz.** Considered a horizontal bar showing severity distribution. Rejected — it'd be gratuitous. The summary table is the at-a-glance artifact; one more chart would be noise.
- **Noise / grain texture on the background.** Tempting for "paper" feel. Looks cheap on dark. Cut.
- **JIRA-style severity badges with bright fills.** The document wouldn't be able to breathe. The current treatment — outlined badges with low-opacity fills and tight mono text — is structural rather than decorative.
- **Inter / IBM Plex pairing.** Both are fine, both are the default answer for "technical documentation dark mode." Went with Fraunces + Source Serif specifically to avoid the SaaS-doc aesthetic.
- **A sidebar with sticky navigation.** The summary table does the same job with less chrome. Anchor links in the table jump to each finding. The whole doc reads top-to-bottom; no need for a persistent UI.

## Layout, derived

A two-column finding layout — narrow left "folio" (§ number, severity badge, location, accrual, phase) and wide right body (title, what, impact, fix). Echoes the way academic and legal documents put their identifying metadata in the outer margin. On mobile the folio collapses above the body. This isn't a visual flourish — it separates the scannable metadata from the prose, which is what a developer reading this at 11pm needs.

The masthead at the top (publication name, audit number, date) is a single pipe-separated mono line — publication identity without the expense of a logo lockup. It sets expectations: this is a document, not a web page.

## Typography decisions

- **Display headlines**: Fraunces at opsz 144, SOFT 40-60, wght 520-540. The SOFT axis softens the serifs slightly — the default Fraunces is a little too wonky for this technical context. The cover title uses italic on "Paste" for gold emphasis — a tiny editorial flourish.
- **Body**: Source Serif 4 at 17px, line-height 1.62, font-weight 380 (between Light and Regular). The slightly sub-Regular weight keeps dense prose from feeling heavy on dark backgrounds.
- **Mono**: JetBrains Mono at 0.92rem body, 0.78rem for file:line citations. Subtle ligatures (liga) on, but no stylistic set tricks.
- **Old-style numerals** in body text (`onum`), **tabular** in the ledger table. Tiny detail, but it's the kind of thing that reads as "someone cared" without being showy.

## The details nobody will notice (but which are there)

- The drop cap on the prologue is Fraunces at 4.6em with opsz tuned to display, rendered in gold. It's four lines tall on desktop, two on mobile.
- The end-mark ◆ in the colophon is the same gold as the accents — a small punctuation of the document's end.
- Every section has a roman numeral marker (I through VI). Echoes a journal's table of contents.
- The dek (italic subtitle) appears in three places — cover, tier intros, context section. Same voice each time: factual, quietly editorial, never promotional.
- Print stylesheet inverts the palette for PDF export. The document survives being printed — black ink on warm paper, preserves typography, page breaks inside findings are avoided.
- The cover coverline shows four datapoints — "14 findings · 4 tiers · 2 critical · ~6h total fix" — which sets user expectations before they read anything.
- The architectural context section uses `decimal-leading-zero` counter style for its ordered list — visually coherent with the §01 / §02 finding numbering scheme elsewhere.
- `:focus-visible` uses the gold accent color for keyboard focus. Accessible without looking OS-default.

## What I was genuinely unsure about

- **Whether to use serif for body at all on a dark screen.** Most online reading at 14–17px on dark benefits from sans — serifs get aliased. Source Serif 4 is designed specifically for on-screen reading, which pushed me over. Tested at 17px, 1.62 line-height, antialiased: legible, and it carries the editorial voice the concept needs.
- **Whether the ledger table belongs before or after the tier sections.** Before, clearly — it's the scan-first artifact and the developer needs it for prioritization before they read the detail. The full findings below are the deep dive.
- **Whether phase 4 findings deserve the same card treatment as critical ones.** Yes — because someone editing those files later will want the full context, and treating them as footnotes would signal "don't bother." The visual weight of each card is the same; the severity badge and the phase indicator do the ranking.

## How this reads

Top to bottom:

1. **Masthead** — publication identity, one line.
2. **Cover** — title, one-line argument, datapoints.
3. **Prologue** — three paragraphs with a drop cap. Sets the "this app works, here's what remains" tone.
4. **Legend** — accrual + severity keys. Teaches the reader how to scan.
5. **The Ledger (summary table)** — all 14 at a glance. Sortable by eye.
6. **Critical tier** — 2 findings with full treatment.
7. **High tier** — 4 findings.
8. **Medium tier** — 4 findings.
9. **Low tier** — 4 findings.
10. **What this audit is not** — three corrections to first-pass assumptions. This is where the document earns credibility by admitting its own edges.
11. **Settlement** — four phases with ROI framing.
12. **Colophon** — typesetting credits, end-mark.

## The phrase I'm proudest of

From the pull quote in §01: *"Default SQLite pragmas optimize for survival at rest. WAL optimizes for latency in flight — and costs you nothing."* It's the kind of thing that belongs in an engineering blog post, not a JIRA ticket. It's why the serif body exists.

## Things that would not belong in this design

- Animations on scroll. This is a document, not an experience.
- A "share this finding" button. It's an internal document.
- Dark/light mode toggle. The dark treatment is the design; the print stylesheet covers the light case.
- A TOC sidebar. The summary table is the TOC.
- Emojis anywhere. Period.
