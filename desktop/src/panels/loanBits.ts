// Wording shared by the Debt tab, the loan panel and the loan form.
import type { Debt } from '../data/types'
import { rateAt, type LoanState } from '../data/loans'
import { dLab, isoD } from '../lib/dates'

export type LoanKind = NonNullable<Debt['kind']>
export const LOAN_KINDS: [LoanKind, string][] = [['personal', 'Personal'], ['car', 'Car'], ['mortgage', 'Mortgage'], ['student', 'Student'], ['other', 'Other']]
const KIND_NAME: Record<LoanKind, string> = { personal: 'Personal loan', car: 'Car loan', mortgage: 'Mortgage', student: 'Student loan', other: 'Loan', cardplan: 'Installment plan' }
export const kindName = (k?: Debt['kind']) => KIND_NAME[k ?? 'other'] ?? 'Loan'

export const r2 = (n: number) => Math.round(n * 100) / 100
/** 3.5 → "3.5%", 6.5844 → "6.6%" */
export const pct = (n: number, dp = 2) => String(Math.round(n * 10 ** dp) / 10 ** dp) + '%'

/** "3.5% flat ≈ 6.6% reducing" · "7.9% reducing" · "5% reducing, now 5.5%" */
export function rateText(l: Debt, st: LoanState, today: string) {
  if (st.rateType === 'flat') return pct(st.rate) + ' flat ≈ ' + pct(st.effectiveRate, 1) + ' reducing'
  const now = rateAt(l, today.slice(0, 7))
  return pct(st.rate) + ' reducing' + (now !== st.rate ? ', now ' + pct(now) : '')
}

/** Lender · kind */
export const loanMeta = (l: Debt) => [l.lender, kindName(l.kind)].filter(Boolean).join(' · ')

/** "48 months" / "4 years" / "4 years 6 months" */
export function termText(m: number) {
  const y = Math.floor(m / 12), r = m % 12
  if (!y) return m + (m === 1 ? ' month' : ' months')
  return y + (y === 1 ? ' year' : ' years') + (r ? ' ' + r + (r === 1 ? ' month' : ' months') : '')
}

/** Days from today to a date (negative when it's passed). */
export const daysTo = (iso: string, today: string) => Math.round((isoD(iso).getTime() - isoD(today).getTime()) / 86400000)

/** Next installment: "Overdue · Wed 26 Nov", "Due today", "Due in 4 days · Wed 26 Nov". */
export function dueText(nextDue: string | null, today: string): { text: string; bad: boolean } {
  if (!nextDue) return { text: 'Paid off', bad: false }
  const n = daysTo(nextDue, today), d = dLab(isoD(nextDue))
  if (n < 0) return { text: 'Overdue · ' + d, bad: true }
  if (n === 0) return { text: 'Due today', bad: true }
  if (n === 1) return { text: 'Due tomorrow · ' + d, bad: false }
  return { text: 'Due in ' + n + ' days · ' + d, bad: false }
}

/** 1 → "1st", 22 → "22nd", 26 → "26th" */
export const ordinal = (n: number) => n + (n % 100 >= 11 && n % 100 <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][n % 10] ?? 'th')
/** Always two decimals, for the schedule table. */
export const n2 = (n: number) => n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
