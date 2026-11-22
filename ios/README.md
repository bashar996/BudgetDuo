# Twofold for iPhone

The native SwiftUI version of the Twofold design (previously "Tandem"):
one shared budget for two people, synced between both phones.

- **Screens:** Home (safe to spend, quick actions, bills coming up, transactions), Budget
  (left to assign, category limits, your own categories), Savings (pots, deposit/withdraw,
  round-ups), More → Activity, Bills, Accounts, Debt (payoff plan), Reports (with a CSV download),
  Plan ahead (30-day cash forecast, planned purchases, trips), Us two, Settings; plus the
  full-screen keypad for adding entries and the bottom sheet for category limits.
- **Look:** black, lavender and cream with the stepped blob edges, Geist type, floating tab bar.
- **Wide screens** (an unfolded foldable): budget and tabs on the left, the detail on the right;
  the keypad screen uses both halves (all categories in a grid on the left, chips and keypad on the right).
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
households/{code}/tx/{id}        entries (expense / income / transfer, pot moves)
households/{code}/accounts/{id}  opening balance + details
households/{code}/bills/{id}     day, amount, category, paid months
households/{code}/goals/{id}     pots: target, starting amount, monthly, account
households/{code}/debts/{id}     loans: balance, APR, minimum
households/{code}/planned/{id}   planned purchases with each partner's vote
households/{code}/events/{id}    trips and events: budget, spent
```

The household document also holds your own categories (`custom`) and the debt
plan settings (`strat`, `extra`).

## Differences from the design

- The design creates categories, pots, loans, planned purchases and trips on the web
  only. There's no web app yet, so the phone can create and edit all of them.
- The bundle ID stays `app.tandem.budget` because that's what is registered in Firebase;
  nobody sees it.

## Not built yet

The desktop/web app.
