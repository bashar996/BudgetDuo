// Loan and credit-card maths. This file is the reference: the iPhone app's
// Model/Loans.swift is a line-by-line port, so both apps show the same numbers.
//
// Loans are households/{code}/debts/{id}. Payments are ordinary expense entries
// with `debtId` (and `debtPart`: 'installment' | 'extra'), so deleting an entry
// in Activity undoes the payment. Outstanding balance is never stored.
import { addM, dim, pad, ymOf } from '../lib/dates'

export type RateType = 'reducing' | 'flat'

/** The loan document (new fields are optional so older loans still load). */
export interface LoanDoc {
  id: string
  name: string
  kind?: 'personal' | 'car' | 'mortgage' | 'student' | 'other'
  lender?: string | null
  /** Amount borrowed. Missing on loans added before this version (see `balance`). */
  principal?: number | null
  /** Annual rate in %. */
  rate?: number | null
  rateType?: RateType
  termMonths?: number | null
  /** Date of the first installment, "YYYY-MM-DD"; its day is the payment day. */
  firstDue?: string | null
  /** The bank's installment; empty → calculated. */
  installment?: number | null
  /** Installments paid before the loan was added to Twofold. */
  paidBefore?: number | null
  /** Variable rate: from that month on ("YYYY-MM"), the new annual %. */
  rateChanges?: { from: string; rate: number }[] | null
  /** Early-settlement fee in % of the outstanding principal. */
  fee?: number | null
  /** Account the installments come out of. */
  acct?: string | null
  /** Linked bill that shows the installment under Bills. */
  billId?: string | null
  // Older, simple loans (and kept up to date for older app versions):
  balance: number
  apr: number
  min: number
  createdAt?: Date | null
}

export interface LoanPayment { date: string; amt: number; part: 'installment' | 'extra' }

export interface ScheduleRow {
  n: number
  date: string
  payment: number
  interest: number
  principal: number
  balance: number
  /** paid (counted in paidBefore or by a payment entry) */
  paid: boolean
}

export interface LoanState {
  /** Outstanding principal today. */
  balance: number
  principal: number
  rate: number
  rateType: RateType
  /** For flat loans, the reducing-balance rate that costs the same. */
  effectiveRate: number
  installment: number
  termMonths: number | null
  installmentsPaid: number
  installmentsLeft: number
  /** Principal repaid, 0..1 */
  progress: number
  paidSoFar: number
  interestPaid: number
  interestLeft: number
  totalLeft: number
  /** "YYYY-MM-DD" of the next installment, or null when paid off. */
  nextDue: string | null
  /** "YYYY-MM" of the last installment at the current pace. */
  endsYm: string | null
  /** Interest over the whole loan as originally agreed. */
  totalInterest: number
  settlement: number
  schedule: ScheduleRow[]
  /** True for older loans without amount borrowed / term / first date. */
  simple: boolean
}

const MAX = 600

/** Same day each month, clamped to the month's length. */
export function nthDue(firstDue: string, k: number): string {
  const ym = addM(firstDue.slice(0, 7), k)
  const day = Math.min(Number(firstDue.slice(8, 10)) || 1, dim(ym))
  return ym + '-' + pad(day)
}

/** Equal monthly installment on a reducing balance. */
export function emi(principal: number, ratePct: number, months: number): number {
  if (months <= 0) return principal
  const r = ratePct / 1200
  if (r === 0) return principal / months
  return (principal * r) / (1 - Math.pow(1 + r, -months))
}

/** Flat rate: interest on the full amount borrowed for the whole term. */
export function flatInstallment(principal: number, ratePct: number, months: number): number {
  return months > 0 ? principal / months + (principal * ratePct) / 1200 : principal
}

/** The reducing rate with the same installment as a flat-rate loan. */
export function flatToReducing(ratePct: number, months: number): number {
  if (months <= 0 || ratePct <= 0) return ratePct
  const target = flatInstallment(1, ratePct, months)
  let lo = 0, hi = 200
  for (let i = 0; i < 80; i++) {
    const mid = (lo + hi) / 2
    if (emi(1, mid, months) > target) hi = mid; else lo = mid
  }
  return (lo + hi) / 2
}

/** Annual rate for a month, after any rate changes. */
export function rateAt(loan: Pick<LoanDoc, 'rate' | 'apr' | 'rateChanges'>, ym: string): number {
  let r = loan.rate ?? loan.apr ?? 0
  for (const c of [...(loan.rateChanges ?? [])].sort((a, b) => (a.from < b.from ? -1 : 1))) if (c.from <= ym) r = c.rate
  return r
}

export function isSimple(l: LoanDoc): boolean {
  return !(l.principal && l.principal > 0 && l.termMonths && l.termMonths > 0 && l.firstDue)
}

/** Installment: the bank's figure if given, otherwise calculated. */
export function installmentOf(l: LoanDoc): number {
  if (l.installment && l.installment > 0) return l.installment
  if (isSimple(l)) return l.min || 0
  const rate = l.rate ?? l.apr ?? 0
  return (l.rateType ?? 'reducing') === 'flat' ? flatInstallment(l.principal!, rate, l.termMonths!) : emi(l.principal!, rate, l.termMonths!)
}

/**
 * Everything about a loan today.
 * @param payments entries with this loan's debtId, any order
 * @param today    "YYYY-MM-DD"
 */
export function loanState(l: LoanDoc, payments: LoanPayment[], today: string): LoanState {
  const simple = isSimple(l)
  const rateType: RateType = simple ? 'reducing' : l.rateType ?? 'reducing'
  const P = simple ? l.balance : l.principal!
  const n = simple ? null : l.termMonths!
  // Older loans have no first date: assume the month after they were added.
  const added = l.createdAt ?? new Date(today + 'T00:00:00')
  const first = l.firstDue ?? addM(ymOf(added), 1) + '-' + pad(Math.min(28, added.getDate()))
  const baseRate = l.rate ?? l.apr ?? 0
  let inst = installmentOf(l)
  const flatInt = rateType === 'flat' ? (P * baseRate) / 1200 : 0
  const flatPrin = rateType === 'flat' && n ? P / n : 0

  // The schedule as agreed (with rate changes on reducing loans: the installment
  // is recalculated over the remaining months, as banks do).
  const schedule: ScheduleRow[] = []
  let bal = P, instNow = inst, totalInterest = 0
  /** Installment level in force for each period (reducing loans). */
  const instAt: number[] = []
  for (let k = 0; k < (n ?? MAX) && bal > 0.005; k++) {
    const date = nthDue(first, k)
    let interest: number, principal: number
    if (rateType === 'flat') { interest = flatInt; principal = Math.min(bal, flatPrin) }
    else {
      const r = rateAt(l, date.slice(0, 7))
      if (k > 0 && r !== rateAt(l, nthDue(first, k - 1).slice(0, 7)) && n && !(l.installment && l.installment > 0)) instNow = emi(bal, r, n - k)
      instAt.push(instNow)
      interest = (bal * r) / 1200
      principal = Math.min(bal, Math.max(0, instNow - interest))
      if (n && k === n - 1) principal = bal
      if (principal <= 0 && interest > 0) { schedule.push({ n: k + 1, date, payment: interest, interest, principal: 0, balance: bal, paid: false }); break }
    }
    bal -= principal
    totalInterest += interest
    schedule.push({ n: k + 1, date, payment: principal + interest, interest, principal, balance: Math.max(0, bal), paid: false })
  }

  // Replay what's actually been paid.
  const before = Math.max(0, Math.min(l.paidBefore ?? 0, schedule.length))
  bal = before > 0 ? schedule[before - 1].balance : P
  let interestPaid = schedule.slice(0, before).reduce((a, r) => a + r.interest, 0)
  let paidSoFar = schedule.slice(0, before).reduce((a, r) => a + r.payment, 0)
  let count = before
  const sorted = [...payments].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
  for (const p of sorted) {
    if (bal <= 0.005) break
    paidSoFar += p.amt
    if (p.part === 'extra') { bal = Math.max(0, bal - p.amt); continue }
    const interest = rateType === 'flat' ? flatInt : (bal * rateAt(l, p.date.slice(0, 7))) / 1200
    interestPaid += Math.min(interest, p.amt)
    bal = Math.max(0, bal - Math.max(0, p.amt - interest))
    count++
  }
  schedule.forEach((r, i) => (r.paid = i < count))

  // From here on, at the installment the schedule has reached. Extra payments
  // keep the installment and shorten the loan (the usual bank default).
  const recalc = !simple && rateType === 'reducing' && !(l.installment && l.installment > 0)
  if (recalc && instAt.length) inst = instAt[Math.min(count, instAt.length - 1)]
  const instToday = inst
  let b = bal, months = 0, interestLeft = 0
  while (b > 0.005 && months < MAX) {
    const date = nthDue(first, count + months)
    // A future rate change resets the installment so the loan still ends when it
    // would have at the old rate.
    if (recalc && months > 0) {
      const rOld = rateAt(l, nthDue(first, count + months - 1).slice(0, 7)), rNew = rateAt(l, date.slice(0, 7))
      if (rNew !== rOld) inst = emi(b, rNew, monthsToPay(b, rOld, inst))
    }
    const interest = rateType === 'flat' ? (b >= flatPrin - 0.005 ? flatInt : flatInt * (b / (flatPrin || 1))) : (b * rateAt(l, date.slice(0, 7))) / 1200
    const pay = rateType === 'flat' ? Math.min(b, flatPrin) + interest : Math.min(inst, b + interest)
    if (pay - interest <= 0) { months = MAX; break }
    interestLeft += interest
    b -= pay - interest
    months++
  }
  const done = bal <= 0.005
  return {
    balance: bal, principal: P, rate: baseRate, rateType,
    effectiveRate: rateType === 'flat' && n ? flatToReducing(baseRate, n) : baseRate,
    installment: instToday, termMonths: n,
    installmentsPaid: count, installmentsLeft: done ? 0 : months,
    progress: P > 0 ? 1 - bal / P : 1,
    paidSoFar, interestPaid, interestLeft, totalLeft: bal + interestLeft,
    nextDue: done ? null : nthDue(first, count),
    endsYm: done ? null : months >= MAX ? null : nthDue(first, count + months - 1).slice(0, 7),
    totalInterest, settlement: bal * (1 + (l.fee ?? 0) / 100),
    schedule, simple,
  }
}

/** Months to clear `bal` at a fixed annual rate and installment (MAX if never). */
export function monthsToPay(bal: number, ratePct: number, inst: number): number {
  let b = bal, m = 0
  while (b > 0.005 && m < MAX) {
    const i = (b * ratePct) / 1200
    if (inst <= i) return MAX
    b -= inst - i
    m++
  }
  return Math.max(1, m)
}

/**
 * What an extra payment today would save. Worked out by replaying the loan with
 * that payment added, so the preview always matches what happens after paying.
 */
export function prepayEffect(l: LoanDoc, payments: LoanPayment[], today: string, extra: number): { monthsSaved: number; interestSaved: number } {
  const now = loanState(l, payments, today)
  if (extra <= 0 || now.balance <= 0) return { monthsSaved: 0, interestSaved: 0 }
  const then = loanState(l, [...payments, { date: today, amt: Math.min(extra, now.balance), part: 'extra' }], today)
  return {
    monthsSaved: Math.max(0, now.installmentsLeft - then.installmentsLeft),
    interestSaved: Math.max(0, now.interestLeft - then.interestLeft),
  }
}

// MARK: Credit cards (accounts with type 'card')

export interface CardDoc {
  apr?: number | null
  limit?: number | null
  /** Day of the month the statement is made. */
  statementDay?: number | null
  /** Day of the month payment is due. */
  dueDay?: number | null
  /** Minimum payment: this % of the balance… */
  minPct?: number | null
  /** …but at least this much. */
  minFloor?: number | null
}

export interface CardState {
  owed: number
  limit: number | null
  utilisation: number | null
  apr: number
  minDue: number
  /** "YYYY-MM-DD" */
  nextDue: string | null
  nextStatement: string | null
  /** Interest next month if only the minimum is paid. */
  interestIfMin: number
  /** Paying only the minimum each month. */
  minOnly: { months: number; interest: number; never: boolean }
}

export const CARD_DEFAULTS = { apr: 36, minPct: 5, minFloor: 100 }

/** Next date with this day of the month, from today on. */
export function nextDay(day: number, today: string): string {
  const ym = today.slice(0, 7), d = Math.min(day, dim(ym))
  if (Number(today.slice(8, 10)) <= d) return ym + '-' + pad(d)
  const nx = addM(ym, 1)
  return nx + '-' + pad(Math.min(day, dim(nx)))
}

export function minPayment(owed: number, c: CardDoc): number {
  if (owed <= 0) return 0
  const pct = c.minPct ?? CARD_DEFAULTS.minPct, floor = c.minFloor ?? CARD_DEFAULTS.minFloor
  return Math.min(owed, Math.max(floor, (owed * pct) / 100))
}

/** Months and interest to clear `owed`, paying `pay(balance)` each month. */
export function cardPayoff(owed: number, apr: number, pay: (b: number) => number) {
  let b = owed, m = 0, interest = 0
  while (b > 0.005 && m < MAX) {
    const i = (b * apr) / 1200
    const p = Math.min(b + i, pay(b))
    if (p <= i) return { months: MAX, interest, never: true }
    interest += i; b = b + i - p; m++
  }
  return { months: m, interest, never: false }
}

export function cardState(c: CardDoc, balance: number, today: string): CardState {
  const owed = Math.max(0, -balance)
  const apr = c.apr ?? CARD_DEFAULTS.apr
  const minDue = minPayment(owed, c)
  return {
    owed, apr, minDue,
    limit: c.limit ?? null,
    utilisation: c.limit ? owed / c.limit : null,
    nextDue: c.dueDay ? nextDay(c.dueDay, today) : null,
    nextStatement: c.statementDay ? nextDay(c.statementDay, today) : null,
    interestIfMin: ((owed - minDue) * apr) / 1200,
    minOnly: cardPayoff(owed, apr, (b) => minPayment(b, c)),
  }
}
