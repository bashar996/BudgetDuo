// New budget category (Needs or Wants) with a monthly limit.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'
import { BigField, ChipGroup, chips, TextField, parse } from './parts'

export function CatPanel({ L }: { L: Ledger }) {
  const { act } = useStore()
  const { close } = useUI()
  const [name, setName] = useState('')
  const [g, setG] = useState<'needs' | 'wants'>('needs')
  const [limit, setLimit] = useState('')
  const [err, setErr] = useState('')

  const save = () => {
    const nm = name.trim(), low = nm.toLowerCase()
    if (!nm) return setErr('Give it a name.')
    if (L.cats.some((c) => c.name.toLowerCase() === low)) return setErr('You already have a category with that name.')
    act.addCategory(nm, g, Math.max(0, parse(limit) || 0))
    close()
  }

  return (
    <PanelFrame title="New category" err={err} onSave={save}>
      <div style={css('display:flex;flex-direction:column;gap:16px')}>
        <TextField label="Name" placeholder="e.g. Pets" value={name} onChange={(v) => { setErr(''); setName(v) }} />
        <ChipGroup grow label="Group" chips={chips<'needs' | 'wants'>([['needs', 'Needs'], ['wants', 'Wants']], g, (k) => { setErr(''); setG(k) })} />
        <BigField label={'Monthly limit (' + L.cur + ')'} placeholder="0" value={limit} onChange={(v) => { setErr(''); setLimit(v) }} />
      </div>
    </PanelFrame>
  )
}
