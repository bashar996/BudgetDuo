// Excel (.xlsx, .xls, and the HTML-table ".xls" some banks send) → rows of cells, via SheetJS.
// Date cells come back as "YYYY-MM-DD", numbers as plain strings, the rest as shown in Excel.
import * as XLSX from 'xlsx'
import { fromSerial } from './dates'

export function readSheet(buf: ArrayBuffer | Uint8Array): string[][] {
  const wb = XLSX.read(buf instanceof Uint8Array ? buf : new Uint8Array(buf), { type: 'array', cellDates: false, cellHTML: false, cellFormula: false, sheetStubs: false })
  let best: string[][] = []
  for (const name of wb.SheetNames) {
    const ws = wb.Sheets[name]
    if (!ws || !ws['!ref']) continue
    const r = XLSX.utils.decode_range(ws['!ref'])
    const rows: string[][] = []
    // Bank exports are small; still, stop at 20k rows so a broken range can't hang the app.
    for (let y = r.s.r; y <= Math.min(r.e.r, r.s.r + 20000); y++) {
      const row: string[] = []
      for (let x = r.s.c; x <= Math.min(r.e.c, r.s.c + 60); x++) {
        const c = ws[XLSX.utils.encode_cell({ r: y, c: x })] as XLSX.CellObject | undefined
        row.push(cellText(c))
      }
      if (row.some((v) => v !== '')) rows.push(row)
    }
    // The sheet with the most rows is the statement (others are often a cover page).
    if (rows.length > best.length) best = rows
  }
  return best
}

function cellText(c: XLSX.CellObject | undefined): string {
  if (!c || c.v == null) return ''
  if (c.t === 'd' && c.v instanceof Date) {
    const d = c.v
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0')
  }
  if (c.t === 'n') {
    const v = c.v as number
    if (c.z && XLSX.SSF.is_date(c.z as string)) return fromSerial(v) ?? String(v)
    return String(v)
  }
  if (c.t === 'b') return c.v ? 'TRUE' : 'FALSE'
  return String(c.w ?? c.v).trim()
}
