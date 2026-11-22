# Twofold for Mac

The desktop version of Twofold, built from the web design (`design/Tandem Budget.dc.html`)
and wrapped as a Mac app with Electron. It uses the **same Firebase project and the same
sign-in** as the iPhone app, so everything you add on one shows on the other.

- Sidebar island (collapsible), month switcher, "+ Add entry".
- Ten tabs: Today, Activity, Budget, Bills, Accounts, Savings, Debt, Reports, Plan ahead, Us two.
- Every add/edit form is a side panel.
- Reports download as a print-ready HTML file (print to PDF from there) or CSV.
- Settings (bottom of the sidebar): names, currency, budget style, rollover, cash cushion,
  coach tips, split mode, theme (Paper / Night), accent colour, invite code, sign out.
- Works offline; changes sync when you're back online.

## One-time setup

### 1. Add a web app to your Firebase project (2 minutes, free)

1. Firebase console → your project → ⚙ **Project settings** → **Your apps** → **Add app** → the
   **web** icon `</>`.
2. Nickname: `Twofold Mac`. Leave "Firebase Hosting" unticked. **Register app**.
3. Firebase shows a `firebaseConfig = { … }` block. Keep it handy: the first time you open
   Twofold it asks you to paste that block in. It's remembered on that Mac.

Email/password sign-in and the Firestore rules are the ones you already set up for the iPhone.

(Optional, instead of pasting: save the values as `desktop/src/firebase.config.json`, shaped like
`firebase.config.example.json`, before building. That file is git-ignored.)

### 2. Build the app on your Mac

Needs Node.js 20 or newer: `brew install node` (or download from nodejs.org).

```sh
cd desktop
npm install
npm run dist
```

This makes `desktop/release/Twofold-1.0.0-arm64.dmg` (Apple silicon) and
`Twofold-1.0.0.dmg` (Intel). Open the one for your Mac and drag **Twofold** into
**Applications**.

The app isn't signed with an Apple Developer ID (that needs the $99/year account). Because you
built it yourself on your Mac, macOS opens it normally. If you copy the .dmg to another Mac and
it says the app "can't be opened", right-click the app → **Open** → **Open**.

To try changes without making a .dmg: `npm run app`.

### 3. Sign in

Use the same email and password as on the iPhone. You'll land in the same budget.

## Preview with sample data

`npm run dev`, then open <http://localhost:5173/?demo> in a browser (or `?demo=empty` for a
brand-new household). Nothing is saved in preview.

## How it's put together

```
desktop/
  electron/main.cjs     the Mac window; serves the built app from app://twofold/
  src/
    App.tsx             sign-in, start/join a budget, loads your household
    data/               Firebase sync, actions (every change), ledger (every number), sample data
    shell/              sidebar, header and hero, shared screen state
    tabs/               one file per tab
    panels/             the side panels (add/edit forms, settings)
    lib/                css(), dates, money and CSV helpers
```

Data lives in Firestore exactly as described in `ios/README.md`. Balances and pot totals are
worked out from entries, never stored, so both apps always agree.
