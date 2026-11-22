// Category suggestions: what you used before for the same merchant, then keyword rules.
import { tokens } from './clean'

export const RULES: [string, string[]][] = [
  ['groceries', ['carrefour', 'lulu', 'spinneys', 'waitrose', 'choithrams', 'union coop', 'unioncoop', 'coop', 'géant', 'geant', 'viva', 'west zone', 'al maya', 'nesto', 'grandiose', 'kibsons', 'instashop', 'el grocer', 'elgrocer', 'supermarket', 'hypermarket', 'grocery', 'bakery', 'fruit']],
  ['transport', ['adnoc', 'enoc', 'eppco', 'emarat', 'petrol', 'fuel', 'salik', 'darb', 'rta', 'nol', 'parking', 'mawaqif', 'careem ride', 'careem car', 'uber', 'taxi', 'valtrans', 'hala']],
  ['utilities', ['dewa', 'addc', 'aadc', 'sewa', 'fewa', 'etihad water', 'empower', 'tabreed', 'etisalat', 'e&', 'du', 'du.ae', 'virgin mobile', 'internet', 'broadband', 'chiller', 'district cooling', 'gas']],
  ['dining', ['talabat', 'deliveroo', 'careem food', 'noon food', 'zomato', 'restaurant', 'cafe', 'café', 'coffee', 'starbucks', 'costa', 'tim hortons', 'mcdonald', 'kfc', 'burger', 'pizza', 'shawarma', 'karak', 'bistro', 'grill', 'kitchen', 'eatery', 'dining']],
  ['subs', ['netflix', 'spotify', 'apple.com/bill', 'apple.com', 'itunes', 'youtube', 'google *', 'google one', 'osn', 'shahid', 'anghami', 'disney', 'amazon prime', 'prime video', 'icloud', 'chatgpt', 'openai', 'microsoft', 'adobe', 'playstation', 'xbox', 'starzplay']],
  ['shopping', ['noon', 'amazon', 'namshi', 'ikea', 'home centre', 'home box', 'centrepoint', 'max fashion', 'h&m', 'zara', 'sharaf dg', 'jumbo', 'virgin megastore', 'ace hardware', 'dragon mart', 'mall', 'store', 'shop', 'trading']],
  ['health', ['pharmacy', 'aster', 'life pharmacy', 'boots', 'bin sina', 'binsina', 'clinic', 'hospital', 'medical', 'dental', 'mediclinic', 'nmc', 'health', 'optic', 'gym', 'fitness']],
  ['kids', ['nursery', 'school', 'kids', 'toys', 'hamleys', 'mothercare', 'babyshop', 'early learning']],
  ['insurance', ['insurance', 'takaful', 'axa', 'oman insurance', 'sukoon', 'orient insurance', 'gig', 'daman']],
  ['travel', ['emirates', 'flydubai', 'air arabia', 'etihad airways', 'booking.com', 'airbnb', 'agoda', 'expedia', 'hotel', 'airline', 'travel', 'visa fee', 'ica', 'gdrfa']],
  ['fun', ['vox', 'reel cinemas', 'novo', 'cinema', 'theatre', 'theme park', 'img worlds', 'ferrari world', 'global village', 'bowling', 'ticket']],
  ['gifts', ['charity', 'donation', 'red crescent', 'dubai cares', 'gift', 'flowers']],
  ['housing', ['rent', 'ejari', 'landlord', 'real estate', 'properties', 'maintenance', 'service charge', 'building']],
  ['debt', ['loan', 'installment', 'instalment', 'emi', 'finance repayment']],
]

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
/** Short keywords ("du", "rta", "emi", "rent") must be whole words; longer ones match anywhere. */
const COMPILED: [string, RegExp[]][] = RULES.map(([cat, kws]) => [cat, kws.map((k) => {
  const t = k.trim()
  return t.length <= 4 && /^[a-z&]+$/.test(t)
    ? new RegExp('(^|[^a-z0-9])' + esc(t) + '($|[^a-z0-9])')
    : new RegExp(esc(k))
})])
// Bank names that would otherwise read as travel ("Emirates NBD") or similar.
const NOISE = /\b(emirates nbd|emirates islamic|enbd|mashreq|adcb|fab|first abu dhabi|rakbank|dubai islamic|cbd|hsbc|citi(bank)?)\b/g

export function ruleCategory(raw: string, has: (id: string) => boolean): string | null {
  const s = ' ' + String(raw).toLowerCase().replace(NOISE, ' ').replace(/\s+/g, ' ') + ' '
  for (const [cat, res] of COMPILED) {
    if (!has(cat)) continue
    if (res.some((re) => re.test(s))) return cat
  }
  return null
}

/** First two words of a name, the key history is matched on. */
export const histKey = (name: string) => tokens(name).slice(0, 2).join(' ')

/** Most-used category per merchant key, from existing expenses. */
export function historyIndex(tx: { type: string; name: string; cat: string }[], has: (id: string) => boolean): Map<string, string> {
  const counts = new Map<string, Map<string, number>>()
  for (const t of tx) {
    if (t.type !== 'exp' || !has(t.cat)) continue
    const k = histKey(t.name)
    if (!k) continue
    const m = counts.get(k) ?? new Map<string, number>()
    m.set(t.cat, (m.get(t.cat) ?? 0) + 1)
    counts.set(k, m)
  }
  const out = new Map<string, string>()
  counts.forEach((m, k) => {
    let best = '', n = 0
    m.forEach((v, c) => { if (v > n) { n = v; best = c } })
    out.set(k, best)
  })
  return out
}

export function suggestCategory(raw: string, name: string, hist: Map<string, string>, has: (id: string) => boolean): { cat: string; how: 'history' | 'rule' } | null {
  const h = hist.get(histKey(name))
  if (h) return { cat: h, how: 'history' }
  const r = ruleCategory(raw, has)
  return r ? { cat: r, how: 'rule' } : null
}
