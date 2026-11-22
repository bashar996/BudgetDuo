// One category: rename it, move it between Needs and Wants, set its monthly limit,
// move money in from another category, use the 3-month average, or delete it
// (two steps, with a choice of where its entries and bills go). Pocket money only
// has the limit controls.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { addM, dLab, isoD, mLabel } from '../lib/dates'
import { inputStyle, PanelFrame } from './PanelFrame'
import { useUI } from '../shell/ui'
import { BigField, Chip, ChipGroup, chips, Pill, TextField, parse, type ChipOpt } from './parts'

export function BudgetPanel({ L, cat }: { L: Ledger; cat: string }) {
  const { act } = useStore()
  const { close, view, setView } = useUI()
  const row = L.rows.find((r) => r.id === cat)
  // Every category can be renamed, moved and deleted except the two pocket-money ones.
  const editable = !!row && row.g !== 'personal'
  const [d, setD] = useState(() => {
    // Average of the three full months before this one (real today).
    let tot = 0
    for (let k = 1; k <= 3; k++) tot += L.inM(addM(L.curYm, -k)).filter((t) => t.cat === cat && t.type === 'exp').reduce((a, t) => a + t.amt, 0)
    return { name: row?.name ?? '', g: (row?.g === 'wants' ? 'wants' : 'needs') as 'needs' | 'wants', limit: String(L.H.budgets[cat] || 0), from: '', move: '', avg: Math.round(tot / 3 / 10) * 10, delStep: false, moveTo: '' }
  })
  const [err, setErr] = useState('')
  const set = <K extends keyof typeof d>(k: K, v: (typeof d)[K]) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }
  const f = L.f

  const save = () => {
    const nm = d.name.trim()
    if (editable) {
      if (!nm) return setErr('Give it a name.')
      if (L.cats.some((c) => c.id !== cat && c.name.toLowerCase() === nm.toLowerCase())) return setErr('You already have a category with that name.')
    }
    const limit = Math.max(0, parse(d.limit) || 0)
    act.setBudget(cat, limit)
    let mv = parse(d.move) || 0
    if (d.from && mv > 0) {
      mv = Math.min(mv, L.H.budgets[d.from] || 0)
      if (mv > 0) act.moveBudget(d.from, cat, mv)
    }
    if (editable && (nm !== row!.name || d.g !== row!.g)) act.updateCategory(cat, { name: nm, g: d.g })
    close()
  }

  // Delete: first tap shows the card, second tap ("Confirm delete") does it.
  const nTx = L.data.tx.filter((t) => t.cat === cat).length, nBills = L.data.bills.filter((b) => b.cat === cat).length
  const used = nTx + nBills > 0
  const delInfo = used
    ? (nTx ? nTx + (nTx === 1 ? ' entry' : ' entries') : '') + (nTx && nBills ? ' and ' : '') + (nBills ? nBills + (nBills === 1 ? ' bill' : ' bills') : '')
      + (nTx + nBills === 1 ? ' uses' : ' use') + ' this category. Where should ' + (nTx + nBills === 1 ? 'it' : 'they') + ' go?'
    : 'Nothing uses this category yet, so it can go straight away.'
  const del = () => {
    if (!d.delStep) { setErr(''); setD((x) => ({ ...x, delStep: true, moveTo: '' })); return }
    if (used && !d.moveTo) return setErr('Choose where its entries should go.')
    act.deleteCategory(cat, d.moveTo && d.moveTo !== 'none' ? d.moveTo : null)
    if (view.fCat === cat) setView({ fCat: 'all' })
    close()
  }
  const moveTo: ChipOpt[] = L.cats.filter((c) => c.id !== cat).map((c) => ({ key: c.id, label: c.name, on: d.moveTo === c.id, pick: () => set('moveTo', c.id) }))
    .concat({ key: 'none', label: 'Leave uncategorised', on: d.moveTo === 'none', pick: () => set('moveTo', 'none') })

  const from = L.rows.filter((r) => r.id !== cat && r.left > 0).sort((a, b) => b.left - a.left).slice(0, 6)
  const latest = L.exp.filter((t) => t.cat === cat).sort(L.desc).slice(0, 4)

  return (
    <PanelFrame title={row?.name ?? L.catOf(cat).name} err={err} onSave={save} onDelete={editable ? del : undefined} deleteLabel={d.delStep ? 'Confirm delete' : 'Delete'}>
      <div style={css('display:flex;flex-direction:column;gap:16px')}>
        {d.delStep && (
          <div style={css('background:var(--card);border-radius:20px;padding:16px;display:flex;flex-direction:column;gap:12px')}>
            <div style={css('font-size:17px;font-weight:500;letter-spacing:-.01em')}>Delete this category?</div>
            <div style={css('font-size:14px;text-wrap:pretty')}>{delInfo}</div>
            {used && (
              <div style={css('display:flex;flex-direction:column;gap:10px')}>
                <div style={css('display:flex;flex-wrap:wrap;gap:6px')}>{moveTo.map((c) => <Chip key={c.key} c={c} />)}</div>
                <div style={css('font-size:12.5px;color:var(--mute);text-wrap:pretty')}>Uncategorised entries stay in Activity but stop counting toward any budget.</div>
              </div>
            )}
            <Pill onClick={() => { setErr(''); setD((x) => ({ ...x, delStep: false, moveTo: '' })) }}>Keep category</Pill>
          </div>
        )}
        <div style={css('font-size:14.5px')}>Spent {f(L.spent[cat] || 0)} so far in {mLabel(L.ym)}.</div>
        {editable && <TextField label="Name" value={d.name} onChange={(v) => set('name', v)} />}
        {editable && <ChipGroup grow label="Group" chips={chips<'needs' | 'wants'>([['needs', 'Needs'], ['wants', 'Wants']], d.g, (k) => set('g', k))} />}
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
