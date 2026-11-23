// Screen state shared by the shell, the tabs and the side panels.
import { createContext, useContext, type FC } from 'react'
import type { Ledger } from '../data/ledger'
import type { Account, AccountType, Goal, Trip, Tx, Who } from '../data/types'

export type TabId = 'home' | 'activity' | 'budget' | 'bills' | 'accounts' | 'worth' | 'savings' | 'goals' | 'reports' | 'plan' | 'us'

export const TABS: [TabId, string][] = [
  ['home', 'Today'], ['activity', 'Activity'], ['budget', 'Budget'], ['bills', 'Bills'], ['accounts', 'Accounts'],
  ['worth', 'Net worth'], ['savings', 'Savings'], ['goals', 'Debt'], ['reports', 'Reports'], ['plan', 'Plan ahead'], ['us', 'Us two'],
]

/** Filters and selections that both the header and a tab body use. */
export interface ViewState {
  q: string
  fWho: 'all' | Who
  fCat: string
  fAcct: string
  selAcct: string | null
}

/** Which side panel is open. Each slides in from the right. `back` is the panel that
 *  comes back when this one closes (an entry opened from a loan returns to the loan). */
export type Panel =
  | { kind: 'tx'; tx?: Tx; pre?: Partial<Tx>; back?: Panel }
  | { kind: 'budget'; cat: string }
  | { kind: 'cat' }
  | { kind: 'contrib'; trip: Trip }
  | { kind: 'item'; item: 'income' | 'bill' | 'planned' | 'event'; who?: Who; id?: string }
  /** A loan: summary, schedule, payments (the wide panel). A card installment plan opens its own version. */
  | { kind: 'loan'; id: string }
  /** New / edit card installment plan (`acct` picks the card for a new one). */
  | { kind: 'planForm'; id?: string; acct?: string; back?: Panel }
  /** New / edit loan. */
  | { kind: 'loanForm'; id?: string; back?: Panel }
  | { kind: 'pot'; goal?: Goal }
  /** `preset` picks the type for a new account ("+ Add investment"). */
  | { kind: 'acct'; acct?: Account; preset?: AccountType }
  | { kind: 'asset'; id?: string }
  | { kind: 'settings' }
  /** Statement import (CSV, Excel, PDF): a file dropped on the window, or chosen in the panel. */
  | { kind: 'import'; file?: File; acct?: string }

export interface UI {
  tab: TabId
  go(tab: TabId): void
  ym: string
  setYm(ym: string): void
  view: ViewState
  setView(patch: Partial<ViewState>): void
  panel: Panel | null
  open(p: Panel): void
  /** Closes the panel, or goes back to the one it was opened from. */
  close(): void
  /** Closes the panel and anything it was opened from. */
  closeAll(): void
  /** A note at the bottom for ~5 s, with Undo when `undo` is given. */
  toast(text: string, undo?: () => void): void
  /** Right-click menu at the pointer. */
  menu(m: MenuSpec | null): void
}

export interface MenuItem { label: string; run(): void; bad?: boolean }
export interface MenuSpec { x: number; y: number; items: MenuItem[] }

export const UICtx = createContext<UI | null>(null)
export const useUI = () => useContext(UICtx)!

/** One bar in the header chart. */
export interface HeroBar { h: string; bg: string; label?: string; tag?: string; title?: string; h2?: string; bg2?: string }

/** The big black header figure shown on every tab except Today. */
export interface HeroSpec {
  label: string
  /** show the currency before the number */
  cur?: boolean
  num: string
  fg: string
  sub?: string
  stats?: [string, string][]
  bars?: HeroBar[]
}

/** What each tab file exports. */
export interface TabDef {
  id: TabId
  /** 'lav' for Today, Accounts, Savings and Us two; 'cream' for the rest. */
  stage: 'cream' | 'lav'
  kicker(L: Ledger): string
  hero?(L: Ledger, view: ViewState): HeroSpec | null
  /** Extra controls under the hero in the black header (Activity search, Reports downloads). */
  Header?: FC<{ L: Ledger }>
  Body: FC<{ L: Ledger }>
}
