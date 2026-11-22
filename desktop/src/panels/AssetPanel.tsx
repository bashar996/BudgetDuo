// New / edit asset (home, car, gold, …): name, kind and what it's worth today.
// Design: Tandem Budget.dc.html, ITEM.asset and m.isAsset in the item panel.
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { AssetKind } from '../data/types'
import { ASSET_KINDS } from '../data/catalog'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'
import { ChipGroup, chips, TextField, parse } from './parts'

export function AssetPanel({ L, id }: { L: Ledger; id?: string }) {
  const { act } = useStore()
  const { close } = useUI()
  const old = id ? L.holdings.find((x) => x.id === id) : undefined
  const [d, setD] = useState(() => ({ name: old?.name ?? '', kind: (old?.kind ?? 'property') as AssetKind, amt: old ? String(old.value) : '' }))
  const [err, setErr] = useState('')
  const set = <K extends keyof typeof d>(k: K, v: (typeof d)[K]) => { setErr(''); setD((x) => ({ ...x, [k]: v })) }

  const save = () => {
    const name = d.name.trim(), value = parse(d.amt)
    if (!name) return setErr('Give it a name.')
    if (isNaN(value)) return setErr('Add an amount.')
    act.saveAsset({ id: old?.id, createdAt: old?.createdAt ?? undefined, name, kind: d.kind, value })
    close()
  }
  const del = old ? () => { act.deleteAsset(old.id); close() } : undefined

  return (
    <PanelFrame title={old ? 'Edit asset' : 'New asset'} err={err} onSave={save} onDelete={del}>
      <div style={css('display:flex;flex-direction:column;gap:14px')}>
        <TextField label="Name" value={d.name} onChange={(v) => set('name', v)} />
        <ChipGroup label="Kind" chips={chips<AssetKind>(ASSET_KINDS, d.kind, (k) => set('kind', k))} />
        <TextField label={'What it’s worth today (' + L.cur + ')'} decimal value={d.amt} onChange={(v) => set('amt', v)} />
      </div>
    </PanelFrame>
  )
}
