// Every change the app can make, written once on top of a Backend.
import { createContext, useContext } from 'react'
import { DELETE, inc, type Backend, type Col, type Op } from './backend'
import type { Account, Asset, Bill, Data, Debt, Goal, Household, Planned, Trip, Tx, Who } from './types'
import { allCategories, catOr, LOCKED } from './catalog'
import { installmentOf, isSimple, loanState } from './loans'
import { loanPayments } from './ledger'
import { dim, isoOf, pad } from '../lib/dates'

type Draft<T extends { id: string }> = Omit<T, 'id'> & { id?: string }

/** The calendar month a bill payment's `paid` flag is keyed by: from its fixed ID
 *  ("bill-<bill>-YYYY-MM"), else the entry's own date. */
export const billPaidKey = (t: Tx) => {
  const pre = 'bill-' + t.billId + '-', m = t.id.startsWith(pre) ? t.id.slice(pre.length) : ''
  return /^\d{4}-\d{2}$/.test(m) ? m : t.date.slice(0, 7)
}

function strip<T extends object>(v: T): Record<string, unknown> {
  const o: Record<string, unknown> = {}
  for (const [k, x] of Object.entries(v)) if (x !== undefined) o[k] = x
  return o
}

export function makeActions(be: Backend, getData: () => Data | null) {
  const put = <T extends { id?: string; createdAt?: Date | null; [k: string]: unknown }>(col: Col, v: T, stamp = true): Op & { id: string } => {
    const id = v.id || be.newId(col)
    const value = strip({ ...v, id, ...(stamp && !v.createdAt ? { createdAt: new Date() } : {}) })
    return { kind: 'put', col, id, value }
  }
  const hh = (fields: Record<string, unknown>): Op => ({ kind: 'patch', col: 'household', fields })
  const commit = (...ops: Op[]) => be.commit(ops)
  /** The category id, or the first remaining one if the household deleted it. */
  const cat = (id: string) => { const D = getData(); return D ? catOr(allCategories(D.household), id) : id }
  /** Same pick as the ledger's mainAcct: the first current account, else the first account. */
  const mainAcct = (D: Data) => (D.accounts.find((a) => a.type === 'current') ?? D.accounts[0])?.id ?? ''
  /** The account a loan's payments come out of (falls back to `acct`, then the main account). */
  const loanAcct = (D: Data, debtId: string | null | undefined, acct?: string) => {
    const l = debtId ? D.debts.find((x) => x.id === debtId) : undefined
    return l?.acct && D.accounts.some((a) => a.id === l.acct) ? l.acct : acct || mainAcct(D)
  }
  /** The entry for paying a bill in a month. Its ID is fixed per bill and month. */
  const billTx = (b: Bill, ym: string, acct: string): Tx => {
    const D = getData()
    return {
      id: 'bill-' + b.id + '-' + ym, date: ym + '-' + pad(Math.min(b.day, dim(ym))), name: b.name, cat: b.cat, amt: b.amt, who: 'J', type: 'exp', billId: b.id,
      acct: b.debtId && D ? loanAcct(D, b.debtId, acct) : acct,
      ...(b.debtId ? { debtId: b.debtId, debtPart: 'installment' as const } : {}),
    }
  }

  return {
    // Entries
    saveTx(t: Draft<Tx>) { const op = put('tx', t); commit(op); return op.id },
    /** Deletes an entry; a bill payment also marks that bill unpaid again. */
    deleteTx(t: Tx) {
      const ops: Op[] = [{ kind: 'del', col: 'tx', id: t.id }]
      if (t.billId && getData()?.bills.some((b) => b.id === t.billId))
        ops.push({ kind: 'patch', col: 'bills', id: t.billId, fields: { ['paid.' + billPaidKey(t)]: false } })
      commit(...ops)
    },

    // Bills: the entry ID is fixed per bill and month, so paying twice can't double-count.
    // `ym` is the CALENDAR month of the due date (BillRow.pm), not the budget-month key.
    togglePaid(b: Bill, ym: string, acct: string) {
      const paid = !!b.paid?.[ym]
      const txId = 'bill-' + b.id + '-' + ym
      const ops: Op[] = [{ kind: 'patch', col: 'bills', id: b.id, fields: { ['paid.' + ym]: !paid } }]
      if (paid) ops.push({ kind: 'del', col: 'tx', id: txId })
      else ops.push(put('tx', { ...billTx(b, ym, acct) }))
      commit(...ops)
    },
    saveBill(b: Draft<Bill>) { commit(put('bills', { ...b, paid: b.paid ?? {} }, false)) },
    deleteBill(id: string) { commit({ kind: 'del', col: 'bills', id }) },

    // Budget
    setBudget(cat: string, limit: number) { commit(hh({ ['budgets.' + cat]: Math.max(0, limit) })) },
    /** Moves part of one category's limit into another. */
    moveBudget(from: string, to: string, amt: number) { commit(hh({ ['budgets.' + from]: inc(-amt), ['budgets.' + to]: inc(amt) })) },
    addCategory(name: string, g: 'needs' | 'wants', limit: number) {
      const H = getData()!.household
      const id = 'c' + Date.now().toString(36)
      commit(hh({ custom: [...(H.custom ?? []), { id, name, g }], ['budgets.' + id]: Math.max(0, limit) }))
      return id
    },
    /** Rename a category or move it between Needs and Wants. Built-ins go in catOv, your own in `custom`. */
    updateCategory(id: string, v: { name: string; g: 'needs' | 'wants' }) {
      if (LOCKED.includes(id)) return
      const H = getData()!.household
      if ((H.custom ?? []).some((c) => c.id === id)) commit(hh({ custom: (H.custom ?? []).map((c) => (c.id === id ? { ...c, name: v.name, g: v.g } : c)) }))
      else commit(hh({ ['catOv.' + id]: { name: v.name, g: v.g } }))
    },
    /**
     * Removes a category and its monthly limit. With a target, every entry and bill that used
     * it moves there; with null they keep the old id and show as "Other" (counted nowhere).
     * Firestore takes at most 500 writes per batch, so the moves go in batches of 450.
     */
    deleteCategory(id: string, target: string | null) {
      if (LOCKED.includes(id)) return
      const D = getData()!, H = D.household
      const ops: Op[] = []
      if (target && target !== id) {
        D.tx.forEach((t) => { if (t.cat === id) ops.push({ kind: 'patch', col: 'tx', id: t.id, fields: { cat: target } }) })
        D.bills.forEach((b) => { if (b.cat === id) ops.push({ kind: 'patch', col: 'bills', id: b.id, fields: { cat: target } }) })
      }
      const isCustom = (H.custom ?? []).some((c) => c.id === id)
      // The category itself goes last, so a failed move never leaves entries pointing at nothing new.
      ops.push(hh(isCustom
        ? { custom: (H.custom ?? []).filter((c) => c.id !== id), ['budgets.' + id]: DELETE }
        : { catDel: [...(H.catDel ?? []).filter((x) => x !== id), id], ['catOv.' + id]: DELETE, ['budgets.' + id]: DELETE }))
      for (let i = 0; i < ops.length; i += 450) commit(...ops.slice(i, i + 450))
    },

    // Pay
    setIncome(who: Who, amt: number, day: number) {
      const H = getData()!.household
      const list = H.incomes.some((x) => x.who === who) ? H.incomes : [...H.incomes, { who, amt: 0, day: 1 }]
      commit(hh({ incomes: list.map((x) => (x.who === who ? { who, amt: Math.max(0, amt), day } : x)) }))
    },

    // Us two
    toggleCheck(key: string) { const on = !!getData()?.household.checks?.[key]; commit(hh({ ['checks.' + key]: !on })) },
    /** Records what was moved between you, so later shared spending still shows. */
    setSettled(ym: string, amount: number) { commit(hh({ ['settled.' + ym]: inc(amount) })) },

    /** Shared settings: names, currency, budget style, rollover, cushion, … */
    updateHousehold(fields: Partial<Household>) { commit(hh(fields as Record<string, unknown>)) },

    // Accounts
    saveAccount(a: Draft<Account>) { const op = put('accounts', a); commit(op); return op.id },
    deleteAccount(id: string) { commit({ kind: 'del', col: 'accounts', id }) },

    // Pots
    saveGoal(g: Draft<Goal>) { const op = put('goals', g); commit(op); return op.id },
    deleteGoal(id: string) { commit({ kind: 'del', col: 'goals', id }) },
    setGoalAuto(id: string, auto: boolean) { commit({ kind: 'patch', col: 'goals', id, fields: { auto } }) },
    setRoundUpPot(id: string) { commit(hh({ roundUpPot: id })) },
    moveRoundUps(amount: number, pot: Goal, from: string, ym: string) {
      if (amount <= 0) return
      commit(
        put('tx', { date: isoOf(new Date()), name: 'Round-ups · ' + pot.name, cat: 'transfer', amt: amount, who: 'J' as Who, type: 'xfer' as const, acct: from, to: pot.acct, pot: pot.id, potDir: 'in' as const }),
        hh({ ['roundSwept.' + ym]: inc(amount) }),
      )
    },

    // Debt
    // Assets (home, car, gold, …): valued by hand, never moved by entries.
    saveAsset(a: Draft<Asset>) { const op = put('assets', a); commit(op); return op.id },
    deleteAsset(id: string) { commit({ kind: 'del', col: 'assets', id }) },

    setStrategy(s: 'avalanche' | 'snowball') { commit(hh({ strat: s })) },
    setExtra(v: number) { commit(hh({ extra: Math.max(0, v) })) },

    // Plan ahead
    savePlanned(p: Draft<Planned>) { commit(put('planned', p)) },
    deletePlanned(id: string) { commit({ kind: 'del', col: 'planned', id }) },
    vote(p: Planned, who: 'A' | 'B') { commit({ kind: 'patch', col: 'planned', id: p.id, fields: { [who]: !p[who] } }) },
    /** Logs the purchase as a Shopping expense and takes it off the plan. */
    buyPlanned(p: Planned, acct: string) {
      commit(
        put('tx', { date: isoOf(new Date()), name: p.name, cat: cat('shopping'), amt: p.cost, who: 'J' as Who, type: 'exp' as const, acct }),
        { kind: 'del', col: 'planned', id: p.id },
      )
    },
    saveTrip(t: Draft<Trip>) { commit(put('events', t)) },
    deleteTrip(id: string) { commit({ kind: 'del', col: 'events', id }) },
    /** Logs spending on a trip as a Travel expense and adds it to the trip. */
    spendOnTrip(t: Trip, amt: number, acct: string) {
      commit(
        put('tx', { date: isoOf(new Date()), name: t.name, cat: cat('travel'), amt, who: 'J' as Who, type: 'exp' as const, acct }),
        { kind: 'patch', col: 'events', id: t.id, fields: { spent: inc(amt) } },
      )
    },

    // MARK: Round 6: loans, card payments, undo

    /**
     * Saves a loan. Also writes the legacy fields the debt plan and older builds read
     * (apr = rate, min = installment, balance = amount borrowed for scheduled loans), and
     * creates, updates or removes its bill ("Show installments in Bills").
     */
    saveLoan(l: Draft<Debt>, inBills: boolean) {
      const D = getData()!
      const id = l.id || be.newId('debts')
      // Whole numbers stay integers (the iPhone reads them as Int).
      const int = (v: number | null | undefined) => (v == null ? v : Math.round(v))
      const doc = { ...l, id, termMonths: int(l.termMonths), paidBefore: int(l.paidBefore) } as Debt
      const simple = isSimple(doc), inst = installmentOf(doc)
      const old = l.billId ? D.bills.find((b) => b.id === l.billId) : undefined
      const ops: Op[] = []
      let billId: string | null = null
      if (inBills && !simple) {
        billId = old?.id ?? be.newId('bills')
        ops.push(put('bills', {
          id: billId, name: l.name, amt: Math.round(inst * 100) / 100, day: Number(l.firstDue!.slice(8, 10)) || 1,
          cat: cat('debt'), sub: false, paid: old?.paid ?? {}, debtId: id,
        }, false))
      } else if (old) ops.push({ kind: 'del', col: 'bills', id: old.id })
      ops.unshift(put('debts', { ...doc, billId, apr: l.rate ?? l.apr ?? 0, min: inst, balance: simple ? l.balance : l.principal! }))
      commit(...ops)
      return id
    },
    /** Deletes a loan and its bill. Its payments stay in Activity as ordinary expenses. */
    deleteLoan(l: Debt) {
      const D = getData()
      const ops: Op[] = [{ kind: 'del', col: 'debts', id: l.id }]
      D?.bills.forEach((b) => { if (b.id === l.billId || b.debtId === l.id) ops.push({ kind: 'del', col: 'bills', id: b.id }) })
      commit(...ops)
    },
    /**
     * Pays a loan: an expense from its account (or the main one), dated today. An installment on a
     * loan with a bill pays that bill for the month it's due instead, so Bills stays in step.
     * Returns the entry, so it can be undone.
     */
    payLoan(l: Debt, part: 'installment' | 'extra', amt: number): Tx | null {
      const D = getData()
      if (!D || !(amt > 0)) return null
      const today = isoOf(new Date())
      const bill = part === 'installment' ? D.bills.find((b) => b.debtId === l.id && (!l.billId || b.id === l.billId)) : undefined
      if (bill) {
        const ym = (loanState(l, loanPayments(D.tx, l.id), today).nextDue ?? today).slice(0, 7)
        if (!bill.paid?.[ym]) {
          const t = billTx(bill, ym, mainAcct(D))
          commit({ kind: 'patch', col: 'bills', id: bill.id, fields: { ['paid.' + ym]: true } }, put('tx', { ...t }))
          return t
        }
      }
      const t: Tx = {
        id: be.newId('tx'), createdAt: new Date(), date: today, name: l.name + (part === 'extra' ? ' · extra payment' : ' · installment'),
        cat: cat('debt'), amt: Math.round(amt * 100) / 100, who: 'J', type: 'exp', acct: loanAcct(D, l.id), debtId: l.id, debtPart: part,
      }
      commit(put('tx', { ...t }))
      return t
    },
    /** Puts a deleted entry back with the same ID and fields (and marks its bill paid again). */
    restoreTx(t: Tx) {
      const ops: Op[] = [put('tx', { ...t })]
      if (t.billId && getData()?.bills.some((b) => b.id === t.billId))
        ops.push({ kind: 'patch', col: 'bills', id: t.billId, fields: { ['paid.' + billPaidKey(t)]: true } })
      commit(...ops)
    },

    // MARK: Statement import

    /**
     * Writes imported entries in batches of at most 450 writes (Firestore allows 500).
     * A bill match uses the bill's fixed entry ID for that month and marks the bill paid,
     * so it can't be counted twice. Returns what to pass to undoImport().
     */
    importEntries(entries: { tx: Draft<Tx>; bill?: { id: string; ym: string } }[]): ImportResult {
      const D = getData()
      const res: ImportResult = { ids: [], bills: [] }
      let ops: Op[] = []
      const flush = () => { if (ops.length) commit(...ops); ops = [] }
      for (const e of entries) {
        const bill = e.bill && D?.bills.find((b) => b.id === e.bill!.id)
        const need = bill ? 2 : 1
        if (ops.length + need > 450) flush()
        const op = put('tx', { ...e.tx, ...(bill ? { id: 'bill-' + bill.id + '-' + e.bill!.ym, billId: bill.id } : {}) })
        ops.push(op)
        res.ids.push(op.id)
        if (bill) {
          ops.push({ kind: 'patch', col: 'bills', id: bill.id, fields: { ['paid.' + e.bill!.ym]: true } })
          res.bills.push({ id: bill.id, ym: e.bill!.ym })
        }
      }
      flush()
      return res
    },
    /** Deletes exactly the entries an import wrote and marks the bills it paid unpaid again. */
    undoImport(r: ImportResult) {
      const D = getData()
      const ops: Op[] = [
        ...r.ids.map((id): Op => ({ kind: 'del', col: 'tx', id })),
        ...r.bills.filter((b) => D?.bills.some((x) => x.id === b.id)).map((b): Op => ({ kind: 'patch', col: 'bills', id: b.id, fields: { ['paid.' + b.ym]: false } })),
      ]
      for (let i = 0; i < ops.length; i += 450) commit(...ops.slice(i, i + 450))
    },
  }
}

export interface ImportResult { ids: string[]; bills: { id: string; ym: string }[] }

export type Actions = ReturnType<typeof makeActions>

export interface Ctx {
  data: Data
  act: Actions
  uid: string
  householdId: string
  me: Who
  syncing: boolean
  demo: boolean
  signOut(): void
  leave(): void
}

export const StoreCtx = createContext<Ctx | null>(null)
export const useStore = () => useContext(StoreCtx)!
