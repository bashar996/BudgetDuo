// A dropped or chosen file → a table (CSV, Excel) or text lines (PDF).
import { decodeText, parseCsv } from './csv'
import { itemsToLines } from './pdfText'

export type Loaded = { kind: 'table'; table: string[][] } | { kind: 'pdf'; lines: string[] }

export const ACCEPT = '.csv,.tsv,.txt,.xlsx,.xls,.pdf'
export const isStatementFile = (name: string) => /\.(csv|tsv|txt|xlsx|xlsm|xls|pdf)$/i.test(name)

export async function loadFile(file: File, password?: string): Promise<Loaded> {
  if (file.size > 40 * 1024 * 1024) throw new Error('That file is too big for a statement (over 40 MB).')
  const buf = await file.arrayBuffer()
  const head = new Uint8Array(buf.slice(0, 8))
  const isPdf = /\.pdf$/i.test(file.name) || (head[0] === 0x25 && head[1] === 0x50 && head[2] === 0x44 && head[3] === 0x46)
  if (isPdf) {
    const { pdfItems } = await import('./pdf')
    const lines = itemsToLines(await pdfItems(buf, password))
    if (!lines.length) throw new Error('This PDF has no text to read — it may be a scanned image. Try the CSV or Excel download from your bank instead.')
    return { kind: 'pdf', lines }
  }
  const zip = head[0] === 0x50 && head[1] === 0x4b, ole = head[0] === 0xd0 && head[1] === 0xcf
  if (zip || ole || /\.xls[xm]?$/i.test(file.name)) {
    const { readSheet } = await import('./xlsx')
    try {
      return { kind: 'table', table: readSheet(buf) }
    } catch (e: any) {
      if (/password|encrypt/i.test(String(e?.message))) throw new Error('This spreadsheet is password-protected. Open it in Excel or Numbers, save a copy without the password, and import that.')
      throw new Error('This spreadsheet couldn’t be read' + (e?.message ? ' (' + e.message + ')' : '') + '.')
    }
  }
  return { kind: 'table', table: parseCsv(decodeText(buf)) }
}
