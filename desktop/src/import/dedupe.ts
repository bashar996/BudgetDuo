// Import IDs and duplicate checks.
import type { Tx } from '../data/types'
import { similarity } from './clean'

/** Raw description as it goes into the import ID: upper case, single spaces, trimmed. */
export const idDesc = (s: string) => String(s).toUpperCase().replace(/\s+/g, ' ').trim()

/**
 * Stable ID for a statement line, the same on the iPhone:
 * "imp_" + hex of the first 8 bytes of SHA-256("acct|YYYY-MM-DD|-38.00|DESCRIPTION|n"),
 * where n counts identical lines earlier in the same file (0 for the first).
 */
export async function importIdOf(acct: string, date: string, amount: number, raw: string, occurrence: number): Promise<string> {
  const text = [acct, date, amount.toFixed(2), idDesc(raw), occurrence].join('|')
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))
  return 'imp_' + Array.from(d.slice(0, 8), (b) => b.toString(16).padStart(2, '0')).join('')
}

/** Import IDs for a file's rows, numbering identical lines. */
export function importIds(acct: string, rows: { date: string; amount: number; desc: string }[]): Promise<string[]> {
  const seen = new Map<string, number>()
  return Promise.all(rows.map((r) => {
    const k = [r.date, r.amount.toFixed(2), idDesc(r.desc)].join('|')
    const n = seen.get(k) ?? 0
    seen.set(k, n + 1)
    return importIdOf(acct, r.date, r.amount, r.desc, n)
  }))
}

const dayMs = 86400000
const dayNum = (iso: string) => Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) / dayMs

/**
 * Finds the existing entry a row probably is: same account and amount (±0.01) in the same
 * direction, within 3 days, and also: the same day, a similar name, a bill or loan payment, or the same
 * category as the row's suggestion. An entry on another account counts only with a similar name. Each entry matches at most one row (`used`).
 */
export function likelyDuplicate(
  tx: Tx[], acct: string, row: { date: string; amount: number; name: string; desc: string; cat?: string }, used: Set<string>,
): Tx | null {
  const amt = Math.abs(row.amount), inflow = row.amount > 0, d = dayNum(row.date)
  let best: Tx | null = null, bestScore = -1
  for (const t of tx) {
    if (used.has(t.id) || Math.abs(t.amt - amt) > 0.011) continue
    const dd = Math.abs(dayNum(t.date) - d)
    if (!(dd <= 3)) continue
    const sameAcct = inflow
      ? (t.type === 'inc' && t.acct === acct) || (t.type === 'xfer' && t.to === acct)
      : (t.type === 'exp' && t.acct === acct) || (t.type === 'xfer' && t.acct === acct)
    const dirOk = inflow ? t.type !== 'exp' : t.type !== 'inc'
    if (!dirOk) continue
    const sim = Math.max(similarity(row.name, t.name), similarity(row.desc, t.name))
    const alike = dd === 0 || sim >= 0.5 || !!t.billId || !!t.debtId || (!!row.cat && row.cat === t.cat)
    if (sameAcct ? !alike : !(sim >= 0.5)) continue
    const score = (sameAcct ? 2 : 0) + sim - dd * 0.1
    if (score > bestScore) { best = t; bestScore = score }
  }
  return best
}

/** How banks label a card installment on the statement ("EPP 4/12", "IPP", "INSTALMENT", "EASY PAYMENT PLAN", "FLEXI"). */
const PLAN_WORDS = /\bEPP\b|\bIPP\b|\bINSTAL|\bEASY\s*PAYMENT|\bFLEXI/i

/**
 * A card statement line that is an installment (or fee) Twofold already posted for one of the
 * card's installment plans: an expense on this card from that plan, amount within 1%, date within
 * 5 days, and the description names the plan or reads like an installment. Each entry matches once.
 * @param plans the card's installment plans ({ id, name })
 */
export function planInstallmentDupe(
  tx: Tx[], plans: { id: string; name: string }[], acct: string, row: { date: string; amount: number; desc: string }, used: Set<string>,
): Tx | null {
  if (row.amount >= 0 || !plans.length) return null
  const amt = -row.amount, d = dayNum(row.date), desc = row.desc.toLowerCase()
  let best: Tx | null = null, bestGap = Infinity
  for (const t of tx) {
    const plan = t.debtId ? plans.find((p) => p.id === t.debtId) : undefined
    if (!plan || used.has(t.id) || t.type !== 'exp' || t.acct !== acct || t.debtPart === 'extra') continue
    if (Math.abs(t.amt - amt) > Math.max(0.011, t.amt * 0.01)) continue
    const gap = Math.abs(dayNum(t.date) - d)
    if (gap > 5) continue
    if (!(PLAN_WORDS.test(row.desc) || (plan.name.trim().length >= 2 && desc.includes(plan.name.trim().toLowerCase())))) continue
    if (gap < bestGap) { best = t; bestGap = gap }
  }
  return best
}
