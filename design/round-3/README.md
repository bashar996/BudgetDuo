# Handoff: Twofold — Net worth, Bills calendar on mobile, Edit & delete categories, Edit & delete savings pots, App icon (changes only)

## Overview
This package describes **only the changes made in this round** to Twofold, the shared budgeting app for couples. It assumes the earlier full handoff has already been implemented.

Six changes:

1. **Net worth** — a new section on web and iPhone that adds up everything the couple owns (accounts, investments, and physical assets) minus everything they owe.
2. **Assets and investments** — users can now record assets that don't sit in a bank account (home, car, gold, a business) and track what they put into each investment to see its gain.
3. **Bills calendar on iPhone** — the phone's Bills screen gets the month calendar the web already had, with tap-a-day filtering.
4. **Edit and delete budget categories** — every budget category (built-in or user-made) can now be renamed, moved between groups and deleted, with a choice of where its entries go.
5. **App icon** — a new icon for iOS, Android and web.
6. **Edit and delete savings pots** — a visible Edit button on every pot (web and iPhone), and pots can now be created, edited and deleted on the phone.

## About the design files
The bundled files are **design references built in HTML** — working prototypes showing the intended look and behaviour, not production code to ship. **Recreate these changes in the target codebase** using its own framework, components and patterns. Open any `.dc.html` directly in a browser with `support.js` and `ios-frame.jsx` beside it. Each file is one template plus one logic class; `renderVals()` holds the exact calculations.

Naming: the product is **Twofold**. File names, component names (`TandemScreen`, `TandemDevice`) and the storage key (`tandem-budget-v3`) still carry the old name in the prototype only.

## Fidelity
**High-fidelity.** Colours, type, spacing and behaviour are final.

Tokens are unchanged from the main handoff. The ones used here: black `#0b0b0c`, lavender `#b9b0ff`, cream `#fbf9ef`, white `#ffffff`, deep purple `#4b40a8`, muted on cream `#6b6878`, soft cream `#ebe8da` / `#efecde`, bad `#c23b30`, hairline `rgba(11,11,12,.12)`. Font: Geist. Section titles 22px/500/`-0.01em`; row titles 16px/500; meta 13px; amounts 15px/500.

---

## 1. Data model changes

```
assets[]            NEW   {id, name, kind, value}
                          kind: 'property' | 'vehicle' | 'gold' | 'business' | 'other'
accounts[].cost     NEW   optional number, only on type 'invest' — the amount the user has put in
```

Kind labels: Property, Vehicle, Gold & jewellery, Business, Other.

`assets` is persisted with the rest of the household data. Assets are manual valuations — they have no transactions and are never a source or destination for transfers.

**Migration:** existing households have no `assets` field; treat missing as an empty list. (The prototype seeds two demo assets and demo `cost` values on first load — do not port that.)

## 2. Net worth calculation (changed)

```
own       = sum of every account with a positive balance  +  sum of assets[].value
owe       = sum of loans (debts[].balance)  +  sum of |balance| for accounts below zero (credit cards)
net worth = own − owe
```

Previously `own` did not include assets. Everything that shows net worth (hero, history bars, the "since last month" line) now uses this figure.

Breakdown of `own` into four groups, in this order and with these colours:

| Group | What counts | Colour |
|---|---|---|
| Cash | current + cash accounts with a positive balance | `#0b0b0c` |
| Savings | savings accounts | `#b9b0ff` |
| Investments | investment accounts | `#4b40a8` |
| Property & other assets | `assets[]` | `#6b6878` |

Investment gain per account (only when `cost > 0`): `gain = balance − cost`, shown as `+AED 12,000 · +23%` (percentage = gain ÷ cost, rounded). Positive in `#4b40a8`, negative in `#c23b30` with a `−` sign.

---

## 3. Web (`Tandem Budget.dc.html`)

### New tab: Net worth
- Added to navigation **between Accounts and Savings** (11 tabs now). Icon: stacked layers (Lucide `layers`). Kicker: "Everything you own, minus what you owe". Cream stage.
- On mobile web it appears in the More sheet.

**Hero (black zone)**
- Label "Net worth", currency prefix + big number (white), sub-line "+AED X since last month".
- Stats row: **You own**, **You owe**, **Investment gain** (sum of gains across investments with a cost; "—" if none have one).
- Six-month bar chart (cream bars, current month lavender with a value tag) — this chart moved here from Accounts.

**Body — two columns (`repeat(auto-fit, minmax(min(100%,290px),1fr))`, gap 30px 40px)**

Left column:
- **What you own** — title with the total on the right (13px muted). Below it a split bar: 16px tall, 3px gaps, 5px radius per segment, segment widths proportional to value (zero-value groups omitted, 6px minimum width). Then four legend rows on hairlines: 14px colour square (5px radius) · label 16px · percentage of own (13px muted) · amount (15px/500, right-aligned, min-width 96px).
- **What you owe** — title with a "Payoff plan →" outline pill button (44px, radius 22px, 1.5px black border) that goes to the Debt tab. Rows: name 16px/500 + type or "x% interest" 13px muted · amount. Then a "Total owed" line (15px/500). Empty: "Nothing owed."

Right column:
- **Assets** — title + **"+ Add asset"** outline pill. Rows are buttons (open edit): 44px soft-cream tile (radius 13px) with the kind's first letter · name 16px/500 + kind 13px muted · value. Empty: "Add a home, a car, gold or anything else of value that doesn't sit in an account."
- **Investments** — title + **"+ Add investment"** outline pill. Same row style; tile shows the account's first letter; meta is owner · provider; right side stacks value over the gain line (12.5px). If no cost is recorded the gain line reads "Add what you put in to see the gain" in muted. Rows open the account editor. Empty: "Add a brokerage, fund or long-term plan with what it's worth today."

### Asset panel (new) — side panel, same shell as other item forms
- Title "New asset" / "Edit asset".
- Fields in order: **Name** → **Kind** (five chips, single-select, default Property) → **What it's worth today (currency)**.
- Validation: name required ("Give it a name."); value must be a number ("Add an amount.").
- Edit mode shows Delete.

### Investment (changed) — uses the existing account panel
- "+ Add investment" opens the account panel with **Type preset to Investment**.
- When Type is Investment, an extra field appears: **"Amount you put in (optional)"** → saved as `cost`.

### Accounts tab (changed)
- Hero no longer shows net worth. It is now **"Across your accounts"** = sum of all account balances (cards negative), sub-line "Everyday money, savings and cards. The full picture, with your assets, is under Net worth.", stats Cash / Savings / Investments, **no bar chart**.
- Kicker changed to "Balances and cards".

---

## 4. iPhone (`TandemScreen.dc.html`, logic in `Tandem iPhone.dc.html`)

### Bills screen — calendar (new)
A white card sits at the top of the cream field, above the bill list.

- Card: `#ffffff`, radius 22px, padding 14px, 10px gap below.
- Header row: month and year (18px/500) on the left; hint "Tap a day to see its bills" (12.5px muted) on the right.
- Grid: 7 equal columns, 5px gap. Weekday initials row (S M T W T F S, 12px muted). Then one square cell per day (leading blanks for the first weekday).
- Cell: `aspect-ratio:1`, radius 12px, day number 14px/500, and under it one 4px dot per bill due that day (dots take the text colour).

| State | Fill | Text | Notes |
|---|---|---|---|
| No bills | transparent | black | not tappable |
| Bills, all paid | `#ebe8da` | black | |
| Bill still due | `#b9b0ff` | black | |
| Overdue (due, before today) | `#c23b30` | white | |
| Today | `#0b0b0c` | white | wins over the states above |
| Payday | 1.5px black border | — | combines with any fill |
| Selected | double ring: 2px white then 2px black (`0 0 0 2px #fff, 0 0 0 4px #0b0b0c`) | — | combines with any fill |

- Legend under the grid (12px muted, 11px swatches): Due · Overdue · Paid · Today · Payday (outlined).
- **Interaction:** tapping a day that has bills filters the list below to that day and shows a pill above the list — "{day} {Mon} only ×" (44px, outline). Tapping the same day again or the pill clears the filter. Days without bills do nothing.
- The list rows and Pay / Paid buttons are unchanged. **iPhone Duo (unfolded) — the calendar uses both panes.** Opening Bills from the left pane (More → Bills, or Home → "All bills →") turns the left pane into a dedicated calendar screen: back arrow + "Bills" title on black, blob edge, then the calendar card filling the cream field (hint text reads "That day's bills show on the right"). The right pane shows the "Still due" hero and the bill list **without** the calendar card. Tapping a day on the left filters the list on the right and shows the "{day} {Mon} only ×" pill there. Back, or any tab-bar tap on the left, returns the left pane to where it was; the right pane then shows calendar + list together again, as on a single phone. Folded cover and regular iPhones keep the single-column layout (calendar above list).
- The phone always shows the current month (no month switching, same as the rest of the phone app).

### Net worth screen (new)
- Reached from **More**, new row placed after Accounts: title "Net worth", sub-line "AED X across everything you own".
- Black zone: back arrow + centred title "Net worth"; label "Net worth"; currency + 54px number (white); sub-line "Own AED X · owe AED Y".
- Cream field (mirrored blob edge), 20px side padding:
  1. **What you own** — total on the right; split bar 14px tall (same colours and rules as web); four legend rows.
  2. **Assets** — rows with 44px `#ebe8da` tile (kind initial), name + kind, value.
  3. **Investments** — rows with tile, name + owner, value over gain line.
  4. **What you owe** — total on the right; rows name + type, amount.
  5. Footnote (13px muted): "Assets and investments are added and edited in the web app."
- Read-only on phone in this design. Empty states: "No assets yet. Add a home, car or gold in the web app." / "No investments yet." / "Nothing owed."

### Accounts screen and More list (changed)
- Accounts hero label "Net worth" → **"Across your accounts"**; number = sum of account balances; sub-line "{n} accounts · the full picture is under Net worth".
- More list order is now: Activity, Bills, Accounts, **Net worth**, Debt, Reports, Plan ahead, Us two. The Accounts row sub-line is "{n} accounts and cards".

---

## 5. Edit and delete budget categories (web)

Previously only user-made categories could be renamed or deleted. Now **every category can**, except the two pocket-money categories (one per partner), which stay fixed.

### Data model
```
catOv   NEW   { [categoryId]: { name, g } }   overrides for built-in categories (g: 'needs' | 'wants')
catDel  NEW   [categoryId]                    built-in categories the household has removed
```
- Effective category list = (built-ins + `custom[]`) minus `catDel`, with `catOv` applied. Every screen on web and phone reads this list (budget groups, entry category picker, Activity filters, Reports, Categories to watch).
- User-made categories are edited and removed in `custom[]` directly; `catOv` / `catDel` are only for built-ins. In production, simply store all categories per household as editable rows — the override maps are a prototype shortcut.

### Entry point
Budget tab → tap any category row → the existing category side panel. Hint line at the top of the Budget tab now reads "Pick a category to rename it, change its limit, move money in or delete it."

### Panel — fields, top to bottom
1. "Spent AED X so far in {month}." (unchanged)
2. **Name** — text input (new for built-ins).
3. **Group** — two equal-width chips, Needs / Wants, single-select (new). Changing it moves the row to the other group on save.
4. **Monthly limit** — unchanged. "Use 3-month average", latest entries and "Or move money in from" are unchanged.
5. Footer: **Delete** (outline, bad colour) + **Save**.

Pocket-money categories show only the limit controls — no Name, no Group, no Delete.

### Save — validation
- Name required → "Give it a name."
- Name must not match another category (case-insensitive) → "You already have a category with that name."

### Delete — two steps, in the same panel
1. First tap on **Delete** does not delete. A white card (radius 20px, padding 16px) appears at the top of the panel body and the footer button label changes to **"Confirm delete"**.
   - Title "Delete this category?" (17px/500).
   - If entries or bills use it: "{n} entries and {m} bills use this category. Where should they go?" followed by a wrap of chips — every other category, plus **"Leave uncategorised"** last — and the note "Uncategorised entries stay in Activity but stop counting toward any budget."
   - If nothing uses it: "Nothing uses this category yet, so it can go straight away." (no chips).
   - **"Keep category"** outline pill cancels and restores the Delete label.
2. **Confirm delete**:
   - If the category is in use and no chip is picked → error "Choose where its entries should go."
   - Otherwise: remove the category and its monthly limit; re-assign its entries **and** bills to the chosen category, or leave them as they are if "Leave uncategorised" was picked; clear the Activity category filter if it pointed at the deleted one; close the panel.
- Uncategorised entries display with the category label "Other" and are excluded from category totals, safe-to-spend and reports.

### Fallbacks when a built-in is gone
Actions that used a fixed category now fall back to the first remaining category if theirs was deleted: default category on a new entry (Groceries), trip spending (Travel & events), buying a planned purchase (Shopping), a newly added bill (Utilities).

### iPhone (now editable on the phone too)
Entry points on the Budget screen: tap any category row, or the new full-width outline button **"+ New category"** (52px, radius 18px, 1.5px black border) under the last group, with the hint "Tap a category to rename it, change its limit or delete it." beneath it.

Both open the existing bottom sheet (cream, radius 30px top corners, slides up .3s), now with:
1. Small label: "Edit category" / "New category" (pocket money: "Monthly limit" + the fixed name in 24px, nothing else new).
2. **Name** — white input, 52px, radius 16px, 18px/500, placeholder "Category name", 2px black focus ring.
3. **Group** — two equal chips, Needs / Wants (44px, radius 22px; selected = black fill, white text).
4. "Monthly limit" label, then the existing −/+ stepper (±50) around the 52px number.
5. Info line; error line (13px/600, `#b3352b`).
6. Buttons: "3-month avg · X" (outline) and **Save** (black).
7. **"Delete category"** — text button, 44px, `#b3352b` (hidden for new and pocket-money categories).

Delete replaces the sheet content in place (no second sheet): label "Delete category", title "Delete {name}?", the same usage sentence as web, a wrapping chip list — "Leave uncategorised" first so it is always visible, then every other category, all shown at once with no inner scroll area (if the sheet outgrows the screen, the whole sheet scrolls, capped at 94% of the screen height), the uncategorised note, then **"Keep it"** (outline) and **"Delete"** (fill `#c23b30`, white). Rules, validation messages and data effects are identical to web. New categories default to Needs with a limit of 0.

On the Duo the sheet covers the left pane only; the right pane keeps showing its detail.

## 6. App icon (new)

Files are in `app-icon/`:
- `twofold-icon.svg` — master, 1024×1024, full-bleed square (no rounded corners baked in; iOS and Android apply their own mask).
- `twofold-icon-1024.png`, `-512.png`, `-180.png` — raster exports.
- `twofold-icon-preview.png` — how it looks masked at 400, 180, 120, 60 and 40px. Reference only.

**The mark:** two panels opened like a fold — the left in lavender `#b9b0ff`, the right in cream `#fbf9ef` — on black `#0b0b0c`. Each panel carries one black pill (bottom of the left, top of the right), echoing the loose pills in the app's blob edge and standing for the two partners. Corners are rounded with a 56-unit round join; the artwork is scaled 1.16× about the centre.

**Use:**
- iOS app icon: generate the full asset catalogue from the 1024 master.
- Android adaptive icon: black background layer; the two panels as the foreground layer, scaled down to sit inside the 66% safe zone.
- Web: favicon and PWA icons (512, 180) from the same master.
- Do not add a gradient, shadow, wordmark or outline. Do not recolour the panels.

## 7. Edit and delete savings pots

No data model change (pots are `goals[]`: `{id, name, target, saved, monthly, acct, due, auto}`).

### Web (`Tandem Budget.dc.html`, Savings tab)
Editing and deleting already existed but was only reachable by clicking the pot's name, which looked like plain text. Each pot card now has an explicit **"Edit"** outline pill (44px, radius 22px, 1.5px border, 13.5px/500) in the card's top-right corner, above the big percentage. It opens the existing pot side panel (Name, Target, Auto-save each payday, Needed by, Kept in) which has **Delete** in its footer. The pot name stays clickable too.

### iPhone (`TandemScreen.dc.html`, Savings tab)
- Each pot card gets the same **"Edit"** pill, top-right above the percentage (black 1.5px outline on the lavender field).
- New full-width outline button **"+ New pot"** (52px, radius 18px) under the last pot. Empty state copy is now "No pots yet. Start one for anything you're saving toward."
- Both open a new **pot bottom sheet** (same shell as the category sheet: cream, 30px top radius, grabber, slides up .3s, max-height 94% with the sheet scrolling):
  1. Title "Edit pot" / "New savings pot" (24px/500).
  2. **Name** — white input, 52px, radius 16px, 17px/500, placeholder "e.g. New car".
  3. Two inputs side by side: **Target (currency)** and **Auto-save each payday**, both numeric.
  4. **Kept in** — single-select chips, one per savings account (44px, selected = black fill). If there are no savings accounts: "No savings account yet. Add one in the web app so the pot has a home."
  5. Error line (13px/600, `#b3352b`), then **Save** (black, full width, 54px).
  6. **"Delete pot"** text button (`#b3352b`, 44px) — edit mode only.
- Validation: "Give it a name" · "Add a target amount" (must be > 0) · "Add a savings account on the web first".
- New pots start with 0 saved and auto-save on if a payday amount was entered. Setting the amount to 0 turns auto-save off.
- **Delete** swaps the sheet content in place: label "Delete pot", title "Delete {name}?", then either "AED X is set aside in this pot. The money stays in {account}; it just stops being earmarked." or "Nothing is saved in this pot yet, so it can go straight away.", then **"Keep it"** (outline) and **"Delete"** (`#c23b30`).
- Deleting removes the pot only. Account balances and past transfers are untouched.
- "Needed by" (deadline) is still web-only.
- On the Duo the sheet covers the left pane only.

## Open decisions
- Uncategorised spending is not counted anywhere; consider an "Uncategorised" row in Budget so it stays visible.
- There is no undo or restore for a deleted built-in category.
- Adding and editing assets and investments is web-only; decide whether the phone needs it at launch.
- Asset values are entered by hand and never update on their own; no valuation history is stored. The six-month net worth chart in the prototype is illustrative — production needs monthly snapshots to draw it.
- Loans are not linked to assets (e.g. car loan ↔ car), so there is no per-asset equity figure.

## Files
- `Tandem Budget.dc.html` — web: category edit / delete (`catList`, `saveBudget`, the `budget` branch of `del`, `m.delStep` block in the budget panel); Net worth tab (template block `is.worth`, logic `worth` in `renderVals()`), asset panel (`ITEM.asset`, `m.isAsset`), investment cost (`openAcct` / `saveAcct`), Accounts hero change (`HV.accounts`, `HV.worth`).
- `TandemScreen.dc.html` — phone: Bills calendar card (inside the `ph.is.bills` block), Duo calendar pane (`ph.is.billcal`), Net worth screen (`ph.is.worth`), category sheet (`ph.bs.*`), "+ New category" button, pot sheet (`ph.ps.*`), pot Edit and "+ New pot" buttons.
- `Tandem iPhone.dc.html` — phone logic: calendar cells (`cal`, `bl`), Duo split (`split`, `bI`), category editing (`catList`, `openBudget`, `saveBudget`, `delBudget`, `bs`), pot editing (`openPot`, `savePot`, `delPot`, `ps`), net worth data (`wv`), More rows.
- `TandemDevice.dc.html`, `ios-frame.jsx`, `support.js` — unchanged; needed only to open the prototypes.
