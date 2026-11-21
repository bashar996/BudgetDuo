# Twofold

A budgeting app for two people sharing one household budget: Bashar & Eman, in AED.
The iPhone app and the Mac app share the same data through Firebase (free plan), so an
entry added on one shows on the other within a second or two.

| Folder | What |
| --- | --- |
| [`ios/`](ios) | iPhone app (SwiftUI). Setup steps in [`ios/README.md`](ios/README.md). |
| [`desktop/`](desktop) | Mac app (Electron). Setup steps in [`desktop/README.md`](desktop/README.md). |
| [`firestore.rules`](firestore.rules) | Firestore security rules: only the two of you can read or change your budget. Paste into Firebase → Firestore → Rules. |
| [`design/`](design) | The Claude Design handoff (HTML prototypes, design notes and the design chat). |
