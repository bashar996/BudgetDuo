// Every derived number the screens show, from the synced documents.
// Mirrors renderVals() in design/Tandem Budget.dc.html, with balances and pot
// totals worked out from entries (like the iPhone app's Ledger.swift).
import { allCategories, catOr as firstOr, type Category } from './catalog'
import type { Account, Bill, Data, Goal, Tx, Who } from './types'
import { addDays, addM, dim, isoOf, ymOf } from '../lib/dates'
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

export interface BillRow extends Bill { d: number; isPaid: boolean }
export interface DebtLine { id: string; name: string; balance: number; apr: number; min: number; card?: Account; loan?: boolean }
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
 * @param ym     the month picked in the header
 * @param today  real today
 */
export function makeLedger(data: Data, ym: string, today = new Date()) {
  const H = data.household
  const A = H.nameA, B = H.nameB, cur = H.currency
  const f = (n: number) => fmt(n, cur)
  const curYm = ymOf(today), tDay = today.getDate()
  const isCur = ym === curYm, days = dim(ym)
  const day = isCur ? tDay : ym < curYm ? days : 0
  const daysLeft = isCur ? days - tDay + 1 : ym > curYm ? days : 0
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

  const inM = (m: string) => data.tx.filter((t) => t.date.slice(0, 7) === m)
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

  const billsM: BillRow[] = data.bills.map((b) => ({ ...b, d: Math.min(b.day, days), isPaid: !!b.paid?.[ym] })).sort((a, b) => a.d - b.d)
  const unpaid = ym >= curYm ? sum(billsM.filter((b) => !b.isPaid), (b) => b.amt) : 0
  const safe = tAvail - tSpent - unpaid
  const leftAssign = income - tLimit - goalsMo

  // Net worth: own = positive balances + assets; owe = loans + accounts below zero.
  const holdings = data.assets ?? []
  const holdSum = sum(holdings, (x) => x.value)
  const posSum = (types: string[]) => sum(accounts.filter((a) => types.includes(a.type) && a.balance > 0), (a) => a.balance)
  const assets = sum(accounts.filter((a) => a.balance > 0), (a) => a.balance) + holdSum
  const liab = sum(data.debts, (x) => x.balance) + sum(accounts.filter((a) => a.balance < 0), (a) => -a.balance)
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

  // Debt: loans plus cards in the red.
  const allDebts: DebtLine[] = (data.debts.map((d) => ({ ...d, loan: true })) as DebtLine[]).concat(
    accounts.filter((a) => a.type === 'card' && a.balance < 0).map((a) => ({
      id: a.id, name: a.name, balance: -a.balance, apr: a.apr || 36, min: Math.max(100, Math.round(-a.balance * 0.05)), card: data.accounts.find((x) => x.id === a.id),
    })))
  const strat = H.strat ?? 'avalanche', extra = H.extra ?? 0
  const debtPlan = simDebt(allDebts, extra, strat)

  // Bills and pay over the next n days (from real today).
  const events = (n: number): CashEvent[] => {
    const out: CashEvent[] = []
    for (let i = 0; i <= n; i++) {
      const d = addDays(today, i), m = ymOf(d), dd = d.getDate(), dm = dim(m)
      data.bills.forEach((b) => {
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
    const varAvg = sum(data.tx.filter((t) => t.type === 'exp' && !t.billId && t.date >= since), (t) => t.amt) / 60
    const ev = events(30)
    let b = cash
    const series: number[] = []
    for (let k = 0; k <= 30; k++) { ev.filter((e) => e.i === k).forEach((e) => (b += e.amt)); if (k > 0) b -= varAvg; series.push(b) }
    return { cash, series, events: ev, varAvg }
  }

  // Round-ups: each everyday purchase this month rounded up to the next 10.
  const roundUps = Math.max(0, Math.round(sum(inM(curYm).filter((t) => t.type === 'exp' && !t.billId), (t) => Math.ceil(t.amt / 10) * 10 - t.amt) - (H.roundSwept?.[curYm] || 0)))
  const roundUpPot = goals.find((g) => g.id === H.roundUpPot) ?? goals[0]

  return {
    data, H, A, B, cur, f, num, today, tDay, curYm, ym, isCur, days, day, daysLeft, pace,
    whoName, whoCol, rollover, cushion,
    accounts, goals, acctBy, aName, mainAcct, balance, savedIn,
    cats, catBy, catOf, catOr, inM, byCat, desc,
    mtx, exp, inc, spent, pExp, pSpent, income, goalsMo,
    rows, tAvail, tSpent, tLimit, billsM, unpaid, safe, leftAssign,
    assets, liab, holdings, holdSum, ownGroups, investments, invGain, allDebts, strat, extra, debtPlan,
    events, forecast, roundUps, roundUpPot,
  }
}
