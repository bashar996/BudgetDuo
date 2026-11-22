// Same Firestore documents as the iPhone app (ios/Twofold/Model/Models.swift).
// Balances and pot totals are never stored: they are worked out from entries.
import type { LoanDoc } from './loans'

export type Who = 'A' | 'B' | 'J'
export type TxType = 'exp' | 'inc' | 'xfer'
export type AccountType = 'current' | 'cash' | 'card' | 'save' | 'invest'

export interface Income { who: Who; amt: number; day: number }
export interface CustomCategory { id: string; name: string; g: 'needs' | 'wants' }
export type AssetKind = 'property' | 'vehicle' | 'gold' | 'business' | 'other'

/** households/{code} */
export interface Household {
  nameA: string
  nameB: string
  currency: string
  members: string[]
  memberWho: Record<string, Who>
  budgets: Record<string, number>
  incomes: Income[]
  checks: Record<string, boolean>
  roundSwept: Record<string, number>
  roundUpPot?: string | null
  custom?: CustomCategory[]
  /** Renamed / moved built-in categories. */
  catOv?: Record<string, { name: string; g: 'needs' | 'wants' }>
  /** Built-in categories the household removed. */
  catDel?: string[]
  strat?: 'avalanche' | 'snowball'
  extra?: number
  // Settings from the web design, shared by both of you:
  budgetStyle?: 'Zero-based' | 'Category limits' | '50/30/20'
  rollover?: boolean
  cushion?: number
  coachTips?: boolean
  splitMode?: 'One joint pot' | 'Split shared costs'
  splitRule?: '50/50' | 'By income'
  /** "YYYY-MM" → amount already settled (A owes B is negative) */
  settled?: Record<string, number>
  roundUps?: boolean
  sweep?: boolean
}

/** households/{code}/tx/{id} */
export interface Tx {
  id: string
  date: string
  name: string
  cat: string
  amt: number
  who: Who
  type: TxType
  note?: string | null
  billId?: string | null
  /** Loan payment: the loan it pays, and whether it's the installment or an extra payment. */
  debtId?: string | null
  debtPart?: 'installment' | 'extra' | null
  acct: string
  to?: string | null
  pot?: string | null
  potDir?: 'in' | 'out' | null
  createdAt?: Date | null
}

/** households/{code}/accounts/{id}; live balance = opening + entries */
export interface Account {
  id: string
  name: string
  type: AccountType
  who: Who
  bank?: string | null
  last4?: string | null
  opening: number
  limit?: number | null
  apy?: number | null
  apr?: number | null
  /** Investments only: the amount put in; gain = balance − cost. */
  cost?: number | null
  // Credit cards only (see loans.ts cardState; defaults in CARD_DEFAULTS):
  statementDay?: number | null
  dueDay?: number | null
  minPct?: number | null
  minFloor?: number | null
  createdAt?: Date | null
}

/** households/{code}/assets/{id}: things owned outside an account, valued by hand. */
export interface Asset { id: string; name: string; kind: AssetKind; value: number; createdAt?: Date | null }

/** households/{code}/bills/{id} */
export interface Bill {
  id: string; day: number; name: string; amt: number; cat: string; sub: boolean; paid: Record<string, boolean>
  /** Set when the bill shows a loan's installment (paying it pays the loan). */
  debtId?: string | null
}

/** households/{code}/goals/{id}; saved = startSaved + pot moves */
export interface Goal {
  id: string
  name: string
  target: number
  startSaved: number
  monthly: number
  acct: string
  due?: string | null
  auto?: boolean
  createdAt?: Date | null
}

/** households/{code}/debts/{id}: a loan. Its fields and maths live in loans.ts. */
export type Debt = LoanDoc
export interface Planned { id: string; name: string; cost: number; A: boolean; B: boolean; createdAt?: Date | null }
export interface Trip { id: string; name: string; when: string; budget: number; spent: number; createdAt?: Date | null }

export interface Data {
  household: Household
  tx: Tx[]
  accounts: Account[]
  bills: Bill[]
  goals: Goal[]
  debts: Debt[]
  planned: Planned[]
  trips: Trip[]
  assets: Asset[]
}
