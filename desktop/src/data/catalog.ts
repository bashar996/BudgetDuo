import type { AssetKind, Household, Who } from './types'

export type Group = 'needs' | 'wants' | 'personal'
export interface Category { id: string; name: string; g: Group; h: number; who?: Who; custom?: boolean; variable?: boolean }

/** Built-in categories (same ids as the iPhone app). `h` picks the dot colour. */
export const CATS: Category[] = [
  { id: 'housing', name: 'Housing', g: 'needs', h: 255 },
  { id: 'groceries', name: 'Groceries', g: 'needs', h: 145, variable: true },
  { id: 'utilities', name: 'Utilities', g: 'needs', h: 215 },
  { id: 'transport', name: 'Transport', g: 'needs', h: 190, variable: true },
  { id: 'insurance', name: 'Insurance', g: 'needs', h: 285 },
  { id: 'health', name: 'Health', g: 'needs', h: 170, variable: true },
  { id: 'kids', name: 'Kids & family', g: 'needs', h: 55, variable: true },
  { id: 'debt', name: 'Debt payments', g: 'needs', h: 320 },
  { id: 'dining', name: 'Dining out', g: 'wants', h: 35, variable: true },
  { id: 'fun', name: 'Entertainment', g: 'wants', h: 350, variable: true },
  { id: 'shopping', name: 'Shopping', g: 'wants', h: 75, variable: true },
  { id: 'subs', name: 'Subscriptions', g: 'wants', h: 300 },
  { id: 'travel', name: 'Travel & events', g: 'wants', h: 105, variable: true },
  { id: 'gifts', name: 'Gifts & giving', g: 'wants', h: 15, variable: true },
  { id: 'allowA', name: '', g: 'personal', h: 35, who: 'A', variable: true },
  { id: 'allowB', name: '', g: 'personal', h: 275, who: 'B', variable: true },
]

export const GROUPS: [Group, string][] = [['needs', 'Needs'], ['wants', 'Wants'], ['personal', 'Pocket money']]

/** Category dot colour: shades of violet. */
export const hue = (h: number) => 'oklch(' + (0.42 + (h / 360) * 0.4).toFixed(2) + ' 0.11 290)'

/** Pocket money can't be renamed, moved or deleted. */
export const LOCKED = ['allowA', 'allowB']

/** The household's categories: built-ins (minus catDel, with catOv applied) plus its own. */
export function allCategories(H: Pick<Household, 'custom' | 'catOv' | 'catDel' | 'nameA' | 'nameB'>): (Category & { color: string })[] {
  const gone = H.catDel ?? [], ov = H.catOv ?? {}, nameA = H.nameA, nameB = H.nameB
  return CATS.filter((c) => !gone.includes(c.id) || LOCKED.includes(c.id))
    .map((c) => (ov[c.id] && !LOCKED.includes(c.id) ? { ...c, name: ov[c.id].name, g: ov[c.id].g } : c))
    .concat((H.custom ?? []).map((c) => ({ id: c.id, name: c.name, g: c.g, h: 200, custom: true, variable: true })))
    .map((c) => ({
      ...c,
      name: c.id === 'allowA' ? nameA + '’s pocket money' : c.id === 'allowB' ? nameB + '’s pocket money' : c.name,
      color: hue(c.h),
    }))
}

/** First remaining category when a default one was deleted (Groceries, Travel, Shopping, Utilities). */
export function catOr(cats: { id: string }[], id: string) {
  return (cats.find((c) => c.id === id) ?? cats[0])?.id ?? id
}

export const ASSET_KINDS: [AssetKind, string][] = [
  ['property', 'Property'], ['vehicle', 'Vehicle'], ['gold', 'Gold & jewellery'], ['business', 'Business'], ['other', 'Other'],
]
export const assetKind = (k?: string) => ASSET_KINDS.find((x) => x[0] === k)?.[1] ?? 'Other'

export const CHECKS = [
  'Look at the categories that ran over',
  'Confirm next month’s bills',
  'Top up the savings goals',
  'Agree on planned purchases',
  'Pick one thing to celebrate',
]

export const CURRENCIES = ['AED', 'د.إ', 'SAR', '$', '€', '£']

export const ACCOUNT_TYPES: Record<string, [string, string]> = {
  current: ['Current account', 'var(--ink)'],
  cash: ['Cash', 'var(--mute)'],
  card: ['Credit card', 'var(--a)'],
  save: ['Savings', 'var(--acc)'],
  invest: ['Investment', 'var(--b)'],
}
