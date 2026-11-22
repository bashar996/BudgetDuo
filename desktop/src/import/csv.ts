// CSV / TSV text → rows of cells. Handles quotes, doubled quotes, newlines inside
// quotes, a byte-order mark, and picks the delimiter (, ; tab |) from the first lines.

export function detectDelimiter(text: string): string {
  const lines = text.split(/\r?\n/).filter((l) => l.trim()).slice(0, 40)
  let best = ',', bestScore = -1
  for (const d of [',', ';', '\t', '|']) {
    // Count fields outside quotes per line; the delimiter with the most consistent, >1 count wins.
    const counts = lines.map((l) => {
      let n = 0, q = false
      for (const c of l) { if (c === '"') q = !q; else if (c === d && !q) n++ }
      return n
    })
    const rows = counts.filter((n) => n > 0)
    if (!rows.length) continue
    const freq: Record<number, number> = {}
    rows.forEach((n) => (freq[n] = (freq[n] ?? 0) + 1))
    const mode = Math.max(...Object.values(freq))
    const score = mode * 10 + rows.length
    if (score > bestScore) { bestScore = score; best = d }
  }
  return best
}

export function parseCsv(input: string, delimiter?: string): string[][] {
  const text = input.replace(/^﻿/, '')
  const d = delimiter ?? detectDelimiter(text)
  const rows: string[][] = []
  let row: string[] = [], cell = '', q = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++ } else q = false }
      else cell += c
    } else if (c === '"' && cell.trim() === '') { q = true; cell = '' }
    else if (c === d) { row.push(cell.trim()); cell = '' }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++
      row.push(cell.trim()); cell = ''
      rows.push(row); row = []
    } else cell += c
  }
  if (cell !== '' || row.length) { row.push(cell.trim()); rows.push(row) }
  // Drop fully empty lines.
  return rows.filter((r) => r.some((x) => x !== ''))
}

/** Text from a file's bytes: UTF-8, or Windows-1252 when that fails (older bank exports). */
export function decodeText(buf: ArrayBuffer): string {
  const b = new Uint8Array(buf.slice(0, 2))
  if (b[0] === 0xff && b[1] === 0xfe) return new TextDecoder('utf-16le').decode(buf)
  if (b[0] === 0xfe && b[1] === 0xff) return new TextDecoder('utf-16be').decode(buf)
  try { return new TextDecoder('utf-8', { fatal: true }).decode(buf) }
  catch { return new TextDecoder('windows-1252').decode(buf) }
}
