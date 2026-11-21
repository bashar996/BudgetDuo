// Every change the app can make, written once on top of a Backend.
import { createContext, useContext } from 'react'
import { DELETE, inc, type Backend, type Col, type Op } from './backend'
import type { Account, Bill, Data, Debt, Goal, Household, Planned, Trip, Tx, Who } from './types'
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
    renameCategory(id: string, name: string) {
      const H = getData()!.household
      commit(hh({ custom: (H.custom ?? []).map((c) => (c.id === id ? { ...c, name } : c)) }))
    },
    /** Entries keep their amounts and show as "Other". */
    deleteCategory(id: string) {
      const H = getData()!.household
      commit(hh({ custom: (H.custom ?? []).filter((c) => c.id !== id), ['budgets.' + id]: DELETE }))
    },

    // Pay
    setIncome(who: Who, amt: number, day: number) {
      const H = getData()!.household
      const list = H.incomes.some((x) => x.who === who) ? H.incomes : [...H.incomes, { who, amt: 0, day: 1 }]
      commit(hh({ incomes: list.map((x) => (x.who === who ? { who, amt: Math.max(0, amt), day } : x)) }))
    },

    // Us two
    toggleCheck(key: string) { const on = !!getData()?.household.checks?.[key]; commit(hh({ ['checks.' + key]: !on })) },
    setSettled(ym: string, v: boolean) { commit(hh({ ['settled.' + ym]: v })) },

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
        put('tx', { date: isoOf(new Date()), name: p.name, cat: 'shopping', amt: p.cost, who: 'J' as Who, type: 'exp' as const, acct }),
        { kind: 'del', col: 'planned', id: p.id },
      )
    },
    saveTrip(t: Draft<Trip>) { commit(put('events', t)) },
    deleteTrip(id: string) { commit({ kind: 'del', col: 'events', id }) },
    /** Logs spending on a trip as a Travel expense and adds it to the trip. */
    spendOnTrip(t: Trip, amt: number, acct: string) {
      commit(
        put('tx', { date: isoOf(new Date()), name: t.name, cat: 'travel', amt, who: 'J' as Who, type: 'exp' as const, acct }),
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
