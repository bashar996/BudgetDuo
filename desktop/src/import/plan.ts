// Statement rows → proposed entries: expense / income / transfer, category, bill or loan
// match, duplicates. Pure, so it can be tested without the app.
import { allCategories } from '../data/catalog'
import { installmentOf, isPlan } from '../data/loans'
import type { Account, Bill, Data, Tx, Who } from '../data/types'
import { addM, dim, pad } from '../lib/dates'
import { daysBetween } from '../lib/period'
import { round2 } from './amounts'
import { cleanName, similarity } from './clean'
import { historyIndex, suggestCategory } from './categorise'
import { likelyDuplicate, planInstallmentDupe } from './dedupe'
import type { StmtRow } from './detect'

export type Status = 'new' | 'needsCat' | 'imported' | 'dupe' | 'transfer' | 'cardPayment' | 'refund' | 'bill' | 'loan' | 'income' | 'salary'

export interface PlanRow {
  key: number
  row: StmtRow
  importId: string
  /** Ticked for import. */
  on: boolean
  status: Status
  /** Badge text: "Matches bill Rent", "Already in Twofold", … */
  note: string
  kind: 'exp' | 'inc' | 'xfer'
  name: string
  cat: string | null
  catHow: 'history' | 'rule' | 'user' | null
  who: Who
  bill?: { id: string; ym: string; name: string }
  debtId?: string
  /** Transfers: from → to. */
  from?: string
  to?: string
  dupeOf?: Tx
}

export interface ImportEntry { tx: Omit<Tx, 'id'> & { id?: string }; bill?: { id: string; ym: string } }

const SALARY = /\b(salary|payroll|sal|wages|wps)\b/i
const XFER = /\b(transfer|trf|tfr|ft|own account|own acc|xfer|fund transfer|funds transfer)\b/i
const CARD_PAY = /\b(payment|thank you|thankyou|pymt|pmt|paid)\b/i
const CARD_OUT = /\b(card payment|cc payment|credit card payment|card pymt|cc pymt|card settlement)\b/i
const REFUND = /\b(refund|reversal|reversed|cashback|cash back|chargeback|return)\b/i

/** Another account of yours that a description names (by name or last four digits). */
function ownAccount(desc: string, accounts: Account[], self: string): Account | undefined {
  const d = desc.toLowerCase()
  return accounts.find((a) => a.id !== self && (
    (a.last4 && new RegExp('(^|[^0-9])' + a.last4 + '($|[^0-9])').test(d)) ||
    (a.name.length >= 5 && d.includes(a.name.toLowerCase()))
  ))
}

/**
 * Which month's due date of a bill a statement line pays: the nearest unpaid, unmatched due date
 * within 3 days (this calendar month, the one before or after), else this calendar month's.
 * `ym` is that due date's calendar month, the bill's `paid` key.
 */
function nearestDue(b: Bill, date: string, used: Set<string>): { ym: string; gap: number } | null {
  let best: { ym: string; gap: number } | null = null
  for (const k of [0, -1, 1]) {
    const ym = addM(date.slice(0, 7), k)
    if (b.paid?.[ym] || used.has(b.id + ym)) continue
    const gap = Math.abs(daysBetween(ym + '-' + pad(Math.min(b.day, dim(ym))), date))
    if (k && gap > 3) continue
    if (!best || gap < best.gap) best = { ym, gap }
  }
  return best
}

/** `ids` come from importIds(acctId, rows) (async: SHA-256). */
export function planRows(rows: StmtRow[], data: Data, acctId: string, ids: string[]): PlanRow[] {
  const acct = data.accounts.find((a) => a.id === acctId)
  const isCard = acct?.type === 'card'
  const cats = allCategories(data.household)
  const has = (id: string) => cats.some((c) => c.id === id)
  const hist = historyIndex(data.tx, has)
  const known = new Set(data.tx.map((t) => t.importId).filter(Boolean) as string[])
  const used = new Set<string>(), usedBills = new Set<string>()
  const who: Who = acct?.who === 'A' || acct?.who === 'B' ? acct.who : 'J'
  // The card's installment plans: Twofold posts their installments itself, so a statement line for one is already in.
  const cardPlans = isCard ? data.debts.filter((l) => isPlan(l) && l.acct === acctId) : []
  const main = (data.accounts.find((a) => a.type === 'current' && a.id !== acctId) ?? data.accounts.find((a) => (a.type === 'current' || a.type === 'cash') && a.id !== acctId))?.id

  return rows.map((row, key): PlanRow => {
    const name = cleanName(row.desc)
    const base: PlanRow = { key, row, importId: ids[key], on: true, status: 'new', note: '', kind: row.amount < 0 ? 'exp' : 'inc', name, cat: null, catHow: null, who }
    const out = row.amount < 0, amt = Math.abs(row.amount)

    // What it would be, before the duplicate checks.
    const p: PlanRow = { ...base }
    if (out) {
      // A bill: same amount (±1%), and a similar name or a due date within 3 days. The paid key is
      // the calendar month of the due date nearest the statement date (whatever the budget month).
      let ym = ''
      const bill = data.bills.find((b) => {
        if (Math.abs(b.amt - amt) > Math.max(0.011, b.amt * 0.01)) return false
        const due = nearestDue(b, row.date, usedBills)
        if (!due || !(similarity(name, b.name) >= 0.5 || similarity(row.desc, b.name) >= 0.5 || due.gap <= 3)) return false
        ym = due.ym
        return true
      })
      const loan = !bill ? data.debts.find((l) => {
        if (isPlan(l)) return false
        const inst = installmentOf(l)
        const named = similarity(row.desc, l.name) >= 0.5 || (!!l.lender && similarity(row.desc, l.lender) >= 0.5)
        return named && inst > 0 && Math.abs(inst - amt) <= Math.max(1, inst * 0.02)
      }) : undefined
      const other = !isCard ? ownAccount(row.desc, data.accounts, acctId) : undefined
      if (bill) {
        usedBills.add(bill.id + ym)
        Object.assign(p, { status: 'bill', note: 'Matches bill ' + bill.name, bill: { id: bill.id, ym, name: bill.name }, name: bill.name, cat: bill.cat, catHow: 'rule', who: 'J' as Who, debtId: bill.debtId ?? undefined })
      } else if (loan) {
        Object.assign(p, { status: 'loan', note: 'Installment on ' + loan.name, debtId: loan.id, name: loan.name + ' · installment', cat: has('debt') ? 'debt' : cats[0]?.id ?? 'debt', catHow: 'rule' })
      } else if (other || (!isCard && CARD_OUT.test(row.desc) && data.accounts.some((a) => a.type === 'card'))) {
        const to = other ?? data.accounts.find((a) => a.type === 'card')!
        Object.assign(p, { status: 'transfer', on: false, kind: 'xfer', note: 'Looks like a transfer to ' + to.name, from: acctId, to: to.id, cat: 'transfer', name: 'Transfer to ' + to.name })
      } else {
        const s = suggestCategory(row.desc, name, hist, has)
        if (s) Object.assign(p, { cat: s.cat, catHow: s.how })
        else Object.assign(p, { status: 'needsCat', note: 'Needs a category' })
      }
    } else if (isCard) {
      if (CARD_PAY.test(row.desc) && !REFUND.test(row.desc)) {
        Object.assign(p, main
          ? { status: 'cardPayment', on: false, kind: 'xfer', note: 'Card payment — record it as a transfer from ' + data.accounts.find((a) => a.id === main)!.name + '?', from: main, to: acctId, cat: 'transfer', name: 'Card payment' }
          : { status: 'cardPayment', on: false, kind: 'inc', note: 'Card payment', cat: 'income', name: 'Card payment' })
      } else {
        const merchant = cleanName(row.desc.replace(REFUND, ' ')) || name
        Object.assign(p, { status: 'refund', note: 'Refund', kind: 'inc', cat: 'income', name: ('Refund · ' + merchant).slice(0, 48) })
      }
    } else if (SALARY.test(row.desc)) {
      Object.assign(p, { status: 'salary', note: 'Salary', cat: 'income', name: 'Salary', who: 'J' as Who })
    } else if (XFER.test(row.desc) || ownAccount(row.desc, data.accounts, acctId)) {
      Object.assign(p, { status: 'transfer', on: false, note: 'Looks like a transfer', cat: 'income' })
    } else {
      Object.assign(p, { status: 'income', note: 'Income', cat: 'income' })
    }

    // Duplicates.
    if (known.has(ids[key])) return { ...p, on: false, status: 'imported', note: 'Already imported' }
    const inst = isCard ? planInstallmentDupe(data.tx, cardPlans, acctId, row, used) : null
    if (inst) {
      used.add(inst.id)
      if (p.bill) usedBills.delete(p.bill.id + p.bill.ym)
      return { ...p, on: false, status: 'dupe', note: 'Already in Twofold · ' + inst.name, dupeOf: inst }
    }
    const dupe = likelyDuplicate(data.tx, acctId, { date: row.date, amount: row.amount, name, desc: row.desc, cat: p.cat ?? undefined }, used)
    if (dupe) {
      used.add(dupe.id)
      if (p.bill) usedBills.delete(p.bill.id + p.bill.ym)
      return { ...p, on: false, status: 'dupe', note: 'Already in Twofold · ' + dupe.name, dupeOf: dupe }
    }
    return p
  })
}

/** A ticked expense needs a category before it can be imported. */
export const ready = (p: PlanRow) => !(p.kind === 'exp' && !p.cat)

export function toEntry(p: PlanRow, acctId: string, now = new Date()): ImportEntry {
  const amt = round2(Math.abs(p.row.amount))
  const tx: ImportEntry['tx'] = {
    date: p.row.date, name: p.name.trim() || (p.kind === 'inc' ? 'Income' : 'Expense'), amt, who: p.who, type: p.kind,
    cat: p.kind === 'xfer' ? 'transfer' : p.kind === 'inc' ? 'income' : p.cat || 'other',
    acct: p.kind === 'xfer' ? p.from ?? acctId : acctId, note: p.row.desc,
    importId: p.importId, source: 'import', createdAt: now,
  }
  if (p.kind === 'xfer') tx.to = p.to
  if (p.kind === 'exp' && p.debtId) { tx.debtId = p.debtId; tx.debtPart = 'installment' }
  if (p.kind === 'exp' && p.bill) {
    tx.id = 'bill-' + p.bill.id + '-' + p.bill.ym
    tx.billId = p.bill.id
    return { tx, bill: { id: p.bill.id, ym: p.bill.ym } }
  }
  return { tx }
}
