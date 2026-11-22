import type { Ledger } from '../data/ledger'
import { useUI } from '../shell/ui'
import { AcctPanel } from './AcctPanel'
import { BudgetPanel } from './BudgetPanel'
import { CatPanel } from './CatPanel'
import { ContribPanel } from './ContribPanel'
import { ItemPanel } from './ItemPanel'
import { PotPanel } from './PotPanel'
import { SettingsPanel } from './SettingsPanel'
import { TxPanel } from './TxPanel'

/** Shows whichever side panel is open. Each kind lives in its own file. */
export function PanelHost({ L }: { L: Ledger }) {
  const { panel: p } = useUI()
  if (!p) return null
  switch (p.kind) {
    case 'tx': return <TxPanel key={'tx' + (p.tx?.id ?? '')} L={L} tx={p.tx} pre={p.pre} />
    case 'budget': return <BudgetPanel key={'b' + p.cat} L={L} cat={p.cat} />
    case 'cat': return <CatPanel L={L} />
    case 'contrib': return <ContribPanel key={'c' + p.trip.id} L={L} trip={p.trip} />
    case 'item': return <ItemPanel key={p.item + (p.id ?? '') + (p.who ?? '')} L={L} kind={p.item} who={p.who} id={p.id} />
    case 'pot': return <PotPanel key={'p' + (p.goal?.id ?? '')} L={L} goal={p.goal} />
    case 'acct': return <AcctPanel key={'a' + (p.acct?.id ?? '')} L={L} acct={p.acct} />
    case 'settings': return <SettingsPanel L={L} />
  }
}
