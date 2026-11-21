import type { Ledger } from '../data/ledger'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'

/** Shows whichever side panel is open. Each kind lives in its own file. */
export function PanelHost({ L }: { L: Ledger }) {
  const { panel } = useUI()
  if (!panel) return null
  // TODO(panels): tx, budget, cat, contrib, item, pot, acct, settings
  return (
    <PanelFrame key={JSON.stringify(panel).slice(0, 80)} title={panel.kind} onSave={() => {}}>
      <div>{L.cur}</div>
    </PanelFrame>
  )
}
