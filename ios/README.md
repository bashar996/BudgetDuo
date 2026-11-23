# Twofold for iPhone

The native SwiftUI version of the Twofold design (previously "Tandem"):
one shared budget for two people, synced between both phones.

- **Screens:** Home (safe to spend, quick actions, coach tips, settle-up, bills coming up,
  transactions), Budget (left to assign / unbudgeted, 50/30/20 check, category limits with
  rollover; rename, regroup, add and delete categories, move money in from another one), Savings
  (pots with Edit / New pot sheets, auto-save switch, deposit/withdraw, round-ups, month-end
  sweep, where extra money goes, recent moves), More → Activity (search, who / account / category
  filters, CSV export, statement import), Bills (with the budget month's calendar), Accounts, Net worth (add and edit
  assets and investments), Debt (payoff plan, loans with their full schedule and payments, credit
  cards with minimums and payoff, card installment plans), Reports (with a CSV download), Plan ahead (30-day cash forecast
  against your cushion, planned purchases with both votes and Mark bought, trips with Log spend),
  Us two (settle-up, who paid, pay, pocket money, money date), Settings; plus the full-screen
  keypad for adding entries and the category / pot bottom sheets. Everything the Mac app can
  create, edit or delete can be done on the phone too.
- **Settings shared with the Mac** (household document): budget style (Zero-based, Category
  limits, 50/30/20), the day the budget month starts, rollover, cash cushion, coach tips, how you
  share money and the split rule.
  They work the same on both: rollover adds last month's unspent limit to each category, the
  cushion drives Plan ahead, split mode adds settle-up to Us two ("Mark as settled" adds what
  was owed to `settled.{month}`). **Look** (the accent colour) is per phone.
- **Budget month** (Settings → "Budget month starts on day", 1–28, written as the integer
  `cycleStart`; missing = 1 = calendar months): e.g. 25 makes each budget month run 25th → 24th.
  `Model/Period.swift` holds the rules (the same as the Mac's `desktop/src/lib/period.ts`): a
  budget month keeps a "yyyy-MM" key, named after the month most of its days are in (start 25:
  "2026-12" is 25 Nov – 24 Dec; start 10: "2026-11" is 10 Nov – 9 Dec), so `checks`,
  `roundSwept` and `settled` stay keyed the same way. Everything "this month" follows it (spent,
  safe to spend and the per-day figure, rollover, coach tips, Home, Us two, Reports, Savings'
  "moved in", round-ups, Activity's month arrows); headings show the month name plus the range
  when the start isn't the 1st. Each bill is due once per budget month (its day inside the
  range); its `paid` flag and payment entry id (`bill-{billId}-{yyyy-MM}`) use the calendar month
  of that due date, so existing data keeps working. Pay days, loans, cards and the 30-day
  forecast stay on calendar dates.
- **Look:** black, lavender (or the accent you pick) and cream with the stepped blob edges, Geist type.
- **Wide screens** (an unfolded foldable): budget and tabs on the left, the detail on the right;
  the keypad screen uses both halves (all categories in a grid on the left, chips and keypad on the right).
  Bills opened from the left pane puts the calendar on the left and the list on the right.
  There's one **Back** for both panes, a round button low in the tab rail's column on the right
  edge (thumb reach when unfolded); it undoes the latest step in either pane (a pushed screen,
  the right pane switching screens, or the bills calendar opening). The panes have no back
  arrows of their own; swipe back still works. Bills and Accounts dock their Add button at the
  bottom of the right pane.
- **Empty start:** the Home screen shows "Start here" steps (accounts → pay → limits → first entry)
  that tick off as you go.

## Sync and what it costs

| Piece | Service | Cost for the two of you |
| --- | --- | --- |
| Sync + offline cache | Firebase Firestore, **Spark (free) plan** | $0. Free tier is 50,000 reads and 20,000 writes a day; two people use a few hundred. |
| Sign-in | Firebase Authentication (email + password) | $0 |
| Getting the app on your phones | Xcode on a Mac | $0 with a free Apple ID, but the app stops opening after **7 days** and must be re-installed from the Mac. |
| | Apple Developer Program | $99/year: TestFlight builds that last 90 days and auto-update, no Mac needed day-to-day. |

Never upgrade Firebase to the Blaze plan; Spark can't bill you anything.

How sync works: each phone keeps a full local copy (works offline) and Firestore pushes
changes to the other phone within a second or two. Balances and pot totals are **worked out
from the entries**, never stored, so editing on both phones at once can't make them disagree.
Paying a bill uses a fixed entry ID per bill and month, so tapping Pay on both phones doesn't
count it twice.

## One-time setup (about 15 minutes)

### 1. Firebase project (free)

1. Go to <https://console.firebase.google.com>, **Add project**, name it e.g. `tandem`
   (Google Analytics: off).
2. **Build → Authentication → Get started → Email/Password → Enable**.
3. **Build → Firestore Database → Create database** → production mode → pick a region near you
   (e.g. `europe-west` or `me-central1`).
4. Still in Firestore, open **Rules**, replace everything with the contents of
   [`firestore.rules`](../firestore.rules) (at the top of the repository) and **Publish**.
5. **Project settings → Your apps → iOS (+)**. Bundle ID: `app.tandem.budget` (or your own;
   change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to match). Download
   **GoogleService-Info.plist** and put it at `ios/Twofold/Resources/GoogleService-Info.plist`.
   It's git-ignored.

### 2. Build on a Mac

Needs Xcode 15.3 or newer (iOS 17+ on the phones).

```sh
brew install xcodegen
cd ios
xcodegen            # creates Twofold.xcodeproj from project.yml
open Twofold.xcodeproj
```

In Xcode: select the **Twofold** target → **Signing & Capabilities** → choose your Team
(your Apple ID works). Plug in a phone, pick it as the run destination and press **Run**.
The first build downloads the Firebase SDK through Swift Package Manager.
On the phone, allow the developer in **Settings → General → VPN & Device Management**
the first time.

Repeat for the second phone (or share via TestFlight if you have the paid account).

### 3. First run

1. Person 1: **Create account** → **Start new** → enter both names and the currency.
2. Home shows an **Invite** card with an 8-character code; tap **Share**.
3. Person 2: **Create account** → **Join with a code** → enter the code.
4. Work through **Start here**: add accounts, set pay (Budget → Income, or More → Us two),
   give categories a limit (Budget tab, tap a category), log a first entry (+).

## iPad

The same app runs on iPad (it's a universal app; one install from Xcode or TestFlight
covers both). On an iPad, or in Split View / Stage Manager when the window is at least
700 points wide, it uses the two-pane layout: tabs and lists on the left, the detail on the
right, and the add-entry keypad across both halves. Narrower windows get the iPhone layout.
iPad supports every orientation; each pane keeps its own back arrow (the single docked
Back by the tab rail is only used on the unfolded iPhone Duo).

To run it: pick an iPad (or an iPad simulator) as the run destination in Xcode.

## Project layout

```
ios/
  project.yml            XcodeGen spec (Firebase via Swift Package Manager)
  Twofold/
    App/TwofoldApp.swift  entry point, sign-in / household gate
    Model/               Codable models, category catalog, date & money helpers,
                         Ledger (every derived number: safe to spend, balances, …)
    Import/              statement import, pure Swift: CSV, .xlsx (small ZIP reader + inflate), PDF text,
                         columns, dates, amounts, names, categories, duplicates (same rules as the Mac)
    Sync/                Session (auth, create/join household), HouseholdStore (live data + writes)
    UI/                  palette, Geist fonts, blob edge, shared components, router
    Screens/             Home, Budget, Pots, More, details, add entry, forms
    Resources/           Geist fonts (SIL OFL), app icon
```

### Firestore data

```
users/{uid}                      { householdId }
households/{code}                names, currency, members, budgets, incomes, checks, round-ups
households/{code}/tx/{id}        entries (expense / income / transfer, pot moves; loan payments and card plan entries carry debtId, debtPart;
                                 imported ones carry importId and source "import")
households/{code}/accounts/{id}  opening balance + details (cards: limit, apr, statementDay, dueDay, minPct, minFloor)
households/{code}/bills/{id}     day, amount, category, paid months (a loan's bill carries debtId)
households/{code}/goals/{id}     pots: target, starting amount, monthly, account
households/{code}/debts/{id}     loans: kind, lender, principal, rate, rateType, termMonths, firstDue,
                                 installment, paidBefore, rateChanges, fee, acct, billId
                                 (+ legacy balance, apr, min kept up to date for older builds);
                                 card installment plans: kind "cardplan", acct = the card, cat, procFee, billedThrough
households/{code}/planned/{id}   planned purchases with each partner's vote
households/{code}/events/{id}    trips and events: budget, spent
households/{code}/assets/{id}    home, car, gold …: name, kind, value (missing = none)
```

The household document also holds your own categories (`custom`), renamed or regrouped
built-in categories (`catOv`: id → name and group), removed built-ins (`catDel`) and the debt
plan settings (`strat`, `extra`), the shared settings (`budgetStyle`, `rollover`, `cushion`,
`coachTips`, `splitMode`, `splitRule`, `settled`, `roundUps`, `sweep`, `cycleStart`; missing = the default).
Investment accounts may carry `cost`, the amount put in, so Net worth can show the gain.
Loan payments (`debtId`) don't count as everyday spending: they're left out of round-ups, the
forecast's daily average and the last-7-days chart, as on the Mac.

Loans and cards: `Model/Loans.swift` is a port of the Mac's `desktop/src/data/loans.ts` (same
functions and formulas), so both apps show the same numbers. A loan's outstanding balance is
never stored: it's replayed from the schedule, `paidBefore` and its payment entries (expenses
with `debtId`, `debtPart` "installment" or "extra"). Extra payments keep the installment and shorten
the loan; a rate change re-works the installment so the loan still ends when it would have. Deleting a payment in Activity undoes it.
"Show installments in Bills" keeps a linked bill (`billId` / `debtId`); paying that bill logs the
installment. Card minimums are `minPct`% of what's owed but at least `minFloor` (defaults 5% and
100; APR 36%). Entries can be deleted from any list (touch and hold → Delete), with Undo for 5 s
that restores the same entry id.

### Card installment plans

A purchase the bank split into monthly installments on a credit card (Easy Payment Plan, Flexi
installments …): Debt → a card → **+ Installment plan** (or a card's entries, from Accounts). It's
a `debts/{id}` document with `kind: "cardplan"` and `acct` = the card, so the loan maths is reused
(rate 0 and "flat" by default). The budget counts **one installment a month** in the plan's
category (`cat`, Shopping by default), not the full price:

- Each installment n is posted by the app as an expense on the card: id `plan-{planId}-{n}`, dated
  `nthDue(firstDue, n − 1)`, `debtId` = the plan, `debtPart` "installment", amounts rounded so they add
  up to the total (1,000 over 3 → 333.33, 333.34, 333.33). The same batch sets `billedThrough = n`.
  `HouseholdStore.billPlans` runs when entries, loans or accounts change and when the day changes
  (checked every minute and when the app comes to the front), only once all three collections have
  synced from the server, and skips a plan whose last write hasn't come back yet. Both phones and
  the Mac write identical documents, so nothing doubles; a deleted installment isn't posted again.
- A processing fee (`procFee`) is posted once when the plan is added (`plan-{id}-fee`, `debtPart`
  "fee": linked to the plan but not a payment). **Close early** posts the quote (what's left ×
  (1 + fee %)) as `plan-{id}-close` (`debtPart` "extra"); billing then stops. Editing never rewrites
  posted entries.
- The card's numbers (`Loans.cardWithPlans`): owed = what's on the card + what its plans still have
  to bill (the bank blocks it), and the limit used counts both; the minimum = the usual minimum on
  the rest + this cycle's installments in full. In the payoff plan each plan is its own line; Net
  worth counts the remaining plan amount under the card. Plans never show in Bills or the Loans list.
- Statement import: a card line matching a posted installment (amount ±1%, date ±5 days, and the
  plan's name or "EPP", "IPP", "INSTAL…", "EASY PAYMENT", "FLEXI" in the description) is "Already in
  Twofold". An existing entry with a `debtId` also counts towards the usual duplicate rule.

Deleting a category can move its entries and bills to another
one (written in batches of at most 450); otherwise they show as "Other" and count towards no budget.

## Statement import

Activity → **Import** (or **Import statement** on an account's card) opens the Files picker for a
CSV, Excel (.xlsx) or PDF statement, then a full-screen flow: which account it's for → the PDF's
password if it has one → the columns (picked automatically, changeable, with a preview and a
"money out is negative / positive" choice when the file doesn't say) → the review list (tick, date,
name, amount, category, who, status; filters All / New / Duplicates / Needs category; set a category
for everything ticked) → **Import n entries**, with Undo for 8 s. Activity then shows that account.

- The rules are a port of the Mac's `desktop/src/import/` (same header words, date and amount
  formats, name clean-up, keyword categories, bill / loan / transfer / card-payment / refund
  handling). Money out on a card is an expense on the card; a payment to the card is offered as a
  transfer from the current account.
- Each entry gets `importId` = `"imp_"` + lowercase hex of the first 8 bytes of SHA-256 of
  `"{accountId}|{yyyy-MM-dd}|{amount, 2 decimals, - for money out}|{description, upper case, single spaces, trimmed}|{n}"`
  (n counts identical lines earlier in the file, from 0), the same on the Mac, so a statement
  imported on one device shows as "Already imported" on the other. Likely duplicates (same amount
  within 3 days on the same account, plus same date, a similar name, a bill payment or the same
  category) are unticked.
- A bill match uses the bill's fixed entry id (`bill-{billId}-{ym}`) and marks the bill paid; a loan
  installment match carries `debtId`. Writes go in batches of at most 450. Undo deletes exactly
  those entries and marks unpaid the bills the import marked paid.
- The column mapping and sign choice are remembered per account and file layout on this phone
  (UserDefaults `twofold.importMap.{accountId}`).
- Not supported: old binary .xls (save as .xlsx or CSV; HTML tables named .xls do work), scanned
  PDFs without text, password-protected spreadsheets. PDF reading is best effort (PDFKit's page
  text), so check the review list.

## Differences from the design

- The design creates loans, planned purchases, trips and assets on the web only; the phone can
  create and edit them too.
- Round-ups only show their "Move" card once switched on under Savings → Ways you save (the
  `roundUps` setting the Mac uses).
- The pot sheet keeps a "Round-ups go to this pot" switch, which isn't in the design.
- The bundle ID stays `app.tandem.budget` because that's what is registered in Firebase;
  nobody sees it.

## Other apps

The Mac app lives in [`desktop/`](../desktop) and shares the same Firestore data.
