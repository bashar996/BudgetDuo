/** 12,345 · −12,345 · 12.50 (true minus sign, decimals only when needed) */
export function num(n: number): string {
  const r = Math.abs(n % 1) > 0.004 ? n : Math.round(n)
  const dec = Math.abs(r % 1) > 0.004 ? 2 : 0
  return (r < 0 ? '−' : '') + Math.abs(r).toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec })
}

/** "AED 12,345" (a space after multi-letter currencies, none after $ € £) */
export function fmt(n: number, currency: string): string {
  const s = num(n), neg = s[0] === '−'
  return (neg ? '−' : '') + currency + (currency.length > 1 ? ' ' : '') + (neg ? s.slice(1) : s)
}

/** 0..1 → "42.0%" for widths and heights. */
export const pc = (x: number) => Math.max(0, Math.min(100, (x || 0) * 100)).toFixed(1) + '%'

export const sum = <T,>(a: T[], k: (x: T) => number) => a.reduce((s, x) => s + k(x), 0)

/** CSV with every cell quoted. */
export const toCsv = (rows: (string | number)[][]) =>
  rows.map((r) => r.map((x) => '"' + String(x).replace(/"/g, '""') + '"').join(',')).join('\n')

/** Saves text as a file (Electron shows the save dialog). */
export function download(name: string, text: string, type: string) {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([text], { type }))
  a.download = name
  a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 4000)
}
