// Bank descriptions → merchant names: "POS PURCHASE CARD 4XXXXXXXXXXX1234 CARREFOUR MOE DUBAI AE"
// → "Carrefour Moe". The raw text is kept in the entry's note.

const LEAD = /^(?:POS|PURCHASE|PUR|DEBIT CARD|CREDIT CARD|CARD|VISA|MASTERCARD|MASTER CARD|APPLE PAY|GOOGLE PAY|ECOM|E-COM|ONLINE|TXN|TRANSACTION|CONTACTLESS|NFC)\b[\s:\-#.]*/
const PLACES = ['RAS AL KHAIMAH', 'UMM AL QUWAIN', 'ABU DHABI', 'AL AIN', 'DUBAI', 'SHARJAH', 'AJMAN', 'FUJAIRAH', 'RAK', 'DXB', 'AUH', 'UAE', 'ARE', 'AE',
  'US', 'USA', 'GB', 'GBR', 'UK', 'SA', 'SAU', 'IN', 'IND', 'IE', 'IRL', 'NL', 'NLD', 'LU', 'LUX', 'SG', 'SGP', 'QA', 'OM', 'KW', 'BH']
const TRAIL = new RegExp('(?:[\\s,\\-]+(?:' + PLACES.map((p) => p.replace(/ /g, '\\s+')).join('|') + '))+[\\s,.\\-]*$')

const SMALL = new Set(['and', 'of', 'the', 'for', 'at', 'by', 'in', 'on', 'to', 'de'])

function title(s: string): string {
  return s.toLowerCase().split(' ').map((w, i) => {
    if (!w) return w
    if (i > 0 && SMALL.has(w)) return w
    // Short words with no vowels are usually initials: KFC, H&M, TFL.
    if (w.length <= 3 && !/[aeiou]/.test(w) && /[a-z]/.test(w)) return w.toUpperCase()
    if (/\.(com|ae|net|org|io)\b/.test(w)) return w
    return w.replace(/(^|[-'(&/])([a-z])/g, (_, p: string, c: string) => p + c.toUpperCase())
  }).join(' ')
}

export function cleanName(raw: string): string {
  let s = ' ' + String(raw).toUpperCase().replace(/[\u00a0\t]/g, ' ') + ' '
  // Card masks: 4XXXXXXXXXXX1234, 4111********1234, ****1234, XXXX1234, xxxx-xxxx-xxxx-1234
  s = s.replace(/\b\d{0,6}[X*•]{4,}[\d X*•-]*\d{0,4}\b/g, ' ')
  s = s.replace(/[*•]{2,}\d{2,4}\b/g, ' ')
  s = s.replace(/\b(?:[X*]{4}[\s-]?){2,}\d{4}\b/g, ' ')
  // Reference codes.
  s = s.replace(/\b(?:REF(?:ERENCE)?|REF NO|RRN|ARN|AUTH(?:CODE)?|APPROVAL CODE|TXN ID|TRN|SEQ|ID)\b\.?\s*(?:NO\.?|NUMBER|#)?\s*[:#\-]?\s*[A-Z0-9\-\/]*\d[A-Z0-9\-\/]*/g, ' ')
  // Dates, times and amounts that some banks repeat in the description.
  s = s.replace(/\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b/g, ' ').replace(/\b\d{1,2}:\d{2}(?::\d{2})?\b/g, ' ')
  s = s.replace(/\b(?:AED|USD|EUR|GBP|SAR)\s?\d[\d,]*(?:\.\d+)?\b/g, ' ')
  s = s.replace(/\d{5,}/g, ' ')
  s = s.replace(/\s+/g, ' ').trim()
  for (let i = 0; i < 4; i++) {
    const n = s.replace(LEAD, '')
    if (n === s) break
    s = n.trim()
  }
  // "TALABAT*ORDER 123" → "TALABAT"; "SQ *BLUE BOTTLE" keeps "BLUE BOTTLE".
  if (s.includes('*')) {
    const [a, ...b] = s.split('*').map((x) => x.trim())
    s = a.replace(/[^A-Z]/g, '').length >= 3 ? a : [a, ...b].filter((x) => x.length > 0 && !/^(SQ|TST|PP|PAYPAL)$/.test(x)).join(' ')
  }
  for (let i = 0; i < 4; i++) {
    const n = s.replace(TRAIL, '').replace(/[\s,.\-#:\/]+$/, '').replace(/^[\s,.\-#:\/]+/, '')
    if (n === s) break
    s = n
  }
  s = s.replace(/\s+/g, ' ').trim()
  if (!s) s = String(raw).replace(/\s+/g, ' ').trim()
  let out = title(s)
  if (out.length > 40) out = out.slice(0, 40).replace(/\s+\S*$/, '') || out.slice(0, 40)
  return out
}

/** Lower-case words for comparing names. */
export function tokens(s: string): string[] {
  return String(s).toLowerCase().replace(/[^a-z0-9\u0600-\u06ff&]+/g, ' ').split(' ').filter((w) => w.length > 1 && !/^\d+$/.test(w))
}

/** Word overlap between two names, 0..1 (shared words ÷ the shorter name's words). */
export function similarity(a: string, b: string): number {
  const x = new Set(tokens(a)), y = new Set(tokens(b))
  if (!x.size || !y.size) return 0
  let n = 0
  x.forEach((w) => { if (y.has(w)) n++ })
  return n / Math.min(x.size, y.size)
}
