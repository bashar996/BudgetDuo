// Accounts (lavender): total across accounts, account tiles, the picked account's
// ledger and 30-day balance, and loans. Net worth lives in tabs/worth.tsx.
// Design: Tandem Budget.dc.html, template `is.accounts` and `acc` in renderVals().
import type { TabDef, HeroBar } from '../shell/ui'
import { useUI } from '../shell/ui'
import type { Ledger } from '../data/ledger'
import type { Tx } from '../data/types'
import { ACCOUNT_TYPES } from '../data/catalog'
import { css, sx } from '../lib/css'
import { addDays, addM, dim, dLab, isoD, isoOf, MN, mLabel, pad } from '../lib/dates'
import { pc, sum } from '../lib/money'

const LAV = 'var(--accBase)', CRM = '#fbf9ef'
const tOf = (type: string) => ACCOUNT_TYPES[type] ?? ACCOUNT_TYPES.current

const flow = (t: Tx, id: string) =>
  t.type === 'inc' ? (t.acct === id ? t.amt : 0) : t.type === 'exp' ? (t.acct === id ? -t.amt : 0) : (t.to === id ? t.amt : 0) - (t.acct === id ? t.amt : 0)

const H22 = css("font:500 22px 'Geist',sans-serif;letter-spacing:-.01em")
const BTN_LINE = css("font:500 14px 'Geist',sans-serif;padding:0 16px;height:46px;border-radius:16px;border:1px solid var(--chip);background:transparent;color:var(--ink);cursor:pointer")

function Body({ L }: { L: Ledger }) {
  const ui = useUI()
  const { f, accounts } = L
  const sel = (ui.view.selAcct && L.acctBy[ui.view.selAcct]) || accounts[0]

  return (
    <div style={css('display:flex;flex-direction:column;gap:26px')}>
      <section style={css('display:flex;flex-direction:column;gap:12px')}>
        <div style={css('display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap')}>
          <span style={H22}>Your accounts</span>
          <span style={css('display:flex;gap:8px')}>
            <button onClick={() => ui.open({ kind: 'tx', pre: { type: 'xfer', acct: sel ? sel.id : '', to: '' } })} style={css("font:500 14px 'Geist',sans-serif;padding:0 16px;height:46px;border-radius:16px;border:1.5px solid var(--ink);background:transparent;color:var(--ink);cursor:pointer")}>Transfer</button>
            <button onClick={() => ui.open({ kind: 'acct' })} style={css("font:500 14px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;white-space:nowrap;flex:none;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer")}>+ New account</button>
          </span>
        </div>
        <div style={css('display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,210px),1fr));gap:10px')}>
          {accounts.map((a) => {
            const on = !!sel && sel.id === a.id
            const used = a.type === 'card' && a.limit ? Math.max(0, -a.balance) / a.limit : 0
            const meta = [a.bank, a.last4 ? '•• ' + a.last4 : '', L.whoName[a.who] || 'Joint'].filter(Boolean).join(' · ')
            const extra = a.type === 'card' ? (a.limit ? Math.round(used * 100) + '% of ' + f(a.limit) + ' limit used' : 'No limit set')
              : a.type === 'save' ? (a.apy ? a.apy + '% a year · ' : '') + L.goals.filter((g) => g.acct === a.id).length + ' pots'
              : a.type === 'invest' ? 'Balance updated by hand' : a.type === 'cash' ? 'Notes and coins' : 'Everyday spending'
            return (
              <button key={a.id} onClick={() => ui.setView({ selAcct: a.id })} aria-pressed={on}
                style={sx('display:flex;flex-direction:column;gap:4px;text-align:left;padding:18px;border:none;border-radius:24px;font:inherit;cursor:pointer;transition:background .2s', { background: on ? '#0b0b0c' : '#ffffff', color: on ? '#ffffff' : '#0b0b0c' })}>
                <span style={css('font-size:12.5px;opacity:.64')}>{tOf(a.type)[0]}</span>
                <span style={css('font-weight:500;font-size:16.5px')}>{a.name}</span>
                <span style={css('font-size:12.5px;opacity:.64')}>{meta}</span>
                <span style={sx("font:500 30px 'Geist',sans-serif;letter-spacing:-.03em;margin-top:14px", { color: a.balance < 0 ? (on ? '#ff8f85' : '#b3352b') : 'inherit' })}>{f(a.balance)}</span>
                {a.type === 'card' && !!a.limit && (
                  <span style={sx('display:block;height:5px;border-radius:3px', { background: on ? 'rgba(255,255,255,.28)' : '#0b0b0c' })}>
                    <span style={sx('display:block;height:100%;border-radius:3px', { width: pc(used), background: used > 0.5 ? '#ff8f85' : 'var(--accBase)' })} />
                  </span>
                )}
                <span style={css('font-size:12.5px;opacity:.64')}>{extra}</span>
              </button>
            )
          })}
          {!accounts.length && <div style={css('padding:8px 0;font-size:14px;color:var(--mute)')}>No accounts yet. Add your current account, cards, cash and savings.</div>}
        </div>
      </section>

      {sel && <Detail L={L} id={sel.id} />}

      {L.data.debts.length > 0 && (
        <section style={css('max-width:620px')}>
          <div style={css('display:flex;justify-content:space-between;align-items:baseline')}>
            <span style={H22}>Loans</span>
            <button onClick={() => ui.go('goals')} style={css("height:44px;border:none;background:none;color:var(--ink);font:500 14px 'Geist',sans-serif;cursor:pointer;padding:0")}>Payoff plan →</button>
          </div>
          {L.data.debts.map((x) => (
            <button key={x.id} onClick={() => ui.open({ kind: 'item', item: 'debt', id: x.id })} style={css('display:flex;align-items:center;gap:12px;width:100%;min-height:56px;padding:8px 0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')}>
              <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
                <span style={css('font-size:16px;font-weight:500')}>{x.name}</span>
                <span style={css('font-size:13px;color:var(--mute)')}>{x.apr + '% interest · ' + f(x.min) + '/mo'}</span>
              </span>
              <span style={css('font-size:15px;font-weight:500')}>{f(-x.balance)}</span>
            </button>
          ))}
        </section>
      )}
    </div>
  )
}

/** The black panel for the picked account. */
function Detail({ L, id }: { L: Ledger; id: string }) {
  const ui = useUI()
  const { f } = L
  const sel = L.acctBy[id]
  let run = sel.balance
  const led = L.data.tx.filter((t) => t.acct === id || t.to === id).sort(L.desc).map((t) => {
    const v = flow(t, id), after = run
    run -= v
    return { t, v, after }
  })
  const mLed = led.filter((x) => x.t.date.slice(0, 7) === L.ym)

  const dayBal: { v: number; title: string }[] = []
  let b = sel.balance, k = 0
  for (let i = 0; i < 30; i++) {
    const dt = addDays(L.today, -i), iso = isoOf(dt)
    dayBal.unshift({ v: b, title: dLab(dt) })
    while (k < led.length && led[k].t.date >= iso) { b -= led[k].v; k++ }
  }
  const mx = Math.max(1, ...dayBal.map((x) => Math.abs(x.v)))
  const inM = sum(mLed.filter((x) => x.v > 0), (x) => x.v), outM = sum(mLed.filter((x) => x.v < 0), (x) => -x.v)

  return (
    <section data-stage="dark" style={css('background:#0b0b0c;color:var(--ink);border-radius:28px;padding:clamp(20px,3vw,32px);display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr));gap:30px 44px;align-items:start')}>
      <div style={css('display:flex;flex-direction:column;gap:18px;min-width:0')}>
        <div>
          <div style={css('font-size:13.5px;color:var(--mute)')}>{tOf(sel.type)[0]} · {sel.name}</div>
          <div style={css("font:500 clamp(40px,5vw,60px)/1 'Geist',sans-serif;letter-spacing:-.04em;margin-top:6px")}>{f(sel.balance)}</div>
        </div>
        <div style={css('display:flex;gap:30px')}>
          <div><div style={css('font-size:12.5px;color:var(--mute)')}>In this month</div><div style={css("font:500 18px 'Geist',sans-serif;color:var(--acc)")}>{f(inM)}</div></div>
          <div><div style={css('font-size:12.5px;color:var(--mute)')}>Out this month</div><div style={css("font:500 18px 'Geist',sans-serif")}>{f(outM)}</div></div>
        </div>
        <div>
          <div style={css('font-size:12.5px;color:var(--mute)')}>Balance, last 30 days</div>
          <div style={css('display:flex;align-items:flex-end;gap:3px;height:96px;margin-top:10px')}>
            {dayBal.map((x, i) => (
              <div key={i} title={x.title + ' · ' + f(Math.round(x.v))} style={sx('flex:1;border-radius:4px 4px 2px 2px;min-height:3px', { height: pc(Math.max(0.03, Math.abs(x.v) / mx)), background: i === 29 ? 'var(--acc)' : 'var(--ink)' })} />
            ))}
          </div>
        </div>
        <div style={css('display:flex;flex-wrap:wrap;gap:8px')}>
          <button onClick={() => ui.open({ kind: 'tx', pre: { acct: id } })} style={css("font:500 14px 'Geist',sans-serif;padding:0 18px;height:46px;border-radius:16px;border:none;background:var(--btn);color:var(--btnInk);cursor:pointer")}>+ Entry</button>
          <button onClick={() => ui.open({ kind: 'tx', pre: { type: 'xfer', acct: id, to: '' } })} style={BTN_LINE}>Transfer out</button>
          <button onClick={() => ui.open({ kind: 'acct', acct: L.data.accounts.find((a) => a.id === id) })} style={BTN_LINE}>Edit</button>
        </div>
      </div>
      <div style={css('min-width:0')}>
        <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:12px;padding-bottom:4px')}>
          <span style={H22}>Ledger</span>
          <span style={css('font-size:13px;color:var(--mute)')}>{mLed.length + ' in ' + mLabel(L.ym, true)}</span>
        </div>
        {mLed.slice(0, 12).map((x) => (
          <button key={x.t.id} onClick={() => ui.open({ kind: 'tx', tx: x.t })} style={css('display:flex;align-items:center;gap:12px;width:100%;min-height:54px;padding:8px 0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')}>
            <span style={css('font-size:13px;width:50px;flex:none;color:var(--mute)')}>{dLab(isoD(x.t.date)).slice(4)}</span>
            <span style={css('flex:1;min-width:0;display:flex;flex-direction:column')}>
              <span style={css('font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap')}>{x.t.name}</span>
              <span style={css('font-size:12.5px;color:var(--mute)')}>{x.t.type === 'xfer' ? L.aName(x.t.acct) + ' → ' + L.aName(x.t.to) : L.catOf(x.t.cat).name}</span>
            </span>
            <span style={css('display:flex;flex-direction:column;align-items:flex-end')}>
              <span style={sx('font-weight:500;white-space:nowrap', { color: x.v > 0 ? 'var(--good)' : 'var(--ink)' })}>{(x.v > 0 ? '+' : '') + f(x.v)}</span>
              <span style={css('font-size:12px;color:var(--mute)')}>{f(Math.round(x.after))}</span>
            </span>
          </button>
        ))}
        {!mLed.length && <div style={css('padding:20px 0;color:var(--mute);font-size:14px')}>Nothing moved through this account this month.</div>}
        <div style={css('font-size:12.5px;color:var(--mute);padding-top:12px')}>{mLed.length > 12 ? 'Showing the latest 12. Filter Activity by this account for the rest.' : 'Small figure under each amount is the balance after it.'}</div>
      </div>
    </section>
  )
}

export const accountsTab: TabDef = {
  id: 'accounts',
  stage: 'lav',
  kicker: () => 'Balances and cards',
  // Net worth (with assets and history) has its own tab now.
  hero: (L) => {
    const { f } = L
    const mix: [string, string[]][] = [['Cash', ['current', 'cash']], ['Savings', ['save']], ['Investments', ['invest']]]
    return {
      label: 'Across your accounts',
      cur: true,
      num: L.num(sum(L.accounts, (a) => a.balance)),
      fg: '#ffffff',
      sub: 'Everyday money, savings and cards. The full picture, with your assets, is under Net worth.',
      stats: mix.map(([label, types]) => [label, f(sum(L.accounts.filter((a) => types.includes(a.type)), (a) => a.balance))] as [string, string]),
    }
  },
  Body,
}
