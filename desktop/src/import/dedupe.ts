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
 * direction, within 3 days, and also: the same day, a similar name, a bill payment, or the same
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
    const alike = dd === 0 || sim >= 0.5 || !!t.billId || (!!row.cat && row.cat === t.cat)
    if (sameAcct ? !alike : !(sim >= 0.5)) continue
    const score = (sameAcct ? 2 : 0) + sim - dd * 0.1
    if (score > bestScore) { best = t; bestScore = score }
  }
  return best
}
