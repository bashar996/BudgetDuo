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

/** Which side panel is open. Each slides in from the right. */
export type Panel =
  | { kind: 'tx'; tx?: Tx; pre?: Partial<Tx> }
  | { kind: 'budget'; cat: string }
  | { kind: 'cat' }
  | { kind: 'contrib'; trip: Trip }
  | { kind: 'item'; item: 'income' | 'bill' | 'debt' | 'planned' | 'event'; who?: Who; id?: string }
  | { kind: 'pot'; goal?: Goal }
  /** `preset` picks the type for a new account ("+ Add investment"). */
  | { kind: 'acct'; acct?: Account; preset?: AccountType }
  | { kind: 'asset'; id?: string }
  | { kind: 'settings' }

export interface UI {
  tab: TabId
  go(tab: TabId): void
  ym: string
  setYm(ym: string): void
  view: ViewState
  setView(patch: Partial<ViewState>): void
  panel: Panel | null
  open(p: Panel): void
  close(): void
}

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
