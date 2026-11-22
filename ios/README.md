# Twofold for iPhone

The native SwiftUI version of the Twofold design (previously "Tandem"):
one shared budget for two people, synced between both phones.

- **Screens:** Home (safe to spend, quick actions, coach tips, settle-up, bills coming up,
  transactions), Budget (left to assign / unbudgeted, 50/30/20 check, category limits with
  rollover; rename, regroup, add and delete categories, move money in from another one), Savings
  (pots with Edit / New pot sheets, auto-save switch, deposit/withdraw, round-ups, month-end
  sweep, where extra money goes, recent moves), More → Activity (search, who / account / category
  filters, CSV export), Bills (with this month's calendar), Accounts, Net worth (add and edit
  assets and investments), Debt (payoff plan, loans with their full schedule and payments, credit
  cards with minimums and payoff), Reports (with a CSV download), Plan ahead (30-day cash forecast
  against your cushion, planned purchases with both votes and Mark bought, trips with Log spend),
  Us two (settle-up, who paid, pay, pocket money, money date), Settings; plus the full-screen
  keypad for adding entries and the category / pot bottom sheets. Everything the Mac app can
  create, edit or delete can be done on the phone too.
- **Settings shared with the Mac** (household document): budget style (Zero-based, Category
  limits, 50/30/20), rollover, cash cushion, coach tips, how you share money and the split rule.
  They work the same on both: rollover adds last month's unspent limit to each category, the
  cushion drives Plan ahead, split mode adds settle-up to Us two ("Mark as settled" adds what
  was owed to `settled.{month}`). **Look** (the accent colour) is per phone.
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

## Project layout

```
ios/
  project.yml            XcodeGen spec (Firebase via Swift Package Manager)
  Twofold/
    App/TwofoldApp.swift  entry point, sign-in / household gate
    Model/               Codable models, category catalog, date & money helpers,
                         Ledger (every derived number: safe to spend, balances, …)
    Sync/                Session (auth, create/join household), HouseholdStore (live data + writes)
    UI/                  palette, Geist fonts, blob edge, shared components, router
    Screens/             Home, Budget, Pots, More, details, add entry, forms
    Resources/           Geist fonts (SIL OFL), app icon
```

### Firestore data

```
users/{uid}                      { householdId }
households/{code}                names, currency, members, budgets, incomes, checks, round-ups
households/{code}/tx/{id}        entries (expense / income / transfer, pot moves; loan payments carry debtId, debtPart)
households/{code}/accounts/{id}  opening balance + details (cards: limit, apr, statementDay, dueDay, minPct, minFloor)
households/{code}/bills/{id}     day, amount, category, paid months (a loan's bill carries debtId)
households/{code}/goals/{id}     pots: target, starting amount, monthly, account
households/{code}/debts/{id}     loans: kind, lender, principal, rate, rateType, termMonths, firstDue,
                                 installment, paidBefore, rateChanges, fee, acct, billId
                                 (+ legacy balance, apr, min kept up to date for older builds)
households/{code}/planned/{id}   planned purchases with each partner's vote
households/{code}/events/{id}    trips and events: budget, spent
households/{code}/assets/{id}    home, car, gold …: name, kind, value (missing = none)
```

The household document also holds your own categories (`custom`), renamed or regrouped
built-in categories (`catOv`: id → name and group), removed built-ins (`catDel`) and the debt
plan settings (`strat`, `extra`), the shared settings (`budgetStyle`, `rollover`, `cushion`,
`coachTips`, `splitMode`, `splitRule`, `settled`, `roundUps`, `sweep`; missing = the default).
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

Deleting a category can move its entries and bills to another
one (written in batches of at most 450); otherwise they show as "Other" and count towards no budget.

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
