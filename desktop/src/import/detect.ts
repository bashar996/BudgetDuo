// Which column is which, and statement rows with signed amounts (+ money in, − money out).
import { parseAmount, round2, signed, type Amount } from './amounts'
import { detectOrder, parseDate, isDateLike, type DateOrder } from './dates'

export interface Mapping {
  /** Row index of the header, −1 when the file has none. */
  header: number
  date: number
  /** Value date, used when the transaction date is empty. */
  vdate: number
  desc: number
  /** Single signed amount column (−1 when Debit + Credit are used). */
  amount: number
  debit: number
  credit: number
  balance: number
  /** A "Cr/Dr" column next to the amount. */
  dir: number
  order: DateOrder
  /** Single amount column: positive amounts are money out (card statements). */
  posOut: boolean
}

/** A parsed line before the sign convention is applied. */
export interface RawRow {
  /** Index in the source (table row or PDF line), for ordering and the preview. */
  i: number
  date: string
  desc: string
  money: Amount
  /** Direction already known (+1 in, −1 out) from Debit/Credit columns or the running balance. */
  fixed: number | null
  balance: number | null
  raw: string
}

/** A statement row: + money in, − money out. */
export interface StmtRow { i: number; date: string; desc: string; amount: number; balance: number | null; raw: string }

export const NOISE_ROW = /\b(opening|closing|previous|available|ledger|statement|brought|carried|beginning|ending)\s+(balance|forward|bal)\b|\bbalance\s+(b\/f|c\/f|brought|carried|forward)\b|^\s*(sub\s*)?totals?\b|^\s*b\/f\b|^\s*c\/f\b/i

// MARK: Header detection

type Role = 'date' | 'vdate' | 'desc' | 'amount' | 'debit' | 'credit' | 'balance' | 'dir'
const norm = (s: string) => String(s ?? '').toLowerCase().replace(/[_\s]+/g, ' ').replace(/[.:]+$/, '').trim()

export function roleOf(cell: string): Role | null {
  const c = norm(cell)
  if (!c || c.length > 40) return null
  if (/balance/.test(c)) return 'balance'
  if (/^(cr ?\/ ?dr|dr ?\/ ?cr|debit ?\/ ?credit|credit ?\/ ?debit|d ?\/ ?c|c ?\/ ?d|dc|cd|sign)$/.test(c)) return 'dir'
  if (/value date|^val(ue)? dt$/.test(c)) return 'vdate'
  if (/^(transaction|trans|txn|tran|posting|post|posted|booking|book|entry|effective)?\s?(date|dt)( posted)?$/.test(c) || /^date( of transaction| \(.*\))?$/.test(c)) return 'date'
  if (/^(debit|debits|withdrawal|withdrawals|dr|money out|paid out|out|debit amount|withdrawal amount|amount debited|debit \(.*\)|withdrawals? \(.*\))$/.test(c)) return 'debit'
  if (/^(credit|credits|deposit|deposits|cr|money in|paid in|in|credit amount|deposit amount|amount credited|credit \(.*\)|deposits? \(.*\))$/.test(c)) return 'credit'
  if (/^(amount|transaction amount|txn amount|amount \(.*\)|amount [a-z]{3}|billing amount|billed amount|local amount|amount in [a-z]{3}|net amount|value)$/.test(c)) return 'amount'
  if (/^(description|details|narration|narrative|particulars|merchant|merchant name|transaction details|transaction description|remarks|memo|payee|transaction|description \/ narration|beneficiary|details of transaction|reference|transaction narration)$/.test(c)) return 'desc'
  if (/description|narration|particulars|details/.test(c)) return 'desc'
  return null
}

function headerScore(row: string[]) {
  const roles = row.map(roleOf)
  const has = (r: Role) => roles.includes(r)
  const money = has('amount') || has('debit') || has('credit')
  return (has('date') || has('vdate') ? 2 : 0) + (money ? 2 : 0) + (has('desc') ? 1 : 0) + (has('balance') ? 0.5 : 0)
}

const EMPTY: Omit<Mapping, 'order' | 'posOut'> = { header: -1, date: -1, vdate: -1, desc: -1, amount: -1, debit: -1, credit: -1, balance: -1, dir: -1 }

/** Columns from a header row (first within the first 30 that names a date and an amount), else by content. */
export function detectMapping(table: string[][], isCard = false): Mapping {
  let m: Omit<Mapping, 'order' | 'posOut'> | null = null
  for (let r = 0; r < Math.min(30, table.length); r++) {
    if (headerScore(table[r]) >= 4) { m = fromHeader(table, r); break }
  }
  if (!m || (m.date < 0 && m.vdate < 0)) m = byContent(table)
  const dateCol = m.date >= 0 ? m.date : m.vdate
  const order = detectOrder(table.slice(m.header + 1).map((r) => r[dateCol] ?? ''))
  const full: Mapping = { ...m, order, posOut: false }
  full.posOut = inferSign(prepare(rawRows(table, full), isCard), isCard).posOut
  return full
}

function fromHeader(table: string[][], r: number): Omit<Mapping, 'order' | 'posOut'> {
  const m = { ...EMPTY, header: r }
  const amounts: number[] = []
  table[r].forEach((cell, i) => {
    const role = roleOf(cell)
    if (!role) return
    if (role === 'amount') { amounts.push(i); return }
    if ((m as any)[role] < 0) (m as any)[role] = i
  })
  // Several amount columns (card statements: original currency + AED): prefer the local one.
  if (amounts.length) m.amount = amounts.find((i) => /aed|billing|billed|local|د\.إ/i.test(table[r][i])) ?? amounts[amounts.length - 1]
  if (m.amount >= 0 && m.debit >= 0 && m.credit >= 0) m.amount = -1
  if (m.amount < 0 && m.debit >= 0 && m.credit < 0) { m.amount = m.debit; m.debit = -1 }
  if (m.amount < 0 && m.credit >= 0 && m.debit < 0) { m.amount = m.credit; m.credit = -1 }
  if (m.date < 0 && m.vdate >= 0) { m.date = m.vdate; m.vdate = -1 }
  // A "Cr/Dr" column only counts if its values look like it.
  if (m.dir >= 0) {
    const vals = table.slice(r + 1, r + 40).map((x) => norm(x[m.dir] ?? '')).filter(Boolean)
    if (!vals.length || vals.filter((v) => /^(cr|dr|c|d|credit|debit)$/.test(v)).length < vals.length * 0.8) m.dir = -1
  }
  if (m.desc < 0) m.desc = widestText(table, r + 1, [m.date, m.vdate, m.amount, m.debit, m.credit, m.balance, m.dir])
  return m
}

function widestText(table: string[][], from: number, skip: number[]): number {
  const rows = table.slice(from, from + 60)
  const width = Math.max(0, ...rows.map((r) => r.length))
  let best = -1, bestLen = 0
  for (let c = 0; c < width; c++) {
    if (skip.includes(c)) continue
    const vals = rows.map((r) => r[c] ?? '').filter(Boolean)
    if (!vals.length) continue
    const text = vals.filter((v) => !parseAmount(v) && !isDateLike(v))
    const len = text.reduce((s, v) => s + v.length, 0) / vals.length
    if (text.length >= vals.length * 0.6 && len > bestLen) { bestLen = len; best = c }
  }
  return best
}

/** No header row: a date-like column, the widest text column, and the numeric columns. */
function byContent(table: string[][]): Omit<Mapping, 'order' | 'posOut'> {
  const m = { ...EMPTY }
  const rows = table.slice(0, 200)
  const width = Math.max(0, ...rows.map((r) => r.length))
  const stats = Array.from({ length: width }, (_, c) => {
    const vals = rows.map((r) => r[c] ?? '')
    const filled = vals.filter(Boolean)
    return {
      dateF: filled.length ? filled.filter((v) => isDateLike(v)).length / rows.length : 0,
      numF: filled.length ? filled.filter((v) => parseAmount(v) && !isDateLike(v)).length / Math.max(1, filled.length) : 0,
      filled: filled.length,
    }
  })
  let dateBest = 0
  stats.forEach((s, c) => { if (s.dateF > dateBest + 0.05) { dateBest = s.dateF; m.date = c } })
  if (m.date < 0) return m
  // The data starts at the first row with a date.
  const first = rows.findIndex((r) => isDateLike(r[m.date] ?? ''))
  m.header = first - 1
  const nums = stats.map((s, c) => (c !== m.date && s.numF > 0.8 && s.filled >= 1 && !(stats[c].dateF > 0.5) ? c : -1)).filter((c) => c >= 0)
  m.desc = widestText(table, first, [m.date, ...nums])
  const data = table.slice(first)
  if (nums.length === 1) m.amount = nums[0]
  else if (nums.length === 2) {
    // Debit + Credit when each row fills only one of them, else Amount + Balance.
    const both = data.filter((r) => (r[nums[0]] ?? '') !== '' && (r[nums[1]] ?? '') !== '').length
    if (both < data.length * 0.2) { m.debit = nums[0]; m.credit = nums[1] } else { m.amount = nums[0]; m.balance = nums[1] }
  } else if (nums.length >= 3) {
    const [a, b, c] = nums.slice(-3)
    m.debit = a; m.credit = b; m.balance = c
  }
  return m
}

/** Cell text for a shape key (header names, or the column count). */
export function shapeOf(table: string[][], m: Pick<Mapping, 'header'>): string {
  if (m.header >= 0) return 'h:' + table[m.header].map(norm).join('|')
  return 'c:' + Math.max(0, ...table.slice(0, 20).map((r) => r.length))
}

// MARK: Rows

export function rawRows(table: string[][], m: Mapping): RawRow[] {
  const out: RawRow[] = []
  const at = (r: string[], c: number) => (c >= 0 ? (r[c] ?? '').trim() : '')
  for (let i = m.header + 1; i < table.length; i++) {
    const r = table[i]
    const date = parseDate(at(r, m.date), m.order) ?? parseDate(at(r, m.vdate), m.order)
    if (!date) continue
    let desc = at(r, m.desc)
    if (!desc) desc = r.filter((v, c) => v && ![m.date, m.vdate, m.amount, m.debit, m.credit, m.balance, m.dir].includes(c) && !parseAmount(v)).join(' ')
    if (NOISE_ROW.test(desc)) continue
    let money: Amount | null = null, fixed: number | null = null
    if (m.amount >= 0) {
      money = parseAmount(at(r, m.amount))
      if (money && m.dir >= 0) {
        const d = norm(at(r, m.dir))
        if (/^(cr|c|credit)$/.test(d)) money = { ...money, mark: 'cr' }
        else if (/^(dr|d|debit)$/.test(d)) money = { ...money, mark: 'dr' }
      }
    } else {
      const d = parseAmount(at(r, m.debit)), c = parseAmount(at(r, m.credit))
      const dv = d ? Math.abs(d.value) : 0, cv = c ? Math.abs(c.value) : 0
      if (dv || cv) { money = { value: Math.abs(cv - dv), mark: null }; fixed = cv >= dv ? 1 : -1 }
    }
    if (!money || !money.value) continue
    const b = parseAmount(at(r, m.balance))
    out.push({ i, date, desc, money, fixed, balance: b ? signed(b) : null, raw: r.filter(Boolean).join(' · ') })
  }
  return out
}

const near = (a: number, b: number) => Math.abs(a - b) < 0.015

/**
 * Sets the direction of unsigned amounts from the running balance (PDF lines, "Amount" columns
 * with no signs). Works whichever way round the statement is sorted. For a card whose balance
 * is shown as the amount owed, a rising balance is money out.
 */
export function balanceSigns(rows: RawRow[], isCard: boolean) {
  const withBal = rows.filter((r) => r.balance != null)
  if (withBal.length < 2) return
  const owedPositive = isCard && withBal.filter((r) => r.balance! > 0).length > withBal.length / 2
  const flip = owedPositive ? -1 : 1
  const tryOrder = (list: RawRow[]) => {
    const res = new Map<RawRow, number>()
    for (let k = 1; k < list.length; k++) {
      const p = list[k - 1], r = list[k]
      if (p.balance == null || r.balance == null) continue
      const d = r.balance - p.balance, v = Math.abs(r.money.value)
      if (near(d, v)) res.set(r, flip)
      else if (near(d, -v)) res.set(r, -flip)
    }
    return res
  }
  const fwd = tryOrder(rows), rev = tryOrder([...rows].reverse())
  const best = rev.size > fwd.size ? rev : fwd
  best.forEach((s, r) => { if (r.fixed == null) r.fixed = s })
}

/**
 * Sign convention for amounts whose direction isn't known yet. `show` is false when
 * every row's direction is already decided (Debit/Credit columns, Cr/Dr, balance).
 */
export function inferSign(rows: RawRow[], isCard: boolean): { posOut: boolean; sure: boolean; show: boolean } {
  const open = rows.filter((r) => r.fixed == null && !r.money.mark)
  if (!open.length) return { posOut: isCard, sure: true, show: false }
  const neg = open.filter((r) => r.money.value < 0).length, pos = open.length - neg
  // Running balance as evidence when the amounts carry signs.
  let a = 0, b = 0
  const withBal = rows.filter((r) => r.balance != null)
  if (withBal.length >= 3) {
    const owedPositive = isCard && withBal.filter((r) => r.balance! > 0).length > withBal.length / 2
    for (const list of [rows, [...rows].reverse()]) {
      let a1 = 0, b1 = 0
      for (let k = 1; k < list.length; k++) {
        const p = list[k - 1], r = list[k]
        if (p.balance == null || r.balance == null || r.fixed != null || r.money.mark) continue
        const d = r.balance - p.balance
        if (near(d, r.money.value)) a1++
        else if (near(d, -r.money.value)) b1++
      }
      if (a1 + b1 > a + b) { a = a1; b = b1 }
    }
    if (owedPositive) [a, b] = [b, a]
    if (a + b >= 2) return { posOut: b > a, sure: true, show: true }
  }
  if (!neg) return { posOut: true, sure: false, show: true }
  // Card statements: charges positive and payments negative is the usual way round.
  if (isCard) return { posOut: pos >= neg, sure: pos > 0 && neg > 0, show: true }
  return { posOut: false, sure: true, show: true }
}

/** Unsigned amounts (no minus, brackets or Cr/Dr anywhere) take their direction from the balance. */
export function prepare(rows: RawRow[], isCard: boolean): RawRow[] {
  if (!rows.some((r) => r.fixed == null && (r.money.value < 0 || r.money.mark))) balanceSigns(rows, isCard)
  return rows
}

/** Applies the sign convention: + money in, − money out. */
export function finalize(rows: RawRow[], posOut: boolean): StmtRow[] {
  return rows.map((r) => ({
    i: r.i, date: r.date, desc: r.desc.replace(/\s+/g, ' ').trim(), balance: r.balance, raw: r.raw,
    amount: round2(r.fixed != null ? r.fixed * Math.abs(r.money.value) : signed(r.money, posOut)),
  }))
}
