// One category's monthly limit: set it, move money in from another category,
// use the 3-month average; custom categories can be renamed or deleted.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { addM, dLab, isoD, mLabel } from '../lib/dates'
import { inputStyle, PanelFrame } from './PanelFrame'
import { useUI } from '../shell/ui'
import { BigField, ChipGroup, Pill, TextField, parse } from './parts'

export function BudgetPanel({ L, cat }: { L: Ledger; cat: string }) {
  const { act } = useStore()
  const { close, view, setView } = useUI()
  const row = L.rows.find((r) => r.id === cat)
  const custom = !!row?.custom
  const [d, setD] = useState(() => {
    // Average of the three full months before this one (real today).
    let tot = 0
    for (let k = 1; k <= 3; k++) tot += L.inM(addM(L.curYm, -k)).filter((t) => t.cat === cat && t.type === 'exp').reduce((a, t) => a + t.amt, 0)
    return { name: custom ? row!.name : '', limit: String(L.H.budgets[cat] || 0), from: '', move: '', avg: Math.round(tot / 3 / 10) * 10 }
  })
  const [err, setErr] = useState('')
  const set = (k: 'name' | 'limit' | 'from' | 'move', v: string) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }
  const f = L.f

  const save = () => {
    const nm = d.name.trim()
    if (custom && nm && nm.toLowerCase() !== row!.name.toLowerCase() && L.cats.some((c) => c.id !== cat && c.name.toLowerCase() === nm.toLowerCase()))
      return setErr('You already have a category with that name.')
    const limit = Math.max(0, parse(d.limit) || 0)
    act.setBudget(cat, limit)
    let mv = parse(d.move) || 0
    if (d.from && mv > 0) {
      mv = Math.min(mv, L.H.budgets[d.from] || 0)
      if (mv > 0) act.moveBudget(d.from, cat, mv)
    }
    if (custom && nm && nm !== row!.name) act.renameCategory(cat, nm)
    close()
  }
  const del = () => {
    act.deleteCategory(cat)
    if (view.fCat === cat) setView({ fCat: 'all' })
    close()
  }

  const from = L.rows.filter((r) => r.id !== cat && r.left > 0).sort((a, b) => b.left - a.left).slice(0, 6)
  const latest = L.exp.filter((t) => t.cat === cat).sort(L.desc).slice(0, 4)

  return (
    <PanelFrame title={row?.name ?? L.catOf(cat).name} err={err} onSave={save} onDelete={custom ? del : undefined}>
      <div style={css('display:flex;flex-direction:column;gap:16px')}>
        <div style={css('font-size:14.5px')}>Spent {f(L.spent[cat] || 0)} so far in {mLabel(L.ym)}.</div>
        {custom && <TextField label="Name" value={d.name} onChange={(v) => set('name', v)} />}
        <BigField label={'Monthly limit (' + L.cur + ')'} value={d.limit} onChange={(v) => set('limit', v)} />
        <Pill onClick={() => set('limit', String(d.avg || 0))}>Use 3-month average · {f(d.avg || 0)}</Pill>
        {latest.length > 0 && (
          <div>
            <div style={css('font-size:13px;color:var(--mute);margin-bottom:2px')}>Latest in this category</div>
            {latest.map((t) => (
              <div key={t.id} style={css('display:flex;gap:12px;padding:10px 0;border-bottom:1px solid var(--line)')}>
                <span style={css('font-size:13px;color:var(--mute);width:50px;flex:none;padding-top:2px')}>{dLab(isoD(t.date)).slice(4)}</span>
                <span style={css('flex:1;min-width:0')}>{t.name}</span>
                <span style={css('font-weight:500')}>{f(t.amt)}</span>
              </div>
            ))}
          </div>
        )}
        <div>
          <ChipGroup label="Or move money in from" chips={from.map((r) => ({ key: r.id, label: r.name + ' · ' + f(r.left), on: d.from === r.id, pick: () => set('from', d.from === r.id ? '' : r.id) }))} />
          <input className="h-focus-ink" inputMode="decimal" placeholder="Amount to move" value={d.move} onChange={(e) => set('move', e.target.value)} style={{ ...inputStyle, marginTop: 10 }} />
        </div>
      </div>
    </PanelFrame>
  )
}
