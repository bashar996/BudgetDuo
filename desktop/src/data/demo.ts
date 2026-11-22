// The design's sample household (Bashar & Eman), for the ?demo preview only.
// Real use always starts empty.
import { CATS } from './catalog'
import type { Account, Bill, Data, Goal, Tx, Who } from './types'
import { addM, dim, pad, ymOf } from '../lib/dates'

const SAMPLE: Record<string, { n: number; lo: number; hi: number; m: string[]; who?: Who }> = {
  groceries: { n: 9, lo: 150, hi: 450, m: ['Hypermarket', 'Corner grocery', 'Fruit & veg market', 'Bakery', 'Online groceries'] },
  transport: { n: 7, lo: 60, hi: 260, m: ['Petrol', 'Road tolls', 'Parking', 'Taxi'] },
  health: { n: 2, lo: 60, hi: 180, m: ['Pharmacy', 'Clinic visit'] },
  kids: { n: 3, lo: 60, hi: 220, m: ['School supplies', 'Kids’ clothes', 'Swimming lessons', 'Toy shop'] },
  dining: { n: 8, lo: 60, hi: 280, m: ['Shawarma place', 'Café', 'Friday brunch', 'Delivery order', 'Sushi night', 'Karak & snacks'] },
  fun: { n: 3, lo: 60, hi: 200, m: ['Cinema', 'Beach day', 'Desert trip', 'Bookshop'] },
  shopping: { n: 4, lo: 100, hi: 450, m: ['Home goods', 'Clothing', 'Hardware store', 'Online order'] },
  travel: { n: 1, lo: 300, hi: 1400, m: ['Flight tickets', 'Staycation', 'Visa fees'] },
  gifts: { n: 1, lo: 100, hi: 400, m: ['Eid gifts', 'Birthday gift', 'Charity'] },
  allowA: { n: 4, lo: 40, hi: 200, who: 'A', m: ['Lunch out', 'Hobby shop', 'Barber', 'Games'] },
  allowB: { n: 4, lo: 40, hi: 200, who: 'B', m: ['Coffee with friends', 'Yoga class', 'Books', 'Skincare'] },
}
const LIMITS: Record<string, number> = { housing: 7500, groceries: 3000, utilities: 1550, transport: 1400, insurance: 850, health: 600, kids: 2800, debt: 3300, dining: 1400, fun: 500, shopping: 1200, subs: 150, travel: 1500, gifts: 500, allowA: 800, allowB: 800 }
const BILLS: [number, string, number, string, number?][] = [[1, 'Rent', 7500, 'housing'], [2, 'Nursery fees', 2200, 'kids'], [3, 'Gym membership', 250, 'health'], [5, 'Car insurance', 420, 'insurance'], [5, 'Health cover top-up', 380, 'insurance'], [8, 'Electricity & water', 780, 'utilities'], [9, 'Video streaming', 56, 'subs', 1], [12, 'Home internet & TV', 389, 'utilities'], [14, 'Music family plan', 33, 'subs', 1], [18, 'Mobile plans', 350, 'utilities'], [22, 'Cloud storage', 11, 'subs', 1], [26, 'Car loan', 1850, 'debt'], [28, 'Personal loan', 1450, 'debt']]

export function demoData(today = new Date()): Data {
  let s = 11
  const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647
  const cur = ymOf(today)
  const tx: Tx[] = []
  let id = 1
  const goals: (Goal & { saved: number })[] = [
    { id: 'g1', name: 'Emergency fund', target: 100000, saved: 62000, startSaved: 0, monthly: 3000, acct: 'a4', auto: true },
    { id: 'g2', name: 'Summer trip', target: 18000, saved: 7500, startSaved: 0, monthly: 1500, acct: 'a4', due: addM(cur, 7), auto: true },
    { id: 'g3', name: 'School fees fund', target: 24000, saved: 11000, startSaved: 0, monthly: 2000, acct: 'a4', due: addM(cur, 5), auto: true },
    { id: 'g4', name: 'Home down payment', target: 300000, saved: 106500, startSaved: 0, monthly: 1500, acct: 'a5', auto: true },
  ]
  const bills: Bill[] = BILLS.map((b, i) => ({ id: 'b' + i, day: b[0], name: b[1], amt: b[2], cat: b[3], sub: !!b[4], paid: {} }))
  for (let k = -5; k <= 0; k++) {
    const ym = addM(cur, k), dm = dim(ym), last = k === 0 ? today.getDate() : dm
    const add = (day: number, name: string, cat: string, amt: number, who: Who, type: Tx['type'], billId?: string, acct = 'a1', x: Partial<Tx> = {}) => {
      if (day <= last) tx.push({ id: k === 0 && billId ? 'bill-' + billId + '-' + ym : 't' + id, date: ym + '-' + pad(day), name, cat, amt: Math.round(amt), who, type, billId, acct, createdAt: new Date(2026, 0, 1, 0, 0, id++), ...x })
    }
    add(1, 'Salary', 'income', 21000, 'A', 'inc'); add(3, 'Salary', 'income', 15500, 'B', 'inc')
    goals.forEach((g) => add(4, 'Auto-save · ' + g.name, 'transfer', g.monthly, 'J', 'xfer', undefined, 'a1', { to: g.acct, pot: g.id, potDir: 'in' }))
    bills.forEach((b) => { if (b.day <= last) { b.paid[ym] = true; add(b.day, b.name, b.cat, b.amt, 'J', 'exp', b.id) } })
    CATS.forEach((c) => {
      const m = SAMPLE[c.id]
      if (!m) return
      for (let i = 0; i < m.n; i++) {
        const day = 1 + Math.floor(rnd() * dm), amt = m.lo + rnd() * (m.hi - m.lo), r = rnd(), name = m.m[Math.floor(rnd() * m.m.length)], r2 = rnd()
        add(day, name, c.id, amt, m.who || (r < 0.4 ? 'A' : r < 0.75 ? 'B' : 'J'), 'exp', undefined, r2 < 0.28 ? 'a3' : r2 < 0.36 ? 'a2' : 'a1')
      }
    })
  }
  const now: (Account & { balance: number })[] = [
    { id: 'a1', name: 'Joint current account', type: 'current', who: 'J', bank: 'Main bank', last4: '4821', balance: 24600, opening: 0 },
    { id: 'a2', name: 'Cash at home', type: 'cash', who: 'J', balance: 1200, opening: 0 },
    { id: 'a3', name: 'Shared credit card', type: 'card', who: 'J', bank: 'Main bank', last4: '0937', balance: -6400, limit: 25000, apr: 36, opening: 0 },
    { id: 'a4', name: 'High-yield saver', type: 'save', who: 'J', bank: 'Online bank', apy: 4.25, balance: 84000, opening: 0 },
    { id: 'a5', name: 'Home fixed deposit', type: 'save', who: 'J', bank: 'Main bank', apy: 5.1, balance: 106500, opening: 0 },
    { id: 'a6', name: 'Brokerage', type: 'invest', who: 'J', balance: 64000, opening: 0, cost: 52000 },
    { id: 'a7', name: 'Long-term investment plan', type: 'invest', who: 'A', balance: 92000, opening: 0, cost: 80000 },
    { id: 'a8', name: 'Long-term investment plan', type: 'invest', who: 'B', balance: 58000, opening: 0 },
  ]
  // Opening balances so that today's balances match the design.
  const eff: Record<string, number> = {}, pots: Record<string, number> = {}
  for (const t of tx) {
    if (t.type === 'exp') eff[t.acct] = (eff[t.acct] ?? 0) - t.amt
    else if (t.type === 'inc') eff[t.acct] = (eff[t.acct] ?? 0) + t.amt
    else { eff[t.acct] = (eff[t.acct] ?? 0) - t.amt; if (t.to) eff[t.to] = (eff[t.to] ?? 0) + t.amt; if (t.pot) pots[t.pot] = (pots[t.pot] ?? 0) + t.amt }
  }
  const accounts: Account[] = now.map(({ balance, ...a }) => ({ ...a, opening: balance - (eff[a.id] ?? 0) }))
  const goalsOut: Goal[] = goals.map(({ saved, ...g }) => ({ ...g, startSaved: saved - (pots[g.id] ?? 0) }))

  return {
    household: {
      nameA: 'Bashar', nameB: 'Eman', currency: 'AED', members: ['demo'], memberWho: { demo: 'A' },
      budgets: LIMITS, incomes: [{ who: 'A', amt: 21000, day: 1 }, { who: 'B', amt: 15500, day: 3 }],
      checks: {}, roundSwept: {}, custom: [], strat: 'avalanche', extra: 1000, roundUpPot: 'g1',
      budgetStyle: 'Zero-based', rollover: false, cushion: 5000, coachTips: true, splitMode: 'One joint pot', splitRule: '50/50',
      settled: {}, roundUps: true, sweep: false,
    },
    tx, accounts, bills, goals: goalsOut,
    debts: [{ id: 'd1', name: 'Car loan', balance: 68000, apr: 4.2, min: 1850 }, { id: 'd2', name: 'Personal loan', balance: 41000, apr: 7.9, min: 1450 }],
    planned: [{ id: 'p1', name: 'New sofa', cost: 5200, A: true, B: true }, { id: 'p2', name: 'Stand mixer', cost: 1600, A: false, B: true }, { id: 'p3', name: 'Anniversary weekend', cost: 2400, A: true, B: true }, { id: 'p4', name: 'Laptop upgrade', cost: 6000, A: true, B: false }],
    // Preview only: real households start with no assets and no investment costs.
    assets: [{ id: 's1', name: 'Family car', kind: 'vehicle', value: 78000 }, { id: 's2', name: 'Gold & jewellery', kind: 'gold', value: 36000 }],
    trips: [{ id: 'e1', name: 'Eid break getaway', when: 'Mar 2027', budget: 9000, spent: 3200 }, { id: 'e2', name: 'Kids’ birthday party', when: 'Jan 2027', budget: 2500, spent: 600 }, { id: 'e3', name: 'Summer family visit', when: 'Jul 2027', budget: 7500, spent: 0 }],
  }
}

/** Empty household, for previewing the first-run checklist (?demo=empty). */
export function emptyData(): Data {
  return {
    household: { nameA: 'Bashar', nameB: 'Eman', currency: 'AED', members: ['demo'], memberWho: { demo: 'A' }, budgets: {}, incomes: [{ who: 'A', amt: 0, day: 1 }, { who: 'B', amt: 0, day: 1 }], checks: {}, roundSwept: {}, custom: [], strat: 'avalanche', extra: 0 },
    tx: [], accounts: [], bills: [], goals: [], debts: [], planned: [], trips: [], assets: [],
  }
}
