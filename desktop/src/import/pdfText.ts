// PDF statements, the pure part: text items → lines, lines → statement rows.
// Best effort: lines that start with a date and hold at least one amount are transactions;
// lines without a date or amount right after one continue its description.
import { amountTokens, signed, type Amount } from './amounts'
import { detectOrder, leadingDates, numericParts, parseDate } from './dates'
import { NOISE_ROW, prepare, type RawRow } from './detect'

export interface PdfItem { str: string; x: number; y: number; w: number; h: number; page: number }

/** Groups positioned text into lines (top to bottom), with wide gaps kept as double spaces. */
export function itemsToLines(items: PdfItem[]): string[] {
  const out: string[] = []
  const pages = new Map<number, PdfItem[]>()
  items.forEach((it) => { if (it.str.trim()) { const p = pages.get(it.page) ?? []; p.push(it); pages.set(it.page, p) } })
  for (const page of [...pages.keys()].sort((a, b) => a - b)) {
    const list = pages.get(page)!.sort((a, b) => b.y - a.y || a.x - b.x)
    const lines: { y: number; h: number; items: PdfItem[] }[] = []
    for (const it of list) {
      const tol = Math.max(2, Math.min(it.h || 8, 12) * 0.45)
      const line = lines.find((l) => Math.abs(l.y - it.y) <= tol)
      if (line) line.items.push(it)
      else lines.push({ y: it.y, h: it.h, items: [it] })
    }
    lines.sort((a, b) => b.y - a.y)
    for (const l of lines) {
      const its = l.items.sort((a, b) => a.x - b.x)
      let s = '', end = -Infinity
      for (const it of its) {
        const ch = Math.max(2, (it.h || 8) * 0.5)
        const gap = it.x - end
        if (s) s += gap > ch * 1.6 ? '   ' : gap > ch * 0.12 && !s.endsWith(' ') && !it.str.startsWith(' ') ? ' ' : ''
        s += it.str
        end = it.x + (it.w || it.str.length * ch)
      }
      out.push(s.replace(/\s+$/, ''))
    }
  }
  return out
}

const CONT_NOISE = /\bpage\s+\d+|\bof\s+\d+\s*$|statement|balance|total|account\s+(no|number)|customer|iban|swift|continued|^\s*(date|description|debit|credit)\b/i

/** Transaction rows from statement lines. */
export function linesToRows(lines: string[], isCard = false): { rows: RawRow[]; order: 'dmy' | 'mdy' } {
  const lead = lines.map((l) => leadingDates(l))
  const order = detectOrder(lead.flatMap((x) => x.dates.filter((d) => numericParts(d))))
  // A year for dates printed without one ("12 Nov"): the latest full year in the text.
  const years = lines.join(' ').match(/\b20\d{2}\b/g)?.map(Number).filter((y) => y >= 2000 && y <= 2100) ?? []
  const year = years.length ? Math.max(...years) : new Date().getFullYear()

  const rows: (RawRow & { cont: number })[] = []
  let last: (RawRow & { cont: number }) | null = null
  let opening: number | null = null
  lines.forEach((line, i) => {
    const { dates, rest } = lead[i]
    const date = dates.length ? parseDate(dates[0], order, year) ?? (dates[1] ? parseDate(dates[1], order, year) : null) : null
    const toks = amountTokens(date ? rest : line)
    if (!date) {
      if (NOISE_ROW.test(line) && toks.length && opening == null && !rows.length) opening = signed(toks[toks.length - 1].amount)
      if (last && !toks.length && last.cont < 2 && line.trim() && !CONT_NOISE.test(line) && line.trim().length < 80) {
        last.desc += ' ' + line.trim(); last.raw += ' ' + line.trim(); last.cont++
      } else if (toks.length || CONT_NOISE.test(line)) last = null
      return
    }
    if (!toks.length) { last = null; return }
    let desc = rest.slice(0, toks[0].index).trim()
    if (!desc) desc = rest.slice(toks[toks.length - 1].end).trim()
    desc = desc.replace(/\s{2,}/g, ' ')
    if (NOISE_ROW.test(desc)) {
      if (opening == null && !rows.length) opening = signed(toks[toks.length - 1].amount)
      last = null
      return
    }
    const a = toks.map((t) => t.amount)
    let money: Amount, fixed: number | null = null, balance: number | null = null
    if (a.length >= 3) {
      // Debit, Credit, Balance.
      const d = Math.abs(a[a.length - 3].value), c = Math.abs(a[a.length - 2].value)
      money = { value: Math.abs(c - d), mark: null }; fixed = c >= d ? 1 : -1
      balance = signed(a[a.length - 1])
    } else if (a.length === 2) {
      money = a[0]; balance = signed(a[1])
    } else money = a[0]
    if (!money.value) { last = null; return }
    const row = { i, date, desc, money, fixed, balance, raw: line.replace(/\s{2,}/g, '  ').trim(), cont: 0 }
    rows.push(row)
    last = row
  })
  // The opening balance helps decide the first row's direction.
  const all: RawRow[] = rows.map(({ cont: _c, ...r }) => r)
  if (opening != null && all.length && all[0].balance != null) all.unshift({ i: -1, date: all[0].date, desc: '', money: { value: 0, mark: null }, fixed: null, balance: opening, raw: '' })
  prepare(all, isCard)
  return { rows: all.filter((r) => r.i >= 0), order }
}
