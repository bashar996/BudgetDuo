// Every change the app can make, written once on top of a Backend.
import { createContext, useContext } from 'react'
import { DELETE, inc, type Backend, type Col, type Op } from './backend'
import type { Account, Asset, Bill, Data, Debt, Goal, Household, Planned, Trip, Tx, Who } from './types'
import { allCategories, catOr, LOCKED } from './catalog'
import { dim, isoOf, pad } from '../lib/dates'

type Draft<T extends { id: string }> = Omit<T, 'id'> & { id?: string }

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

  return {
    // Entries
    saveTx(t: Draft<Tx>) { const op = put('tx', t); commit(op); return op.id },
    /** Deletes an entry; a bill payment also marks that bill unpaid again. */
    deleteTx(t: Tx) {
      const ops: Op[] = [{ kind: 'del', col: 'tx', id: t.id }]
      if (t.billId && getData()?.bills.some((b) => b.id === t.billId))
        ops.push({ kind: 'patch', col: 'bills', id: t.billId, fields: { ['paid.' + t.date.slice(0, 7)]: false } })
      commit(...ops)
    },

    // Bills: the entry ID is fixed per bill and month, so paying twice can't double-count.
    togglePaid(b: Bill, ym: string, acct: string) {
      const paid = !!b.paid?.[ym]
      const txId = 'bill-' + b.id + '-' + ym
      const ops: Op[] = [{ kind: 'patch', col: 'bills', id: b.id, fields: { ['paid.' + ym]: !paid } }]
      if (paid) ops.push({ kind: 'del', col: 'tx', id: txId })
      else ops.push(put('tx', { id: txId, date: ym + '-' + pad(Math.min(b.day, dim(ym))), name: b.name, cat: b.cat, amt: b.amt, who: 'J' as Who, type: 'exp' as const, billId: b.id, acct }))
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

    saveDebt(d: Draft<Debt>) { commit(put('debts', d)) },
    deleteDebt(id: string) { commit({ kind: 'del', col: 'debts', id }) },
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
  }
}

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
