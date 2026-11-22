// Log spending on a trip or event (a Travel expense from the main account).
import { useState } from 'react'
import type { Ledger } from '../data/ledger'
import type { Trip } from '../data/types'
import { useStore } from '../data/store'
import { css } from '../lib/css'
import { useUI } from '../shell/ui'
import { PanelFrame } from './PanelFrame'
import { Pill, parse } from './parts'

export function ContribPanel({ L, trip }: { L: Ledger; trip: Trip }) {
  const { act } = useStore()
  const { close } = useUI()
  const [amt, setAmt] = useState('')
  const [err, setErr] = useState('')

  const save = () => {
    const v = parse(amt)
    if (!(v > 0)) return setErr('Add an amount first.')
    act.spendOnTrip(trip, v, L.mainAcct)
    close()
  }

  return (
    <PanelFrame title={'Spend on ' + trip.name} amount={{ value: amt, onChange: (v) => { setErr(''); setAmt(v) }, currency: L.cur }} err={err} onSave={save}>
      <div style={css('display:flex;flex-wrap:wrap;gap:6px')}>
        {[100, 250, 500, 1000].map((v) => (
          <Pill key={v} onClick={() => { setErr(''); setAmt(String((parse(amt) || 0) + v)) }}>+{L.num(v)}</Pill>
        ))}
      </div>
    </PanelFrame>
  )
}
