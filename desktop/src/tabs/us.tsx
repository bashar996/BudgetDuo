// Us two: settle-up, who paid, pocket money, pay and the monthly money date.
import { css, sx } from '../lib/css'
import { pc, sum } from '../lib/money'
import { CHECKS } from '../data/catalog'
import type { Ledger, Row } from '../data/ledger'
import type { Who } from '../data/types'
import { useStore } from '../data/store'
import { useUI, type TabDef } from '../shell/ui'

/** Shared costs this month and who owes whom (the design's `us`). */
export function settleUp(L: Ledger) {
  const { A, B, f, H } = L
  const split = (H.splitMode ?? 'One joint pot') !== 'One joint pot'
  const pd: Record<Who, number> = { A: 0, B: 0, J: 0 }
  L.exp.filter((t) => t.cat !== 'allowA' && t.cat !== 'allowB').forEach((t) => (pd[t.who] += t.amt))
  const incA = sum(H.incomes.filter((x) => x.who === 'A'), (x) => x.amt), incB = L.income - incA
  const rA = (H.splitRule ?? '50/50') === 'By income' ? incA / (L.income || 1) : 0.5
  // What's already been settled this month is taken off.
  const owe = pd.A - rA * (pd.A + pd.B) - (Number(H.settled?.[L.ym]) || 0)
  const sq = Math.abs(owe) < 1
  return {
    split, pd, incA, incB, owe, sq,
    rule: Math.round(rA * 100) + ' / ' + Math.round((1 - rA) * 100),
    line: sq ? 'You’re all square' : (owe > 0 ? B + ' owes ' + A : A + ' owes ' + B) + ' ' + f(Math.round(Math.abs(owe))),
    sub: sq ? 'Nothing to move between you this month.' : A + ' covered ' + f(pd.A) + ' and ' + B + ' covered ' + f(pd.B) + ' of shared costs from personal cards.',
  }
}

/** "AED 120 left" / "AED 30 over" and the detail line under a budget bar. */
export const leftText = (L: Ledger, r: Row) => (r.left < 0 ? L.f(-r.left) + ' over' : L.f(r.left) + ' left')
export const rowDetail = (L: Ledger, r: Row) => L.f(r.sp) + ' of ' + L.f(r.avail) + ' · ' + leftText(L, r)

const contrib = (L: Ledger, s: ReturnType<typeof settleUp>) => ([['A', L.A, s.incA, 'var(--a)'], ['B', L.B, s.incB, 'var(--b)']] as const).map(([who, label, v, color]) => ({
  who, label, color, w: pc(v / (L.income || 1)), amt: L.f(v) + ' · ' + Math.round((v / (L.income || 1)) * 100) + '%',
}))

const H2 = "font:500 22px 'Geist',sans-serif;letter-spacing:-.01em"

function Body({ L }: { L: Ledger }) {
  const { act } = useStore()
  const { open } = useUI()
  const s = settleUp(L)
  const total = s.pd.A + s.pd.B + s.pd.J || 1
  const paid = (['A', 'B', 'J'] as Who[]).map((w) => ({ w, label: L.whoName[w] + (w === 'J' ? ' account' : ''), amt: L.f(s.pd[w]), width: pc(s.pd[w] / total), color: L.whoCol[w] }))
  const allow = ([['allowA', L.A], ['allowB', L.B]] as const).map(([id, name]) => ({ name, r: L.rows.find((x) => x.id === id) }))
  const pay = contrib(L, s)
  const checks = CHECKS.map((t, i) => ({ t, k: L.ym + ':' + i, on: !!L.H.checks?.[L.ym + ':' + i] }))
  return (
    <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:30px 40px;align-items:start')}>
      {s.split && (
        <section style={css('grid-column:1/-1;background:#0b0b0c;color:#ffffff;border-radius:28px;padding:clamp(22px,4vw,34px);display:flex;flex-wrap:wrap;gap:20px;align-items:center;justify-content:space-between')}>
          <div style={css('min-width:220px;flex:1')}>
            <div style={css('font-size:13.5px;color:#a9a7b8')}>Settle up · split {s.rule}</div>
            <div style={css("font:500 clamp(30px,5vw,48px)/1.05 'Geist',sans-serif;letter-spacing:-.03em;margin-top:8px")}>{s.line}</div>
            <div style={css('margin-top:8px;font-size:14px;color:#d9d7e4')}>{s.sub}</div>
          </div>
          {!s.sq && <button onClick={() => act.setSettled(L.ym, s.owe)} style={css("font:500 15px 'Geist',sans-serif;padding:0 24px;height:52px;border-radius:18px;border:none;background:var(--accBase);color:#0b0b0c;cursor:pointer")}>Mark as settled</button>}
        </section>
      )}
      <section style={css('display:flex;flex-direction:column;gap:4px')}>
        <span style={css(H2)}>Who paid for shared things</span>
        <div style={css('display:flex;height:16px;border-radius:8px;overflow:hidden;background:var(--soft);margin:10px 0 4px')}>
          {paid.map((p) => <div key={p.w} style={{ width: p.width, background: p.color }} />)}
        </div>
        {paid.map((p) => (
          <div key={p.w} style={css('display:flex;align-items:center;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)')}>
            <span style={sx('width:14px;height:14px;border-radius:5px', { background: p.color })} />
            <span style={css('flex:1;font-size:16px')}>{p.label}</span>
            <span style={css('font-size:15px;font-weight:500')}>{p.amt}</span>
          </div>
        ))}
      </section>
      <section>
        <span style={css(H2)}>Pocket money</span>
        {allow.map(({ name, r }) => r && (
          <div key={name} style={css('padding:12px 0 2px')}>
            <div style={css('display:flex;justify-content:space-between;align-items:flex-end;gap:10px')}><span style={css('font-size:16px')}>{name}</span><span style={css('font-size:22px;letter-spacing:-.02em;line-height:1')}>{leftText(L, r)}</span></div>
            <div style={css('height:5px;border-radius:3px;background:var(--track);margin-top:8px')}><div style={sx('height:100%;background:var(--acc);border-radius:3px', { width: pc(r.ratio) })} /></div>
            <div style={css('font-size:12.5px;color:var(--mute);margin-top:6px')}>{rowDetail(L, r)}</div>
          </div>
        ))}
        <div style={css('font-size:13px;color:var(--mute);margin-top:10px')}>No-questions-asked money for each of you.</div>
      </section>
      <section style={css('display:flex;flex-direction:column;gap:4px')}>
        <span style={css(H2)}>Income coming in</span>
        <div style={css('display:flex;height:16px;border-radius:8px;overflow:hidden;background:var(--soft);margin:10px 0 4px')}>
          {pay.map((p) => <div key={p.who} style={{ width: p.w, background: p.color }} />)}
        </div>
        {pay.map((p) => (
          <button key={p.who} className="h-row" onClick={() => open({ kind: 'item', item: 'income', who: p.who })} style={css('display:flex;align-items:center;gap:12px;width:100%;min-height:48px;padding:0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')}>
            <span style={sx('width:14px;height:14px;border-radius:5px', { background: p.color })} />
            <span style={css('flex:1;font-size:16px')}>{p.label}</span>
            <span style={css('font-size:15px;font-weight:500')}>{p.amt}</span>
          </button>
        ))}
        <div style={css('font-size:13px;color:var(--mute);margin-top:8px')}>Pick a name to set pay and payday.</div>
      </section>
      <section>
        <div style={css('display:flex;justify-content:space-between;align-items:baseline;gap:12px')}>
          <span style={css(H2)}>Money date</span>
          <span style={css('font-size:13px;color:var(--mute)')}>{checks.filter((c) => c.on).length} of {CHECKS.length} done</span>
        </div>
        <div style={css('font-size:13px;color:var(--mute);margin:2px 0 10px')}>Twenty minutes, a coffee, and you’re both on the same page.</div>
        <div style={css('background:var(--card);border-radius:24px;padding:4px 18px')}>
          {checks.map((c) => (
            <button key={c.k} onClick={() => act.toggleCheck(c.k)} style={css('display:flex;align-items:center;gap:12px;width:100%;min-height:52px;padding:6px 0;background:none;border:none;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left')}>
              <span style={sx('width:24px;height:24px;flex:none;border-radius:8px;border:1.5px solid var(--ink);color:#ffffff;display:grid;place-items:center;font-size:14px;font-weight:600;box-sizing:border-box', { background: c.on ? 'var(--ink)' : 'transparent' })}>{c.on ? '✓' : ''}</span>
              <span style={{ textDecoration: c.on ? 'line-through' : 'none' }}>{c.t}</span>
            </button>
          ))}
        </div>
      </section>
    </div>
  )
}

export const usTab: TabDef = {
  id: 'us',
  stage: 'lav',
  kicker: () => 'Your household, together',
  hero: (L) => {
    const s = settleUp(L)
    return {
      label: 'Your household', num: L.A + ' & ' + L.B, fg: '#ffffff',
      sub: s.split ? s.sub : 'One joint pot. Everything you both add lands in the same budget.',
      stats: contrib(L, s).map((c) => [c.label + '’s pay', c.amt] as [string, string]),
    }
  },
  Body,
}
