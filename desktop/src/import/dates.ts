// Statement dates: dd/mm/yyyy (UAE default), dd-mm-yyyy, dd.mm.yyyy, yyyy-mm-dd,
// dd MMM yyyy, dd-MMM-yy, dd/mm/yy, MMM dd, yyyy, Excel serial numbers.
// mm/dd is used only when the column proves it (some second part > 12, no first part > 12).

export type DateOrder = 'dmy' | 'mdy'

const MON: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 }
const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?'
const pad = (n: number) => String(n).padStart(2, '0')
const dim = (y: number, m: number) => new Date(y, m, 0).getDate()
const year = (y: string) => (y.length === 2 ? 2000 + Number(y) : Number(y))
const mon = (s: string) => MON[s.toLowerCase().slice(0, s.toLowerCase().startsWith('sept') ? 4 : 3)] ?? MON[s.toLowerCase().slice(0, 3)]

function iso(y: number, m: number, d: number): string | null {
  if (!(y >= 1990 && y <= 2100) || !(m >= 1 && m <= 12) || !(d >= 1 && d <= dim(y, m))) return null
  return y + '-' + pad(m) + '-' + pad(d)
}

const RE_ISO = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:$|[T\s])/
const RE_NUM = /^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})(?:$|\s)/
const RE_DMON = new RegExp('^(\\d{1,2})[-/. ]?(' + MONTHS + ')\\.?[-/., ]?\\s*(\\d{4}|\\d{2})?(?:$|\\s|,)', 'i')
const RE_MOND = new RegExp('^(' + MONTHS + ')\\.?[ -](\\d{1,2})(?:st|nd|rd|th)?,?[ -](\\d{4})(?:$|\\s)', 'i')

/** Two numeric parts that could be either way round, for detectOrder(). */
export function numericParts(s: string): [number, number] | null {
  const m = String(s).trim().match(RE_NUM)
  return m ? [Number(m[1]), Number(m[2])] : null
}

/** dmy unless some value only makes sense as mm/dd. */
export function detectOrder(values: string[]): DateOrder {
  let firstBig = false, secondBig = false
  for (const v of values) {
    const p = numericParts(v)
    if (!p) continue
    if (p[0] > 12) firstBig = true
    if (p[1] > 12) secondBig = true
  }
  return secondBig && !firstBig ? 'mdy' : 'dmy'
}

/** Excel's day count (1900 system) → ISO date. */
export function fromSerial(n: number): string | null {
  if (!(n > 20000 && n < 80000)) return null
  const d = new Date(Date.UTC(1899, 11, 30) + Math.floor(n) * 86400000)
  return iso(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate())
}

/**
 * "YYYY-MM-DD", or null. `fallbackYear` is used for dates printed without a year
 * ("12 Nov" on some card statements).
 */
export function parseDate(input: string | number | null | undefined, order: DateOrder = 'dmy', fallbackYear?: number): string | null {
  if (input == null) return null
  if (typeof input === 'number') return fromSerial(input)
  const s = String(input).replace(/[ ]/g, ' ').trim()
  if (!s) return null
  let m = s.match(RE_ISO)
  if (m) return iso(Number(m[1]), Number(m[2]), Number(m[3]))
  m = s.match(RE_NUM)
  if (m) {
    const a = Number(m[1]), b = Number(m[2]), y = year(m[3])
    return order === 'mdy' ? iso(y, a, b) : iso(y, b, a)
  }
  m = s.match(RE_DMON)
  if (m) {
    const y = m[3] ? year(m[3]) : fallbackYear
    return y ? iso(y, mon(m[2]), Number(m[1])) : null
  }
  m = s.match(RE_MOND)
  if (m) return iso(Number(m[3]), mon(m[1]), Number(m[2]))
  if (/^\d{5}(\.\d+)?$/.test(s)) return fromSerial(Number(s))
  return null
}

export const isDateLike = (s: string | number | null | undefined, order: DateOrder = 'dmy') => parseDate(s, order, 2000) != null

/** Date tokens at the start of a line of PDF text. */
const LEAD = new RegExp(
  '^\\s*(\\d{4}-\\d{2}-\\d{2}|\\d{1,2}[-/.]\\d{1,2}[-/.](?:\\d{4}|\\d{2})|\\d{1,2}[-/ ]?(?:' + MONTHS + ')\\.?(?:[-/ ,]\\s?(?:\\d{4}|\\d{2}))?|(?:' + MONTHS + ')\\.? \\d{1,2},? \\d{4})(?=\\s|$)', 'i')

/**
 * Up to two dates at the start of a line (transaction date, then value date) and the rest.
 * "01/11/2026 02/11/2026 CARREFOUR 120.00" → dates ["01/11/2026","02/11/2026"], rest "CARREFOUR 120.00".
 */
export function leadingDates(line: string): { dates: string[]; rest: string } {
  const dates: string[] = []
  let rest = line
  for (let i = 0; i < 2; i++) {
    const m = rest.match(LEAD)
    if (!m) break
    // "12 Nov 2026" vs "12 November" followed by "2026 ..." — the regex already takes the year.
    dates.push(m[1].trim())
    rest = rest.slice(m[0].length)
  }
  return { dates, rest: rest.trim() }
}
