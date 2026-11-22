// Entry rows everywhere (Activity, Today, account ledgers, loan payments) open the entry
// on click, show a delete button on hover, and have Edit / Delete on right-click.
// Deleting shows an Undo toast that puts the entry back exactly as it was.
import type { CSSProperties, MouseEvent, ReactNode } from 'react'
import { useStore } from '../data/store'
import type { Tx } from '../data/types'
import { css, sx } from '../lib/css'
import { Icon, ICON } from './icons'
import { useUI, type Panel } from './ui'

export function useEntry() {
  const ui = useUI()
  const { act } = useStore()
  const del = (t: Tx) => { act.deleteTx(t); ui.toast('Deleted ' + t.name, () => act.restoreTx(t)) }
  const edit = (t: Tx, back?: Panel) => ui.open({ kind: 'tx', tx: t, back })
  const menu = (e: MouseEvent, t: Tx, back?: Panel) => {
    e.preventDefault()
    ui.menu({ x: e.clientX, y: e.clientY, items: [{ label: 'Edit', run: () => edit(t, back) }, { label: 'Delete', bad: true, run: () => del(t) }] })
  }
  return { del, edit, menu }
}

const ROW = css('display:flex;align-items:center;gap:12px;flex:1;min-width:0;background:none;border:none;font:inherit;color:inherit;cursor:pointer;text-align:left')

/** One entry row. `rowStyle` adds to the clickable part (padding, min-height). */
export function EntryRow({ t, back, rowStyle, children }: { t: Tx; back?: Panel; rowStyle?: CSSProperties; children: ReactNode }) {
  const { del, edit, menu } = useEntry()
  return (
    <div className="tx-row h-row" onContextMenu={(e) => menu(e, t, back)} style={css('display:flex;align-items:center;gap:2px;border-bottom:1px solid var(--line)')}>
      <button onClick={() => edit(t, back)} style={{ ...ROW, padding: '10px 0', ...rowStyle }}>{children}</button>
      <button className="tx-del" onClick={() => del(t)} aria-label={'Delete ' + t.name} title="Delete"
        style={sx('width:34px;height:34px;flex:none;border:none;border-radius:11px;background:transparent;color:var(--mute);display:grid;place-items:center;cursor:pointer;padding:0', {})}>
        <Icon d={ICON.trash} size={17} />
      </button>
    </div>
  )
}
