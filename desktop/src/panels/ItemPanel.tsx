// Pay, bills, planned purchases and trips: name, amount and one extra field.
// Loans have their own form (LoanForm.tsx).
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Who } from '../data/types'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'
import { ChipGroup, TextField, parse } from './parts'

type Kind = 'income' | 'bill' | 'planned' | 'event'

/** The design's ITEM table. */
const ITEM: Record<Kind, { t: string; al: string; el?: string; text?: boolean }> = {
  income: { t: 'pay', al: 'Monthly take-home pay', el: 'Payday (day of the month)' },
  bill: { t: 'bill', al: 'Amount each month', el: 'Day of the month it’s due' },
  planned: { t: 'planned purchase', al: 'Expected cost' },
  event: { t: 'trip or event', al: 'Total budget', el: 'When (e.g. Mar 2027)', text: true },
}

const clampDay = (v: number) => Math.min(31, Math.max(1, Math.round(v) || 1))

export function ItemPanel({ L, kind, who, id }: { L: Ledger; kind: Kind; who?: Who; id?: string }) {
  const { act } = useStore()
  const { close, open } = useUI()
  const I = ITEM[kind]
  const D = L.data
  const bill = kind === 'bill' && id ? D.bills.find((x) => x.id === id) : undefined
  const plan = kind === 'planned' && id ? D.planned.find((x) => x.id === id) : undefined
  const trip = kind === 'event' && id ? D.trips.find((x) => x.id === id) : undefined
  const w: Who = who ?? 'A'
  const editing = !!(bill || plan || trip)
  const loan = bill?.debtId ? D.debts.find((x) => x.id === bill.debtId) : undefined

  const [d, setD] = useState(() => {
    if (kind === 'income') {
      const x = L.H.incomes.find((i) => i.who === w) ?? { amt: 0, day: 1 }
      return { name: L.whoName[w], amt: x.amt ? String(x.amt) : '', extra: String(x.day), cat: '' }
    }
    if (bill) return { name: bill.name, amt: String(bill.amt), extra: String(bill.day), cat: bill.cat }
    if (plan) return { name: plan.name, amt: String(plan.cost), extra: '', cat: '' }
    if (trip) return { name: trip.name, amt: String(trip.budget), extra: trip.when, cat: '' }
    return { name: '', amt: '', extra: '', cat: kind === 'bill' ? L.catOr('utilities') : '' }
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
    else if (kind === 'bill') act.saveBill({ id: bill?.id, name, amt, day: clampDay(ex), cat: d.cat || L.catOr('utilities'), sub: bill?.sub ?? false, paid: bill?.paid ?? {}, debtId: bill?.debtId ?? undefined })
    else if (kind === 'planned') act.savePlanned({ id: plan?.id, createdAt: plan?.createdAt ?? undefined, name, cost: amt, A: plan?.A ?? false, B: plan?.B ?? false })
    else act.saveTrip({ id: trip?.id, createdAt: trip?.createdAt ?? undefined, name, budget: amt, when: d.extra.trim(), spent: trip?.spent ?? 0 })
    close()
  }

  const del = !editing ? undefined : () => {
    if (bill) act.deleteBill(bill.id)
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
        {extraField}
        {loan && (
          <div style={css('font-size:13.5px;color:var(--mute);text-wrap:pretty')}>
            Shows the installment of {loan.name}. Paying it here pays the loan; change the amount or day from the loan, on Debt.{' '}
            <button type="button" onClick={() => open({ kind: 'loan', id: loan.id })} style={css("border:none;background:none;padding:0;font:inherit;color:var(--ink);text-decoration:underline;cursor:pointer")}>Open the loan</button>
          </div>
        )}
        {kind === 'bill' && (
          <ChipGroup label="Category" chips={L.cats.map((c) => ({ key: c.id, label: c.name, on: d.cat === c.id, pick: () => set('cat', c.id) }))} />
        )}
      </div>
    </PanelFrame>
  )
}
