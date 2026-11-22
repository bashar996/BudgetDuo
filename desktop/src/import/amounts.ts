// Money amounts as banks print them: "1,234.50", "(1,234.50)", "-1234.5", "1,234.50 Cr",
// "AED 1,234.50-", "1.234,50". Signs: parentheses or a minus = negative; a trailing
// "Cr" means money in and "Dr" money out, whatever the column's sign convention.

export type Mark = 'cr' | 'dr' | null
export interface Amount { value: number; mark: Mark }

const CURRENCY = /\b(AED|USD|EUR|GBP|SAR|QAR|KWD|BHD|OMR|INR|DHS?|DH)\b|د\.إ|[$€£₹]/gi

/** Parses one cell or token; null when it isn't an amount. */
export function parseAmount(input: string | number | null | undefined): Amount | null {
  if (input == null) return null
  if (typeof input === 'number') return Number.isFinite(input) ? { value: input, mark: null } : null
  let s = String(input).replace(/[   ]/g, ' ').trim()
  if (!s) return null
  let mark: Mark = null
  const m = s.match(/(?:(?<=[\d)])|\s+)(CR|DR)\.?$/i) ?? s.match(/\s+(C|D)$/i)
  if (m && /\d/.test(s.slice(0, m.index))) {
    const k = m[1].toLowerCase()
    mark = k === 'cr' || k === 'c' ? 'cr' : 'dr'
    s = s.slice(0, m.index).trim()
  }
  s = s.replace(CURRENCY, '').trim()
  let neg = false
  if (/^\(.*\)$/.test(s)) { neg = true; s = s.slice(1, -1).trim() }
  s = s.replace(/^[−–]/, '-').replace(/[−–]$/, '-')
  if (s.startsWith('-')) { neg = !neg; s = s.slice(1).trim() }
  else if (s.endsWith('-')) { neg = !neg; s = s.slice(0, -1).trim() }
  else if (s.startsWith('+')) s = s.slice(1).trim()
  s = s.replace(CURRENCY, '').trim()
  if (!s) return null
  // European style "1.234,50" or "1234,50"
  if (/^\d{1,3}(\.\d{3})+,\d{1,2}$/.test(s) || /^\d+,\d{1,2}$/.test(s)) s = s.replace(/\./g, '').replace(',', '.')
  else if (/^\d{1,3}( \d{3})+(\.\d+)?$/.test(s)) s = s.replace(/ /g, '')
  else s = s.replace(/,/g, '')
  if (!/^\d+(\.\d+)?$|^\.\d+$/.test(s)) return null
  const v = parseFloat(s)
  if (!Number.isFinite(v)) return null
  return { value: neg ? -v : v, mark }
}

/** The signed amount: + money in, − money out. A Cr/Dr mark wins over the sign. */
export function signed(a: Amount, posIsOut = false): number {
  const v = Math.abs(a.value)
  if (a.mark === 'cr') return v
  if (a.mark === 'dr') return -v
  return posIsOut ? -a.value : a.value
}

export const round2 = (n: number) => Math.round(n * 100) / 100

/**
 * Amount tokens in a line of statement text (PDF). Only numbers with two decimals count,
 * so reference numbers and dates are left alone. Returns them left to right.
 */
export interface Token { text: string; index: number; end: number; amount: Amount }
const TOKEN = /(?:(?:AED|USD|EUR|GBP|SAR)\s?)?\(?(?:[-−]\s?)?(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}\)?(?:-|\s?(?:CR|DR|Cr|Dr|cr|dr)\b)?/g
export function amountTokens(line: string): Token[] {
  const out: Token[] = []
  for (const m of line.matchAll(TOKEN)) {
    const idx = m.index ?? 0
    // Not glued to letters or other digits (e.g. card masks, "ABC123.45").
    const before = line[idx - 1], after = line[idx + m[0].length]
    if (before && /[A-Za-z0-9.\/]/.test(before)) continue
    if (after && /[A-Za-z0-9\/]/.test(after)) continue
    const amount = parseAmount(m[0])
    if (amount) out.push({ text: m[0], index: idx, end: idx + m[0].length, amount })
  }
  return out
}
