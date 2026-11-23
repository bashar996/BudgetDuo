// Savings (lavender): pots, auto-save, round-ups, month-end sweep, recent pot moves,
// and a 12-month projection in the header.
// Design: Tandem Budget.dc.html, template `is.savings` and `sav` / potVM in renderVals().
import type { HeroBar, TabDef } from '../shell/ui'
import { useUI } from '../shell/ui'
import { useStore } from '../data/store'
import type { Ledger } from '../data/ledger'
import { css, sx } from '../lib/css'
import { addM, dLab, isoD, mBetween, MN, mLabel } from '../lib/dates'
import { pc, sum } from '../lib/money'

const LAV = 'var(--accBase)', CRM = '#fbf9ef'
const H22 = css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")
const CHIP = "height:44px;padding:0 15px;border-radius:22px;font:500 13.5px 'Geist',sans-serif;cursor:pointer"

type Pot = Ledger['goals'][number]

/** Pot totals month by month for a year: interest from the pot's account, plus auto-save. */
function project(L: Ledger) {
  const pv = L.goals.map((g) => ({ s: g.saved, g }))
  const proj = [sum(L.goals, (g) => g.saved)]
  let interest = 0
  for (let i = 1; i <= 12; i++) {
    pv.forEach((p) => {
      const it = (p.s * (L.acctBy[p.g.acct]?.apy || 0)) / 1200
      interest += it; p.s += it
      if (p.g.auto && p.s < p.g.target) p.s += Math.min(p.g.monthly, p.g.target - p.s)
    })
    proj.push(sum(pv, (p) => p.s))
  }
  return { proj, interest }
}

const potMoves = (L: Ledger) => L.data.tx.filter((t) => t.type === 'xfer' && t.pot).sort(L.desc)

function stats(L: Ledger): [string, string][] {
  const { f, goals } = L
  const { proj } = project(L)
  const autoPots = goals.filter((g) => g.auto)
  const essentials = sum(L.rows.filter((r) => r.g === 'needs'), (r) => r.limit), ef = goals[0]
  const savTotal = sum(L.accounts.filter((a) => a.type === 'save'), (a) => a.balance), inPots = sum(goals, (g) => g.saved)
  return [
    ['Moves each payday', f(sum(autoPots, (g) => g.monthly))],
    ['Emergency cover', ef && essentials ? (ef.saved / essentials).toFixed(1) + ' months' : '—'],
    ['Not in a pot yet', f(Math.max(0, savTotal - inPots))],
    ['In 12 months', f(Math.round(proj[12]))],
  ]
}

function Toggle({ on, label, onClick }: { on: boolean; label: string; onClick(): void }) {
  return (
    <button onClick={onClick} aria-label={label} aria-pressed={on} style={css('width:48px;height:44px;padding:8px 0;border:none;background:none;cursor:pointer;flex:none')}>
      <span style={sx('display:block;position:relative;width:48px;height:28px;border-radius:14px;transition:background .2s', { background: on ? 'var(--ink)' : 'var(--chip)' })}>
        <span style={sx('position:absolute;top:3px;width:22px;height:22px;border-radius:50%;background:#ffffff;transition:left .2s', { left: on ? 23 : 3 })} />
      </span>
    </button>
  )
}

function PotCard({ L, g }: { L: Ledger; g: Pot }) {
  const ui = useUI()
  const { act } = useStore()
  const { f, calYm: curYm } = L
  const r = g.target ? g.saved / g.target : 0, rem = Math.max(0, g.target - g.saved)
  const n = g.monthly > 0 ? Math.ceil(rem / g.monthly) : 0, a = L.acctBy[g.acct]
  const left = g.due ? Math.max(1, mBetween(curYm, g.due)) : 0, need = left ? Math.ceil(rem / left / 10) * 10 : 0
  const done = rem <= 0, behind = !done && left > 0 && need > g.monthly
  const eta = done ? 'reached' : n ? 'there by ' + mLabel(addM(curYm, n), true) : 'no monthly amount yet'
  const where = (a?.name || 'No account yet') + (a?.apy ? ' · earning ' + a.apy + '% a year' : '')
  const status = done ? 'Reached' : behind ? 'Needs ' + f(need - g.monthly) + ' more a month' : g.due ? 'On track' : n ? 'Steady' : 'Paused'
  const statusColor = done ? 'var(--good)' : behind ? 'var(--warn)' : 'var(--ink)'
  const edit = () => ui.open({ kind: 'pot', goal: L.data.goals.find((x) => x.id === g.id) })
  return (
    <div style={css('background:var(--card);border-radius:26px;padding:20px;display:flex;flex-direction:column;gap:12px')}>
      <div style={css('display:flex;justify-content:space-between;gap:10px;align-items:flex-start')}>
        <div style={css('min-width:0')}>
          <button onClick={edit} style={css("background:none;border:none;padding:0;font:500 19px 'Geist',sans-serif;color:var(--ink);cursor:pointer;text-align:left")}>{g.name}</button>
          <div style={css('font-size:12.5px;color:var(--mute)')}>{where}</div>
        </div>
        <div style={css('flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:8px')}>
          <button onClick={edit} style={css("height:44px;padding:0 16px;border-radius:22px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);font:500 13.5px 'Geist',sans-serif;cursor:pointer")}>Edit</button>
          <span style={css('font-size:32px;letter-spacing:-.03em;line-height:1')}>{Math.round(r * 100) + '%'}</span>
        </div>
      </div>
      <div style={css('height:5px;border-radius:3px;background:var(--track)')}><div style={sx('height:100%;background:#ffffff;border-radius:3px;transition:width .4s', { width: pc(r) })} /></div>
      <div style={css('display:flex;justify-content:space-between;gap:10px;font-size:13.5px')}>
        <span>{f(g.saved)} of {f(g.target)}</span>
        <span style={sx('font-weight:500;text-align:right', { color: statusColor })}>{status}</span>
      </div>
      <div style={css('font-size:12.5px;color:var(--mute);margin-top:-6px')}>{(g.due ? 'Needed by ' + mLabel(g.due, true) : 'No deadline') + ' · ' + eta}</div>
      <div style={css('display:flex;align-items:center;gap:10px;border-top:1px solid var(--line);padding-top:6px')}>
        <Toggle on={!!g.auto} label="Auto-save" onClick={() => act.setGoalAuto(g.id, !g.auto)} />
        <span style={css('font-size:13.5px')}>{g.auto ? 'Auto-save on · ' + f(g.monthly) + ' each payday' : 'Auto-save off'}</span>
      </div>
      <div style={css('display:flex;gap:8px')}>
        <button onClick={() => ui.open({ kind: 'tx', pre: { type: 'xfer', to: g.acct, pot: g.id, potDir: 'in', name: 'Deposit · ' + g.name } })} style={css("flex:1;font:500 15px 'Geist',sans-serif;height:46px;border-radius:16px;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer")}>Deposit</button>
        <button onClick={() => ui.open({ kind: 'tx', pre: { type: 'xfer', acct: g.acct, to: L.mainAcct, pot: g.id, potDir: 'out', name: 'Withdrawal · ' + g.name } })} style={css("flex:1;font:500 15px 'Geist',sans-serif;height:46px;border-radius:16px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")}>Withdraw</button>
      </div>
    </div>
  )
}

function Body({ L }: { L: Ledger }) {
  const ui = useUI()
  const { act } = useStore()
  const { f, goals: pots, H } = L
  const autoPots = pots.filter((g) => g.auto), autoTot = sum(autoPots, (g) => g.monthly)
  const sp = L.roundUpPot, ru = L.roundUps, ruOn = !!H.roundUps, swOn = !!H.sweep
  const history = potMoves(L).slice(0, 7)
  const rawPot = sp && L.data.goals.find((x) => x.id === sp.id)

  return (
    <div style={css('display:flex;flex-direction:column;gap:30px')}>
      <section style={css('display:flex;flex-direction:column;gap:12px')}>
        <div style={css('display:flex;justify-content:space-between;align-items:center;gap:10px')}>
          <span style={H22}>Pots</span>
          <button onClick={() => ui.open({ kind: 'pot' })} style={css("font:500 14px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;white-space:nowrap;flex:none;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer")}>+ New pot</button>
        </div>
        <div style={css('display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,280px),1fr));gap:12px')}>
          {pots.map((g) => <PotCard key={g.id} L={L} g={g} />)}
          {!pots.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute)')}>No pots yet. Create one for each thing you’re saving toward.</div>}
        </div>
      </section>

      <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:30px 40px;align-items:start')}>
        <section>
          <span style={H22}>Ways you save</span>
          <div style={css('display:flex;gap:12px;align-items:flex-start;padding:14px 0;border-bottom:1px solid var(--line)')}>
            <span style={css('width:48px;height:28px;flex:none;border-radius:14px;background:var(--ink);color:var(--bg);display:grid;place-items:center;font-size:11px;font-weight:600')}>AUTO</span>
            <div style={css('flex:1')}>
              <div style={css('font-size:16px;font-weight:500')}>Payday auto-save</div>
              <div style={css('font-size:13.5px;color:var(--mute);text-wrap:pretty')}>{autoTot > 0
                ? 'Right after payday, ' + f(autoTot) + ' moves from ' + L.aName(L.mainAcct) + ' into ' + autoPots.length + ' pots. Switch any pot on or off above.'
                : 'No pot is on auto-save yet. Switch one on above and it fills itself.'}</div>
            </div>
          </div>
          <div style={css('display:flex;gap:12px;align-items:flex-start;padding:6px 0 14px;border-bottom:1px solid var(--line)')}>
            <Toggle on={ruOn} label="Round-ups" onClick={() => act.updateHousehold({ roundUps: !ruOn })} />
            <div style={css('flex:1;display:flex;flex-direction:column;gap:10px;padding-top:8px')}>
              <div>
                <div style={css('font-size:16px;font-weight:500')}>Round-ups</div>
                <div style={css('font-size:13.5px;color:var(--mute);text-wrap:pretty')}>{ruOn
                  ? (ru > 0 ? f(ru) + ' of spare change from ' + mLabel(L.curYm) + ' is ready to move.' : 'All round-ups for ' + mLabel(L.curYm) + ' are already moved.')
                  : 'Rounds each purchase up to the next 10 and saves the difference.'}</div>
              </div>
              {ruOn && ru > 0 && rawPot && (
                <button onClick={() => act.moveRoundUps(ru, rawPot, L.mainAcct, L.curYm)} style={css("align-self:flex-start;font:500 14px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer")}>{'Move ' + f(ru) + ' to ' + sp!.name}</button>
              )}
            </div>
          </div>
          <div style={css('display:flex;gap:12px;align-items:flex-start;padding:6px 0 14px;border-bottom:1px solid var(--line)')}>
            <Toggle on={swOn} label="Month-end sweep" onClick={() => act.updateHousehold({ sweep: !swOn })} />
            <div style={css('flex:1;padding-top:8px')}>
              <div style={css('font-size:16px;font-weight:500')}>Month-end sweep</div>
              <div style={css('font-size:13.5px;color:var(--mute);text-wrap:pretty')}>{swOn
                ? 'On the last day of the month, whatever is left in safe-to-spend moves to ' + (sp ? sp.name : 'a pot') + '. Today that would be about ' + f(Math.max(0, Math.round(L.safe))) + '.'
                : 'Moves whatever is left in safe-to-spend into a pot on the last day of the month.'}</div>
            </div>
          </div>
          <div style={css('padding-top:14px')}>
            <div style={css('font-size:13px;color:var(--mute);margin-bottom:8px')}>Extra money goes to</div>
            <div style={css('display:flex;flex-wrap:wrap;gap:6px')}>
              {pots.map((g) => {
                const on = !!sp && sp.id === g.id
                return (
                  <button key={g.id} onClick={() => act.setRoundUpPot(g.id)} aria-pressed={on}
                    style={sx(CHIP, { border: '1px solid ' + (on ? 'var(--ink)' : 'var(--chip)'), background: on ? 'var(--ink)' : 'transparent', color: on ? 'var(--bg)' : 'var(--ink)' })}>{g.name}</button>
                )
              })}
            </div>
          </div>
        </section>
        <section>
          <span style={H22}>Recent moves</span>
          {history.map((t) => (
            <button key={t.id} onClick={() => ui.open({ kind: 'tx', tx: t })} style={css('display:flex;align-items:center;gap:12px;width:100%;min-height:56px;padding:8px 0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')}>
              <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                <span style={css('font-size:16px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{t.name}</span>
                <span style={css('font-size:13px;color:var(--mute);overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{dLab(isoD(t.date)).slice(4) + ' · ' + L.aName(t.acct) + ' → ' + L.aName(t.to)}</span>
              </span>
              <span style={css('font-size:15px;font-weight:500;white-space:nowrap')}>{f(t.amt)}</span>
            </button>
          ))}
          {!history.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute)')}>Deposits and withdrawals will show here.</div>}
        </section>
      </div>
    </div>
  )
}

export const savingsTab: TabDef = {
  id: 'savings',
  stage: 'lav',
  kicker: () => 'Pots, auto-save and growth',
  hero: (L) => {
    const { f, ym } = L
    const { proj } = project(L)
    const netM = sum(potMoves(L).filter((t) => t.date >= L.period.from && t.date <= L.period.to), (t) => (t.potDir === 'out' ? -t.amt : t.amt))
    const m0 = L.today.getMonth()
    const bars: HeroBar[] = proj.map((v, i) => ({
      h: pc(Math.max(0.04, v / (proj[12] || 1))),
      bg: i === 0 ? LAV : CRM,
      label: MN[(m0 + i) % 12].slice(0, 1),
      tag: i === 12 ? f(Math.round(v)) : '',
      title: mLabel(addM(L.calYm, i), true) + ' · ' + f(Math.round(v)),
    }))
    return {
      label: 'Saved across your pots',
      cur: true,
      num: L.num(Math.round(proj[0])),
      fg: '#ffffff',
      sub: (netM >= 0 ? '+' : '') + f(netM) + ' moved in during ' + mLabel(ym) + '.',
      stats: stats(L),
      bars,
    }
  },
  Body,
}
