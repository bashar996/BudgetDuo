// Pay, bills, loans, planned purchases and trips: name, amount and one extra field.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Who } from '../data/types'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'
import { ChipGroup, Pair, TextField, parse } from './parts'

type Kind = 'income' | 'bill' | 'debt' | 'planned' | 'event'

/** The design's ITEM table. */
const ITEM: Record<Kind, { t: string; al: string; el?: string; text?: boolean }> = {
  income: { t: 'pay', al: 'Monthly take-home pay', el: 'Payday (day of the month)' },
  bill: { t: 'bill', al: 'Amount each month', el: 'Day of the month it’s due' },
  debt: { t: 'debt', al: 'Balance owed', el: 'Interest rate (APR %)' },
  planned: { t: 'planned purchase', al: 'Expected cost' },
  event: { t: 'trip or event', al: 'Total budget', el: 'When (e.g. Mar 2027)', text: true },
}

const clampDay = (v: number) => Math.min(31, Math.max(1, Math.round(v) || 1))

export function ItemPanel({ L, kind, who, id }: { L: Ledger; kind: Kind; who?: Who; id?: string }) {
  const { act } = useStore()
  const { close } = useUI()
  const I = ITEM[kind]
  const D = L.data
  const bill = kind === 'bill' && id ? D.bills.find((x) => x.id === id) : undefined
  const debt = kind === 'debt' && id ? D.debts.find((x) => x.id === id) : undefined
  const plan = kind === 'planned' && id ? D.planned.find((x) => x.id === id) : undefined
  const trip = kind === 'event' && id ? D.trips.find((x) => x.id === id) : undefined
  const w: Who = who ?? 'A'
  const editing = !!(bill || debt || plan || trip)

  const [d, setD] = useState(() => {
    if (kind === 'income') {
      const x = L.H.incomes.find((i) => i.who === w) ?? { amt: 0, day: 1 }
      return { name: L.whoName[w], amt: x.amt ? String(x.amt) : '', extra: String(x.day), min: '', cat: '' }
    }
    if (bill) return { name: bill.name, amt: String(bill.amt), extra: String(bill.day), min: '', cat: bill.cat }
    if (debt) return { name: debt.name, amt: String(debt.balance), extra: String(debt.apr), min: String(debt.min), cat: '' }
    if (plan) return { name: plan.name, amt: String(plan.cost), extra: '', min: '', cat: '' }
    if (trip) return { name: trip.name, amt: String(trip.budget), extra: trip.when, min: '', cat: '' }
    return { name: '', amt: '', extra: '', min: '', cat: kind === 'bill' ? 'utilities' : '' }
  })
  const [err, setErr] = useState('')
  const set = (k: keyof typeof d, v: string) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }

  const title = kind === 'income' ? d.name + '’s ' + I.t : (editing ? 'Edit ' : 'New ') + I.t

  const save = () => {
    const amt = parse(d.amt), name = d.name.trim()
    if (!name) return setErr('Give it a name.')
    if (isNaN(amt)) return setErr('Add an amount.')
    const ex = parse(d.extra) || 0
    if (kind === 'income') act.setIncome(w, amt, clampDay(ex))
    else if (kind === 'bill') act.saveBill({ id: bill?.id, name, amt, day: clampDay(ex), cat: d.cat || 'utilities', sub: bill?.sub ?? false, paid: bill?.paid ?? {} })
    else if (kind === 'debt') {
      const mn = parse(d.min)
      act.saveDebt({ id: debt?.id, createdAt: debt?.createdAt ?? undefined, name, balance: amt, apr: ex, min: mn > 0 ? mn : Math.max(50, Math.round(amt * 0.02)) })
    } else if (kind === 'planned') act.savePlanned({ id: plan?.id, createdAt: plan?.createdAt ?? undefined, name, cost: amt, A: plan?.A ?? false, B: plan?.B ?? false })
    else act.saveTrip({ id: trip?.id, createdAt: trip?.createdAt ?? undefined, name, budget: amt, when: d.extra.trim(), spent: trip?.spent ?? 0 })
    close()
  }

  const del = !editing ? undefined : () => {
    if (bill) act.deleteBill(bill.id)
    else if (debt) act.deleteDebt(debt.id)
    else if (plan) act.deletePlanned(plan.id)
    else if (trip) act.deleteTrip(trip.id)
    close()
  }

  const amtField = <TextField label={I.al + ' (' + L.cur + ')'} decimal value={d.amt} onChange={(v) => set('amt', v)} />
  const extraField = I.el ? <TextField label={I.el} decimal={!I.text} value={d.extra} onChange={(v) => set('extra', v)} /> : null

  return (
    <PanelFrame title={title} err={err} onSave={save} onDelete={del}>
      <div style={css('display:flex;flex-direction:column;gap:14px')}>
        {kind !== 'income' && <TextField label="Name" value={d.name} onChange={(v) => set('name', v)} />}
        {amtField}
        {kind === 'debt' ? (
          <Pair>
            {extraField}
            <TextField label={'Minimum each month (' + L.cur + ')'} decimal placeholder={L.num(Math.max(50, Math.round((parse(d.amt) || 0) * 0.02)))} value={d.min} onChange={(v) => set('min', v)} />
          </Pair>
        ) : extraField}
        {kind === 'bill' && (
          <ChipGroup label="Category" chips={L.cats.map((c) => ({ key: c.id, label: c.name, on: d.cat === c.id, pick: () => set('cat', c.id) }))} />
        )}
      </div>
    </PanelFrame>
  )
}
