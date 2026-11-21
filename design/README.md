# Handoff: Twofold — shared budgeting for couples (web + iPhone + iPhone Duo)

## Overview
Twofold is a budgeting app for two people sharing one household budget. This bundle covers:

- **Web app** (`Tandem Budget.dc.html`) — responsive; sidebar island on desktop, bottom tab bar under 960px.
- **iPhone app** (`Tandem iPhone.dc.html` + `TandemScreen.dc.html` + `TandemDevice.dc.html`) — shown as two phones (one per partner), a foldable "iPhone Duo" unfolded (two panes), and its folded cover display.

All surfaces read and write the same data, so an entry added on one shows on the others.

## Naming
The product is called **Twofold** (previously "Tandem"). Everything the user sees uses the new name. The prototype file names, component names (`TandemScreen`, `TandemDevice`) and storage keys (`tandem-budget-v3`) still carry the old name — do not carry it into production code.

## About the design files
The files here are **design references built in HTML** — working prototypes that show the intended look and behaviour. They are **not production code to ship**. The task is to **recreate these designs in the target codebase** using its own framework, components and patterns (React, SwiftUI, etc.). If there is no codebase yet, choose the most suitable stack (e.g. React + TypeScript for web, SwiftUI for iOS) and implement there.

Open any `.dc.html` file directly in a browser (keep `support.js` and `ios-frame.jsx` beside it). Each file is one template (HTML with `{{ holes }}`, `<sc-if>`, `<sc-for>`) plus one logic class at the bottom whose `renderVals()` computes everything the template shows. Read `renderVals()` for the exact calculations.

## Fidelity
**High-fidelity.** Colours, type, spacing, radii and interactions are final. Recreate pixel-accurately.

---

## Design tokens

### Colour
| Token | Value | Use |
|---|---|---|
| Ink / black | `#0b0b0c` | App background, header zone, primary buttons, progress tracks |
| Lavender (accent) | `#b9b0ff` | Hero fields, active nav, progress fills on cream, primary CTA on black |
| Cream | `#fbf9ef` | Content field, secondary bars |
| White | `#ffffff` | Tiles, keypad keys, text on black |
| Island / raised black | `#17171b` | Sidebar island, tab bars |
| Raised black 2 | `#1d1d22` | Inputs and month switcher on black |
| Hover on island | `#26262c` | |
| Muted on black | `#a9a7b8` | Secondary text on black |
| Soft text on black | `#d9d7e4` | Hero sub-copy, chart labels |
| Muted on cream | `#6b6878` | Secondary text on cream |
| Muted on lavender | `#3a3566` | Secondary text on lavender |
| Accent text on cream | `#4b40a8` | Links, positive values |
| Soft cream | `#efecde` / `#ebe8da` | Avatar squares, soft fills |
| Bad (on cream) | `#c23b30` | Over budget |
| Bad (on lavender) | `#a3261b` | |
| Bad (on black) | `#ff8f85` | Negative hero numbers, forecast dips |
| Warn (on cream) | `#9a4a3a` | |
| Hairline on cream | `rgba(11,11,12,.12)` | Row dividers |
| Hairline on lavender | `rgba(11,11,12,.14–.16)` | |
| Hairline on black | `rgba(255,255,255,.14)` | |

Content sits on one of three "stages": **cream**, **lavender** or **dark**. Lavender is used for Today, Accounts, Savings and Us two; cream for everything else. On lavender, tiles are `rgba(255,255,255,.5)` and progress fills are white.

A "Night" theme swaps the cream stage for `#17171b` with cream text (see the `body[data-theme=night]` rule).

### Type
One family: **Geist** (Google Fonts, weights 400–700). Tabular numerals everywhere.

| Role | Size / weight / tracking |
|---|---|
| Hero number (web) | `clamp(56px, 8.5vw, 108px)` / 500 / `-0.045em`, line-height .95 |
| Today safe-to-spend (web) | `clamp(64px, 10vw, 124px)` / 500 / `-0.05em` |
| Hero number (phone) | 54–60px / 500 / `-0.045em` |
| Amount entry | 68px / 500 / `-0.045em` |
| Section title | 22px / 500 / `-0.01em` |
| Big percentage in rows | 26–27px / 400 / `-0.02em` |
| Row title | 16px / 500 |
| Body | 15px / 400, line-height 1.4 |
| Meta | 12.5–13.5px / 400 |
| Buttons | 14–15px / 500 (primary save: 17px) |
| Chips | 13.5px / 500 |

### Shape and spacing
- Radii: 13px (44px date/avatar tiles), 15–18px (inputs, small buttons), 20–22px (cards, pills at 44px height), 28px (web cards, sidebar island), 30–32px (sheets, tab bars).
- Hit targets: 44px minimum everywhere.
- Web page padding: `clamp(16px, 3.5vw, 44px)`; section gaps 30–40px.
- Phone screen padding: 20px (16px for card lists); 130px bottom padding to clear the tab bar.
- Shadow (tab bars): `0 0 0 1px rgba(255,255,255,.1), 0 12px 30px rgba(0,0,0,.35)`.
- Progress bars: 5px tall, 3px radius, **black track** with lavender fill (white fill on lavender stage). Over-budget fill is the "bad" colour.

### The blob edge
Every screen is a black top zone that "melts" into the coloured field through a stepped, rounded silhouette with two loose pills. On web it is a repeating CSS mask (`--blob`, 1200×84px tile). On phone it is an inline SVG (viewBox `0 0 402 78`, rendered 66px tall); it is mirrored horizontally (`scaleX(-1)`) on cream screens for variety. Copy the path data from the files.

---

## Web app (`Tandem Budget.dc.html`)

### Shell
- **Sidebar island (≥960px)** — floating rounded panel, not a flush column.
  - Container: sticky, full height, 14px padding all round. Panel: `#17171b`, radius 28px, 1px inner ring `rgba(255,255,255,.08)`, padding 14px 10px.
  - **Expanded: 236px** total width (208px panel). **Collapsed: 96px** (68px panel, icons only). Width animates `.28s cubic-bezier(.2,.8,.2,1)`; labels fade `.18s`.
  - Header row 46px: "Twofold" wordmark (600, 24px, `-0.03em`) + 46px toggle button (sidebar-panel icon, `#a9a7b8`, hover `#26262c`/white). Collapsed shows the toggle only, centred.
  - Nav items: 46px tall, radius 16px, 22px icon + 12px gap + 15px/500 label. Active = lavender background, black text. Inactive = transparent, white. Each has a `title` tooltip (needed when collapsed).
  - Collapsed state persists (`navMin`).
- **Bottom tab bar (<960px)** — fixed, 12px inset, `#17171b`, radius 32px, 5 equal columns: Today, Activity, Budget, Bills, More. Each is a 21px icon over a 12px label; active is lavender. "More" opens a cream bottom sheet listing the remaining tabs (icon + 20px label + arrow, 60px rows).
- **Header (black)** — partner initials (two overlapping 46px squares, lavender and cream), page title 22px/500 + grey kicker, month switcher (`#1d1d22` pill with ‹ ›), and "+ Add entry" (lavender, 48px, radius 16px).
- **Hero** (all tabs except Today) — label, currency prefix + big number, sub-copy, a row of small stats, and on most tabs a bar chart (230px tall, cream bars with the key bar in lavender and a cream value tag above it).

### Icons
Simple 24×24 stroke icons, `stroke-width:1.8`, round caps and joins, `currentColor`. Path data is in the `ICON` constant in the logic class. These are stand-ins drawn for the prototype — **swap for the codebase's icon set** (Lucide equivalents: home, list, pie-chart, calendar, credit-card, database/coins, trending-down, bar-chart, trending-up, users, menu, panel-left).

### Tabs
1. **Today** (lavender) — "Safe to spend this month" huge figure, spend progress with unpaid-bills hatch and a today tick, three white quick-action tiles (Income, Move, Spend) plus one black Reports tile, then Categories to watch, Coming up, recent entries, goals and accounts on hairlines. First-run shows a numbered setup checklist.
2. **Activity** (cream) — search, Export CSV, filter chips (who / account / category), entries grouped by day in two columns.
3. **Budget** (cream) — hero "Left to assign". A hint line with a **"+ New category"** button at the top. Three groups (Needs, Wants, Pocket money), each row = name, big %, 5px bar with a "today" pace tick, and "spent of limit · left". Tapping a row opens the limit panel. Optional 50/30/20 check card.
4. **Bills** (cream) — hero "Still due", month calendar, list with black date tiles and Pay/Paid buttons, "+ New bill".
5. **Accounts** (lavender) — hero "Net worth" with 6-month bars, white account tiles (selected turns black), cards and loans.
6. **Savings** (lavender) — hero total with 12-month projection; pots with progress, auto-save toggle, Deposit/Withdraw; round-ups and month-end sweep.
7. **Debt** (cream) — hero "Debt-free by", strategy chips (highest interest / smallest balance), extra-payment slider, payoff order list, "+ Loan".
8. **Reports** (cream) — hero "Spent in {month}" with income-vs-spending bars for six months; **"↓ Download report"** (white, 50px, radius 18px) and **"Export CSV"** (outline) under the hero; then Where it went, Who spent, Most-visited places.
9. **Plan ahead** (cream) — 30-day cash forecast, what moves the balance, trips and events, planned purchases with both partners' votes.
10. **Us two** (lavender) — contributions, pocket money, settle-up, monthly money-date checklist.

### Side panel (add / edit)
Slides in from the right (`translateX`, .23s). Lavender top with title, close button (44px black square, radius 15px), type chips, and for entries an oversized 68px amount input; blob edge; then the form on the stage background. Sticky footer: error line, optional Delete (outline in "bad"), Save (58px, radius 20px).

Panel types: entry (expense / income / transfer), category limit, **new category**, pot, account, and a generic item form (bill, loan, pay, planned purchase, trip).

### Custom categories (new)
- "+ New category" opens a panel: **Name**, **Group** (Needs / Wants chips), **Monthly limit**.
- Validation: name required; must not duplicate an existing category name (case-insensitive) → "You already have a category with that name."
- Saved to `custom: [{id, name, g, h, custom:true}]` with its limit in `budgets[id]`.
- Custom categories appear in the budget groups, the entry category picker, Activity filters, Reports and "Categories to watch".
- Opening a custom category's limit panel also shows a **Name** field (rename) and a **Delete** button. Deleting removes the category and its limit; existing entries keep their amount and show as "Other".

### Downloadable reports (new)
- **Download report** → a self-contained, print-ready HTML file `twofold-report-YYYY-MM.html` in the brand style (cream page, Geist, black tracks with lavender fills): headline spend, income, key stats, category table with bars / share / amount / last month, who spent, top 10 places, six-month income–spending–net table, and a "Print or save as PDF" button that hides on print. In production, generate a real PDF server- or client-side with the same layout.
- **Export CSV** → `twofold-report-YYYY-MM.csv` with the same sections as plain rows.
- Both always reflect the month selected in the header.

---

## iPhone app (`Tandem iPhone.dc.html`, `TandemScreen.dc.html`)

`TandemScreen` is one screen renderer used five times: two phones (402×874), the Duo cover (466×678), and the Duo's left and right panes (445×626 each). `TandemDevice` wraps a screen in a bezel.

### Tab bar
Floating pill, 14px inset, 20px from the bottom, 64px tall, `#17171b`, radius 32px: **Home · Budget · (+) · Savings · More**. The centre "+" is a 52px lavender circle. Active label is lavender.

### Screens
- **Home** — greeting, lavender field with safe-to-spend (60px), progress, Income / Move / Spend tiles (66px, white) and a black **Reports** tile, Coming up (Pay buttons), Transactions.
- **Budget** — "Left to assign" on black, groups on cream; tapping a row opens a bottom sheet with −/+ steppers (±50), 3-month average and Save.
- **Savings** — total in pots, round-ups card (black), pot cards with Deposit / Withdraw.
- **More** — list in web nav order: Activity, Bills, Accounts, **Debt**, **Reports**, **Plan ahead**, Us two.
- **Activity / Accounts / Bills / Us two** — as before.
- **Reports** — 7-day spending bars, Where it went, Who spent, and a black **"↓ Download this month's report"** button (CSV; use the iOS share sheet in production).
- **Debt** (new, cream) — "Debt-free by" in lavender 54px; strategy chips; "Extra each month" stepper (±250, 44px black buttons); numbered payoff list with balance and "Clear by" month.
- **Plan ahead** (new, lavender) — "Cash in 30 days" (turns `#ff8f85` if the forecast dips under the 5,000 cushion), 31 thin bars (110px tall, 3px gap; first bar lavender, dips red), then Coming in and out (next 6 items), Planned purchases with a verdict line, Trips & events with progress. Planned purchases and trips are read-only on phone.

### Add entry — layout per device (fixed this round)
- **Phone (portrait):** lavender header (type chips, 68px amount, name field) → one horizontally scrolling row of category tiles (68px wide, 60px square) → one scrolling row of chips (who + account) → keypad (54px keys) → Save.
- **Duo unfolded:** left pane = header + **all categories in a wrapping grid, 6 per row** (61px wide, 54px square) so nothing is hidden; right pane = **who chips and account chips at the top**, keypad (80px keys) and Save at the bottom.
- **Duo cover (folded):** two columns under the header; left (flex 1.2) = one scrolling row of category tiles, a who row, an account row; right (flex 1) = keypad (50px keys) and Save.
- Chips never wrap to two lines (`white-space:nowrap`); rows scroll horizontally instead.
- Empty amount → "Enter an amount first"; transfer with same or missing accounts → "Pick two different accounts".

### Duo behaviour
- Left pane is the navigator (tabs + lists); right pane shows the detail and has no back button or tab bar.
- On **More**, the row whose detail is open on the right is marked with a filled black arrow circle (38px); others have a plain arrow.
- Home's Reports tile, "All bills" and "See all" open their detail on the right pane.
- The add-entry sheet spans both panes; the budget-limit sheet covers the left pane only.

---

## Interactions and behaviour
- Month switcher changes every figure on the web app; phone always shows the current month.
- Paying a bill creates an expense on the main current account and marks the bill paid for that month; un-paying reverses both.
- Transfers into / out of a pot move the account balances and the pot's saved amount.
- Round-ups: sum of (amount rounded up to the next 10 − amount) for non-bill expenses this month, minus what has already been swept.
- Safe to spend = total category limits − spent − unpaid bills. Left to assign = income − category limits − monthly pot contributions.
- Debt payoff: monthly simulation (interest = balance × APR / 12; pay minimums; extra + freed minimums go to the first debt in strategy order). Credit cards with a negative balance are included automatically (APR default 36%, minimum = max(100, 5% of balance)).
- Forecast: starting cash (current + cash accounts) + scheduled bills and pay over 30 days − average daily non-bill spending over the last 60 days.
- Transitions: sheets and panels .23–.32s `cubic-bezier(.2,.8,.2,1)`; bars animate height/width .4s.

## State
Persisted per household (prototype uses `localStorage` key `tandem-budget-v3`; an "empty view" uses `tandem-budget-empty-v1`):

```
tx[]        {id, date 'YYYY-MM-DD', name, cat, amt, who 'A'|'B'|'J', type 'exp'|'inc'|'xfer', acct, to?, pot?, potDir?, billId?, note?}
budgets     {categoryId: monthlyLimit}
custom[]    {id, name, g 'needs'|'wants', h, custom:true}
bills[]     {id, day, name, amt, cat, sub, paid:{'YYYY-MM':true}}
incomes[]   {who, amt, day}
goals[]     {id, name, target, saved, monthly, acct, due, auto}        // savings pots
debts[]     {id, name, balance, apr, min}
accounts[]  {id, name, type 'current'|'cash'|'card'|'save'|'invest', who, bank, last4, balance, limit?, apy?, apr?}
planned[]   {id, name, cost, A, B}                                      // votes
events[]    {id, name, when, budget, spent}
settled, checks, strat 'avalanche'|'snowball', extra, selAcct, roundUps, sweep, sweepPot, roundSwept, tab, navMin
```

Built-in categories (id, group): housing, groceries, utilities, transport, insurance, health, kids, debt (needs); dining, fun, shopping, subs, travel, gifts (wants); allowA, allowB (pocket money). Replace `localStorage` with the real backend and live sync between partners.

Web-only settings exposed as props: partner names, currency, theme (Paper / Night), accent colour, budget style (Zero-based / 50/30/20), rollover, split mode and rule, cash cushion, coach tips, empty view.

## Changes in this round
1. **Custom budget categories** on web (add, rename, delete), carried through to the phone's budget and entry picker.
2. **Parity between web and phone** — phone tab renamed Pots → **Savings**; Insights → **Reports**; new **Debt** and **Plan ahead** screens; More list reordered to match web navigation.
3. **Sidebar** rebuilt as a collapsible floating island with icons; collapsed state is remembered. Icons also added to the mobile-web tab bar and More sheet.
4. **Reports are downloadable** — styled report file + CSV on web; CSV on phone.
5. **Add-entry fixes on Duo and cover** — categories were clipped to one row or hidden entirely and account chips wrapped onto two lines and ran off-screen; now laid out per device as described above.
6. **Duo More list** shows which detail is open.
7. Bug fix: saving a phone entry with no amount now shows the validation message instead of failing.

## Known gaps to decide in implementation
- Planned purchases, trips, pots, loans and categories can only be created on web.
- Phone forecast uses a fixed 5,000 cushion; web's is a setting.
- Transfer chips on phone have no "From / To" labels.
- Tile labels truncate with an ellipsis on the Duo grid (e.g. "Kids & fa…").

## Assets
No images. Font: Geist via Google Fonts. Icons: hand-drawn stroke paths in `ICON` (replace with the codebase's set). iOS status bar comes from `ios-frame.jsx` (prototype chrome only — not part of the app).

## Files
- `Tandem Budget.dc.html` — web app (all ten tabs, side panel, report export).
- `Tandem iPhone.dc.html` — iPhone / Duo showcase and all phone logic.
- `TandemScreen.dc.html` — phone screen templates (every screen, tab bar, add-entry sheet, budget sheet).
- `TandemDevice.dc.html` — phone bezel wrapper.
- `ios-frame.jsx`, `support.js` — prototype runtime; needed only to open the files.
