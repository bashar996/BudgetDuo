// New / edit savings pot: name, target, auto-save amount, deadline, which savings account.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Goal } from '../data/types'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { useUI } from '../shell/ui'
import { inputStyle, Field, PanelFrame } from './PanelFrame'
import { ChipGroup, Pair, TextField, parse } from './parts'

export function PotPanel({ L, goal }: { L: Ledger; goal?: Goal }) {
  const { act } = useStore()
  const { close } = useUI()
  const old = goal ? L.data.goals.find((g) => g.id === goal.id) : undefined
  const savers = L.accounts.filter((a) => a.type === 'save')
  const [d, setD] = useState(() => old
    ? { name: old.name, amt: String(old.target), extra: String(old.monthly), due: old.due ?? '', acct: old.acct }
    : { name: '', amt: '', extra: '', due: '', acct: savers[0]?.id ?? '' })
  const [err, setErr] = useState('')
  const set = (k: keyof typeof d, v: string) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }

  const save = () => {
    const name = d.name.trim(), target = parse(d.amt)
    if (!name) return setErr('Give it a name.')
    if (!(target > 0)) return setErr('Add a target amount.')
    if (!d.acct) return setErr('Add a savings account first, so the pot has a home.')
    const monthly = parse(d.extra) || 0
    if (old) act.saveGoal({ ...old, name, target, monthly, due: d.due || '', acct: d.acct })
    else act.saveGoal({ name, target, monthly, due: d.due || '', acct: d.acct, startSaved: 0, auto: monthly > 0 })
    close()
  }

  return (
    <PanelFrame title={old ? 'Edit pot' : 'New savings pot'} err={err} onSave={save}
      onDelete={old ? () => { act.deleteGoal(old.id); close() } : undefined}>
      <div style={css('display:flex;flex-direction:column;gap:14px')}>
        <TextField label="Name" value={d.name} onChange={(v) => set('name', v)} />
        <TextField label={'Target amount (' + L.cur + ')'} decimal value={d.amt} onChange={(v) => set('amt', v)} />
        <Pair>
          <TextField label="Auto-save each payday" decimal value={d.extra} onChange={(v) => set('extra', v)} />
          <Field label="Needed by (optional)">
            <input type="month" value={d.due} onChange={(e) => set('due', e.target.value)} style={inputStyle} />
          </Field>
        </Pair>
        <ChipGroup label="Kept in" chips={savers.map((a) => ({ key: a.id, label: a.name, on: d.acct === a.id, pick: () => set('acct', a.id) }))} />
      </div>
    </PanelFrame>
  )
}
