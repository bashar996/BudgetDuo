// Every derived number the screens show, from the synced documents.
// Mirrors renderVals() in design/Tandem Budget.dc.html, with balances and pot
// totals worked out from entries (like the iPhone app's Ledger.swift).
import { allCategories, catOr as firstOr, type Category } from './catalog'
import type { Account, Bill, Data, Debt, Goal, Tx, Who } from './types'
import { cardWithPlans, isPlan, loanState, minPayment, planState, type CardPlanState, type LoanPayment, type LoanState, type PlanState } from './loans'
import { addDays, addM, dim, isoOf, ymOf } from '../lib/dates'
import { billDue, cycleStartOf, dayIndex, periodKey, periodLabel, periodRange, rangeLabel } from '../lib/period'
import { fmt, num, sum } from '../lib/money'

export interface Row {
  id: string
  g: Category['g']
  name: string
  color: string
  custom: boolean
  variable: boolean
  /** monthly limit as set */
  limit: number
  /** limit plus anything rolled over from last month */
  avail: number
  carry: number
  sp: number
  left: number
  ratio: number
}

/** A bill in the selected period: `due` is its date there, `pm` the calendar month its `paid` flag is keyed by. */
export interface BillRow extends Bill { d: number; due: string; pm: string; isPaid: boolean }
export interface DebtLine { id: string; name: string; balance: number; apr: number; min: number; card?: Account; loan?: boolean }
/** A loan with everything worked out today, its payment entries and its bill. */
export interface LoanLine { doc: Debt; st: LoanState; payments: Tx[]; bill?: Bill }
/** A card installment plan: the loan maths plus what's billed, what's left and what's next. */
export interface PlanLine { doc: Debt; st: LoanState; ps: PlanState; payments: Tx[] }
/** A credit card with its balance, card maths (installment plans included) and its plans. */
export interface CardLine { acct: Account & { balance: number }; cs: CardPlanState; plans: PlanLine[] }

/** A loan's payments for loanState(): every entry with its debtId (a card plan's fee isn't a payment). */
export function loanPayments(tx: Tx[], id: string): LoanPayment[] {
  return tx.filter((t) => t.debtId === id && t.debtPart !== 'fee').map((t) => ({ date: t.date, amt: t.amt, part: t.debtPart === 'extra' ? 'extra' : 'installment' }))
}
export interface DebtPlan { months: number; interest: number; done: Record<string, number>; series: number[]; order: string[] }
export interface CashEvent { i: number; d: Date; name: string; amt: number; late?: boolean; inc?: boolean }

export type Ledger = ReturnType<typeof makeLedger>

/** Debt payoff month by month: interest = balance × APR / 12, pay the minimums,
 *  then the extra plus freed-up minimums go to the first debt in order. */
export function simDebt(debts: DebtLine[], extra: number, strat: string): DebtPlan {
  const ds = debts.map((d) => ({ id: d.id, b: d.balance, apr: d.apr, min: d.min }))
  const order = [...ds].sort(strat === 'snowball' ? (a, b) => a.b - b.b : (a, b) => b.apr - a.apr)
  let months = 0, interest = 0
  const done: Record<string, number> = {}, series = [ds.reduce((a, d) => a + d.b, 0)]
  while (ds.some((d) => d.b > 0.01) && months < 720) {
    months++
    let pool = extra
    ds.forEach((d) => {
      if (d.b > 0.01) { const i = (d.b * d.apr) / 1200; interest += i; d.b += i; const p = Math.min(d.b, d.min); d.b -= p; pool += d.min - p }
      else pool += d.min
    })
    for (const d of order) { if (pool <= 0) break; if (d.b > 0.01) { const p = Math.min(d.b, pool); d.b -= p; pool -= p } }
    ds.forEach((d) => { if (d.b <= 0.01 && !done[d.id]) done[d.id] = months })
    series.push(ds.reduce((a, d) => a + Math.max(0, d.b), 0))
  }
  return { months, interest, done, series, order: order.map((d) => d.id) }
}

/**
 * @param data   everything synced for the household
 * @param ym     the budget month (period key, see lib/period.ts) picked in the header
 * @param today  real today
 */
export function makeLedger(data: Data, ym: string, today = new Date()) {
  const H = data.household
  const A = H.nameA, B = H.nameB, cur = H.currency
  const f = (n: number) => fmt(n, cur)
  // Budget months start on H.cycleStart (1 = calendar months). `ym` and `curYm` are period keys;
  // `calYm` is the calendar month, for month-by-month maths (goal and payoff dates).
  const start = cycleStartOf(H)
  const todayIso = isoOf(today), calYm = ymOf(today), tDay = today.getDate()
  const curYm = periodKey(todayIso, start)
  const pr = periodRange(ym, start)
  const isCur = ym === curYm, days = dayIndex(pr.from, pr.to)
  /** The selected period: first and last day, length, and its name ("November 2026 · 25 Oct – 24 Nov"). */
  const period = { ...pr, days, label: periodLabel(ym, start), range: start > 1 ? rangeLabel(ym, start) : '' }
  const prev = periodRange(addM(ym, -1), start)
  /** Today's day number in the current period, and that period's length. */
  const curP = periodRange(curYm, start)
  const tIdx = dayIndex(curP.from, todayIso), tDays = dayIndex(curP.from, curP.to)
  const day = isCur ? tIdx : ym < curYm ? days : 0
  const daysLeft = isCur ? days - tIdx + 1 : ym > curYm ? days : 0
  const pace = day / days
  const whoName: Record<Who, string> = { A, B, J: 'Joint' }
  const whoCol: Record<Who, string> = { A: 'var(--a)', B: 'var(--b)', J: 'var(--mute)' }
  const rollover = !!H.rollover
  const cushion = H.cushion ?? 5000

  // Balances and pots from entries.
  const bal: Record<string, number> = {}
  data.accounts.forEach((a) => (bal[a.id] = a.opening))
  const saved: Record<string, number> = {}
  data.goals.forEach((g) => (saved[g.id] = g.startSaved))
  for (const t of data.tx) {
    if (t.type === 'exp') bal[t.acct] = (bal[t.acct] ?? 0) - t.amt
    else if (t.type === 'inc') bal[t.acct] = (bal[t.acct] ?? 0) + t.amt
    else {
      bal[t.acct] = (bal[t.acct] ?? 0) - t.amt
      if (t.to) bal[t.to] = (bal[t.to] ?? 0) + t.amt
      if (t.pot) saved[t.pot] = (saved[t.pot] ?? 0) + (t.potDir === 'out' ? -t.amt : t.amt)
    }
  }
  const balance = (a: Account) => bal[a.id] ?? a.opening
  const savedIn = (g: Goal) => Math.max(0, saved[g.id] ?? g.startSaved)
  /** Accounts with their live balance, as the design's `S.accounts`. */
  const accounts = data.accounts.map((a) => ({ ...a, balance: balance(a) }))
  /** Pots with what's in them, as the design's `S.goals`. */
  const goals = data.goals.map((g) => ({ ...g, saved: savedIn(g) }))
  const acctBy: Record<string, (typeof accounts)[number]> = {}
  accounts.forEach((a) => (acctBy[a.id] = a))
  const aName = (id?: string | null) => (id && acctBy[id]?.name) || 'Account'
  const mainAcct = (accounts.find((a) => a.type === 'current') ?? accounts[0])?.id ?? ''

  // Categories and budget rows.
  const cats = allCategories(H)
  /** The category id, or the first remaining one if it was deleted. */
  const catOr = (id: string) => firstOr(cats, id)
  const catBy: Record<string, { name: string; color: string }> = {
    income: { name: 'Income', color: 'var(--good)' },
    transfer: { name: 'Transfer', color: 'var(--mute)' },
  }
  cats.forEach((c) => (catBy[c.id] = c))
  const catOf = (id: string) => catBy[id] ?? { name: 'Other', color: 'var(--mute)' }

  /** Entries in budget month `m` (a period key). */
  const inM = (m: string) => { const r = m === ym ? pr : periodRange(m, start); return data.tx.filter((t) => t.date >= r.from && t.date <= r.to) }
  const byCat = (a: Tx[]) => { const o: Record<string, number> = {}; a.forEach((t) => (o[t.cat] = (o[t.cat] || 0) + t.amt)); return o }
  const desc = (a: Tx, b: Tx) => (a.date < b.date ? 1 : a.date > b.date ? -1 : (b.createdAt?.getTime() ?? 0) - (a.createdAt?.getTime() ?? 0))

  const mtx = inM(ym), exp = mtx.filter((t) => t.type === 'exp'), inc = mtx.filter((t) => t.type === 'inc')
  const spent = byCat(exp)
  const pExp = inM(addM(ym, -1)).filter((t) => t.type === 'exp'), pSpent = byCat(pExp)
  const income = sum(H.incomes, (x) => x.amt)
  const goalsMo = sum(data.goals, (g) => g.monthly)

  const rows: Row[] = cats.map((c) => {
    const limit = H.budgets[c.id] || 0
    const carry = rollover && pExp.length ? limit - (pSpent[c.id] || 0) : 0
    const avail = Math.max(0, limit + carry), sp = spent[c.id] || 0, left = avail - sp
    return { id: c.id, g: c.g, name: c.name, color: c.color, custom: !!c.custom, variable: !!c.variable, limit, avail, carry, sp, left,
      ratio: avail > 0 ? sp / avail : sp > 0 ? 1.01 : 0 }
  })
  const tAvail = sum(rows, (r) => r.avail), tSpent = sum(rows, (r) => r.sp), tLimit = sum(rows, (r) => r.limit)

  // Loans and cards (loans.ts): outstanding balances are worked out, never read from `balance`.
  // Card installment plans are debts too, but they show under their card, not as loans.
  const loans: LoanLine[] = data.debts.filter((d) => !isPlan(d)).map((d) => ({
    doc: d,
    st: loanState(d, loanPayments(data.tx, d.id), todayIso),
    payments: data.tx.filter((t) => t.debtId === d.id).sort(desc),
    bill: data.bills.find((b) => b.debtId === d.id && (!d.billId || b.id === d.billId)),
  }))
  const loanBy: Record<string, LoanLine> = {}
  loans.forEach((l) => (loanBy[l.doc.id] = l))
  const plans: PlanLine[] = data.debts.filter(isPlan).map((d) => {
    const ps = planState(d, loanPayments(data.tx, d.id), todayIso)
    return { doc: d, st: ps.st, ps, payments: data.tx.filter((t) => t.debtId === d.id).sort(desc) }
  })
  const planBy: Record<string, PlanLine> = {}
  plans.forEach((p) => (planBy[p.doc.id] = p))
  const cards: CardLine[] = accounts.filter((a) => a.type === 'card').map((a) => {
    const mine = plans.filter((p) => p.doc.acct === a.id)
    const charges = mine.flatMap((p) => p.payments.filter((t) => t.acct === a.id && t.debtPart !== 'extra'))
    const cs = cardWithPlans(a, a.balance, sum(mine, (p) => p.ps.remaining), charges, todayIso)
    return { acct: a, cs, plans: mine }
  })
  const cardBy: Record<string, CardLine> = {}
  cards.forEach((c) => (cardBy[c.acct.id] = c))

  /** A paid-off loan's bill stops coming due (months it was paid still show). */
  const ended = (b: Bill) => !!b.debtId && !!loanBy[b.debtId] && loanBy[b.debtId].st.balance <= 0.005
  // Each bill's due date inside the period; its paid flag stays keyed by that date's calendar month.
  const billsM: BillRow[] = data.bills.map((b) => { const due = billDue(b.day, ym, start), pm = due.slice(0, 7); return { ...b, due, pm, d: Number(due.slice(8, 10)), isPaid: !!b.paid?.[pm] } })
    .filter((b) => !ended(b) || b.isPaid).sort((a, b) => (a.due < b.due ? -1 : a.due > b.due ? 1 : 0))
  const unpaid = ym >= curYm ? sum(billsM.filter((b) => !b.isPaid), (b) => b.amt) : 0
  const safe = tAvail - tSpent - unpaid
  const leftAssign = income - tLimit - goalsMo

  // Net worth: own = positive balances + assets; owe = loans + accounts below zero.
  const holdings = data.assets ?? []
  const holdSum = sum(holdings, (x) => x.value)
  const posSum = (types: string[]) => sum(accounts.filter((a) => types.includes(a.type) && a.balance > 0), (a) => a.balance)
  const assets = sum(accounts.filter((a) => a.balance > 0), (a) => a.balance) + holdSum
  const liab = sum(loans, (l) => l.st.balance) + sum(plans, (p) => p.ps.remaining) + sum(accounts.filter((a) => a.balance < 0), (a) => -a.balance)
  /** What you own, in four groups (order and colours from the design). */
  const ownGroups: { label: string; v: number; color: string }[] = [
    { label: 'Cash', v: posSum(['current', 'cash', 'card']), color: 'var(--ink)' },
    { label: 'Savings', v: posSum(['save']), color: 'var(--acc)' },
    { label: 'Investments', v: posSum(['invest']), color: 'var(--accText)' },
    { label: 'Property & other assets', v: holdSum, color: 'var(--mute)' },
  ]
  /** Investment accounts with their gain (null when no cost is recorded). */
  const investments = accounts.filter((a) => a.type === 'invest').map((a) => ({ ...a, gain: a.cost && a.cost > 0 ? a.balance - a.cost : null }))
  const withCost = investments.filter((a) => a.gain !== null)
  const invGain = withCost.length ? sum(withCost, (a) => a.gain!) : null

  // Debt plan: loans still owing (at their effective rate and installment), each card plan on its
  // own (what's left to bill, at its installment), plus cards in the red: only what's on the card,
  // at the minimum on that (the plans' installments are already their own lines).
  const allDebts: DebtLine[] = loans.filter((l) => l.st.balance > 0.005).map((l): DebtLine => ({
    id: l.doc.id, name: l.doc.name, balance: l.st.balance, apr: l.st.effectiveRate, min: l.st.installment, loan: true,
  })).concat(plans.filter((p) => p.ps.remaining > 0.005).map((p): DebtLine => ({
    id: p.doc.id, name: p.doc.name, balance: p.ps.remaining, apr: p.st.effectiveRate, min: p.st.installment, loan: true,
  }))).concat(cards.filter((c) => c.cs.owedOnCard > 0).map((c) => ({
    id: c.acct.id, name: c.acct.name, balance: c.cs.owedOnCard, apr: c.cs.apr, min: minPayment(c.cs.owedOnCard, c.acct), card: data.accounts.find((x) => x.id === c.acct.id),
  })))
  const strat = H.strat ?? 'avalanche', extra = H.extra ?? 0
  const debtPlan = simDebt(allDebts, extra, strat)

  // Bills and pay over the next n days (from real today).
  const events = (n: number): CashEvent[] => {
    const out: CashEvent[] = []
    for (let i = 0; i <= n; i++) {
      const d = addDays(today, i), m = ymOf(d), dd = d.getDate(), dm = dim(m)
      data.bills.forEach((b) => {
        if (ended(b)) return
        const bd = Math.min(b.day, dm)
        if (!b.paid?.[m] && (bd === dd || (i === 0 && bd < dd))) out.push({ i, d, name: b.name, amt: -b.amt, late: bd < dd })
      })
      if (i > 0) H.incomes.forEach((x) => { if (x.amt > 0 && Math.min(x.day, dm) === dd) out.push({ i, d, name: whoName[x.who] + '’s salary', amt: x.amt, inc: true }) })
    }
    return out
  }

  // 30-day cash forecast: current + cash accounts, scheduled bills and pay,
  // minus average daily everyday spending over the last 60 days.
  const forecast = () => {
    const cash = sum(accounts.filter((a) => a.type === 'current' || a.type === 'cash'), (a) => a.balance)
    const since = isoOf(addDays(today, -60))
    const varAvg = sum(data.tx.filter((t) => t.type === 'exp' && !t.billId && !t.debtId && t.date >= since), (t) => t.amt) / 60
    const ev = events(30)
    let b = cash
    const series: number[] = []
    for (let k = 0; k <= 30; k++) { ev.filter((e) => e.i === k).forEach((e) => (b += e.amt)); if (k > 0) b -= varAvg; series.push(b) }
    return { cash, series, events: ev, varAvg }
  }

  // Round-ups: each everyday purchase this budget month rounded up to the next 10.
  const roundUps = Math.max(0, Math.round(sum(inM(curYm).filter((t) => t.type === 'exp' && !t.billId && !t.debtId), (t) => Math.ceil(t.amt / 10) * 10 - t.amt) - (H.roundSwept?.[curYm] || 0)))
  const roundUpPot = goals.find((g) => g.id === H.roundUpPot) ?? goals[0]

  return {
    data, H, A, B, cur, f, num, today, tDay, curYm, calYm, ym, isCur, days, day, daysLeft, pace,
    start, period, prev, tIdx, tDays,
    whoName, whoCol, rollover, cushion,
    accounts, goals, acctBy, aName, mainAcct, balance, savedIn,
    cats, catBy, catOf, catOr, inM, byCat, desc,
    mtx, exp, inc, spent, pExp, pSpent, income, goalsMo,
    rows, tAvail, tSpent, tLimit, billsM, unpaid, safe, leftAssign,
    todayIso, loans, loanBy, plans, planBy, cards, cardBy,
    assets, liab, holdings, holdSum, ownGroups, investments, invGain, allDebts, strat, extra, debtPlan,
    events, forecast, roundUps, roundUpPot,
  }
}
