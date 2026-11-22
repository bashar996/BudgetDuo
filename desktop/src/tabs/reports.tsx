// Reports: six months of money in and out, where it went, who spent, where you
// shopped, and a downloadable report (print-ready HTML or CSV) for the month.
import type { Ledger } from '../data/ledger'
import type { Who } from '../data/types'
import { css, sx } from '../lib/css'
import { addM, MN, mLabel } from '../lib/dates'
import { download, pc, sum, toCsv } from '../lib/money'
import type { TabDef } from '../shell/ui'

const LAV = 'var(--accBase)', CRM = '#fbf9ef'

/** Everything the Reports tab and the downloads show (the design's `rep` and `repData`). */
function rep(L: Ledger) {
  const { f, ym, exp, rows, tSpent, pSpent, day, whoName, whoCol } = L
  const six = [-5, -4, -3, -2, -1, 0].map((k) => {
    const m = addM(ym, k), t = L.inM(m)
    return { m, i: sum(t.filter((x) => x.type === 'inc'), (x) => x.amt), e: sum(t.filter((x) => x.type === 'exp'), (x) => x.amt), kids: sum(t.filter((x) => x.cat === 'kids'), (x) => x.amt) }
  })
  const mx = Math.max(1, ...six.map((x) => Math.max(x.i, x.e)))
  const varExp = exp.filter((t) => !t.billId)
  const big = [...varExp].sort((a, b) => b.amt - a.amt)[0]
  const spendDays: Record<string, 1> = {}
  varExp.forEach((t) => (spendDays[t.date] = 1))
  const incM = sum(L.inc, (t) => t.amt) || L.income
  const merMap: Record<string, { name: string; a: number; n: number }> = {}
  varExp.forEach((t) => { const o = merMap[t.name] || (merMap[t.name] = { name: t.name, a: 0, n: 0 }); o.a += t.amt; o.n++ })
  const mer = Object.values(merMap).sort((a, b) => b.a - a.a)
  const spRows = rows.filter((r) => r.sp > 0).sort((a, b) => b.sp - a.sp)
  const maxSp = spRows.length ? spRows[0].sp : 1
  const whoSp = (w: Who) => sum(exp.filter((t) => t.who === w), (t) => t.amt)

  const stats: [string, string][] = [
    ['Savings rate', incM ? Math.round(((incM - tSpent) / incM) * 100) + '%' : '—'],
    ['Daily average', f(Math.round(tSpent / Math.max(1, day)))],
    ['Largest purchase', big ? f(big.amt) : '—'],
    ['No-spend days', String(Math.max(0, day - Object.keys(spendDays).length))],
    ['Kids & family', f(Math.round(sum(six, (x) => x.kids) / 6))],
  ]
  const cats = spRows.map((r) => {
    const p = pSpent[r.id] || 0, d = p ? Math.round(((r.sp - p) / p) * 100) : null
    return {
      id: r.id, name: r.name, amt: f(r.sp), w: pc(r.sp / maxSp), share: Math.round((r.sp / tSpent) * 100) + '%',
      delta: d === null ? 'new' : d === 0 ? 'same' : (d > 0 ? '▲ ' : '▼ ') + Math.abs(d) + '%',
      deltaColor: d !== null && d > 0 ? 'var(--bad)' : d !== null && d < 0 ? 'var(--good)' : 'var(--mute)',
    }
  })
  const who = (['A', 'B', 'J'] as Who[]).map((w) => { const v = whoSp(w); return { key: w, label: whoName[w], amt: f(v), w: pc(v / (tSpent || 1)), color: whoCol[w] } })
  const merchants = mer.slice(0, 6).map((o) => ({ name: o.name, amt: f(o.a), count: o.n + '×' }))

  const data = () => ({
    ym, month: mLabel(ym), names: L.A + ' & ' + L.B, ccy: L.cur, spent: Math.round(tSpent), income: Math.round(incM), stats,
    cats: spRows.map((r) => [r.name, Math.round(r.sp), Math.round((r.sp / (tSpent || 1)) * 100) + '%', Math.round(pSpent[r.id] || 0)] as [string, number, string, number]),
    who: (['A', 'B', 'J'] as Who[]).map((w) => [whoName[w], Math.round(whoSp(w))] as [string, number]),
    mer: mer.slice(0, 10).map((o) => [o.name, o.n, Math.round(o.a)] as [string, number, number]),
    months: six.map((x) => [mLabel(x.m), Math.round(x.i), Math.round(x.e), Math.round(x.i - x.e)] as [string, number, number, number]),
  })
  return { six, mx, stats, cats, who, merchants, data }
}

type ReportData = ReturnType<ReturnType<typeof rep>['data']>

const RCSS = "body{margin:0;background:#fbf9ef;color:#0b0b0c;font:15px/1.4 'Geist',system-ui,sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact}.w{max-width:760px;margin:0 auto;padding:48px 32px}.k{font-size:13px;color:#6b6878}h1{font:500 72px/1 'Geist',sans-serif;letter-spacing:-.045em;margin:8px 0 6px}h1 small{font-size:24px;letter-spacing:0;color:#6b6878}h2{font:500 22px 'Geist',sans-serif;letter-spacing:-.01em;margin:38px 0 6px}.s{display:flex;flex-wrap:wrap;gap:14px 34px;margin-top:24px}.s b{display:block;font:500 18px 'Geist',sans-serif}table{width:100%;border-collapse:collapse}td,th{padding:10px 0;border-bottom:1px solid rgba(11,11,12,.12);text-align:left;font-weight:400;vertical-align:bottom}th{font-size:13px;color:#6b6878}.n{text-align:right;white-space:nowrap;padding-left:18px;font-variant-numeric:tabular-nums}.t{height:5px;border-radius:3px;background:#0b0b0c;margin-top:7px}.f{height:100%;border-radius:3px;background:#b9b0ff}button{float:right;font:500 14px 'Geist',sans-serif;height:44px;padding:0 18px;border-radius:22px;border:none;background:#0b0b0c;color:#fff;cursor:pointer}@media print{.w{padding:0}button{display:none}h2{break-after:avoid}tr{break-inside:avoid}}"

/** The design's report(kind, R): a styled, print-ready HTML page or a CSV. */
function report(kind: 'html' | 'csv', R: ReportData) {
  if (kind === 'csv') {
    const c = R.ccy
    const rows: (string | number)[][] = [['Twofold report', R.month], ['Household', R.names], [], ['Spent (' + c + ')', R.spent], ['Income (' + c + ')', R.income]]
    rows.push(...R.stats, [], ['Category', 'Spent (' + c + ')', 'Share', 'Last month (' + c + ')'], ...R.cats,
      [], ['Who', 'Spent (' + c + ')'], ...R.who, [], ['Place', 'Visits', 'Spent (' + c + ')'], ...R.mer,
      [], ['Month', 'Income', 'Spending', 'Net'], ...R.months)
    return download('twofold-report-' + R.ym + '.csv', toCsv(rows), 'text/csv')
  }
  const e = (s: string | number) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
  const n = (v: number) => e(R.ccy) + ' ' + Number(v).toLocaleString('en-US')
  const max = R.cats.length ? R.cats[0][1] : 1
  const tbl = (head: string[], rows: (string | number)[][]) =>
    '<table><tr>' + head.map((h, i) => '<th' + (i ? ' class="n"' : '') + '>' + h + '</th>').join('') + '</tr>' +
    rows.map((r) => '<tr>' + r.map((c, i) => '<td' + (i ? ' class="n"' : '') + '>' + c + '</td>').join('') + '</tr>').join('') + '</table>'
  const html = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Twofold report · ' + e(R.month) + '</title><link href="https://fonts.googleapis.com/css2?family=Geist:wght@400..700&display=swap" rel="stylesheet"><style>' + RCSS + '</style></head><body><div class="w"><button onclick="print()">Print or save as PDF</button><div class="k">Twofold · ' + e(R.names) + ' · ' + e(R.month) + '</div><h1><small>' + e(R.ccy) + '</small> ' + Number(R.spent).toLocaleString('en-US') + '</h1><div class="k">spent this month, with ' + n(R.income) + ' coming in</div><div class="s">' + R.stats.map((s) => '<div><span class="k">' + e(s[0]) + '</span><b>' + e(s[1]) + '</b></div>').join('') + '</div>'
    + '<h2>Where it went</h2>' + tbl(['Category', 'Share', 'Spent', 'Last month'], R.cats.map((c) => [e(c[0]) + '<div class="t"><div class="f" style="width:' + ((c[1] / max) * 100).toFixed(1) + '%"></div></div>', c[2], n(c[1]), n(c[3])]))
    + '<h2>Who spent</h2>' + tbl(['Who', 'Spent'], R.who.map((w) => [e(w[0]), n(w[1])]))
    + '<h2>Most-visited places</h2>' + tbl(['Place', 'Visits', 'Spent'], R.mer.map((m) => [e(m[0]), m[1], n(m[2])]))
    + '<h2>Last six months</h2>' + tbl(['Month', 'Income', 'Spending', 'Net'], R.months.map((m) => [e(m[0]), n(m[1]), n(m[2]), n(m[3])]))
    + '<p class="k" style="margin-top:36px">Generated ' + new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) + '.</p></div></body></html>'
  download('twofold-report-' + R.ym + '.html', html, 'text/html')
}

const title = "font:500 22px 'Geist',sans-serif;letter-spacing:-.01em"
const empty = 'padding:8px 0;font-size:14px;color:var(--mute)'

function Header({ L }: { L: Ledger }) {
  const go = (kind: 'html' | 'csv') => report(kind, rep(L).data())
  return (
    <div style={css('display:flex;flex-wrap:wrap;gap:10px')}>
      <button onClick={() => go('html')} style={css("flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 20px;height:50px;border-radius:18px;border:none;background:#ffffff;color:#0b0b0c;cursor:pointer")}>↓ Download report</button>
      <button onClick={() => go('csv')} style={css("flex:none;white-space:nowrap;font:500 14px 'Geist',sans-serif;padding:0 18px;height:50px;border-radius:18px;border:1px solid rgba(255,255,255,.3);background:transparent;color:#ffffff;cursor:pointer")}>Export CSV</button>
    </div>
  )
}

function Body({ L }: { L: Ledger }) {
  const R = rep(L)
  return (
    <div style={css('display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:30px 40px;align-items:start')}>
      <section>
        <span style={css(title)}>Where it went</span>
        {R.cats.map((c) => (
          <div key={c.id} style={css('padding:12px 0 2px')}>
            <div style={css('display:flex;justify-content:space-between;align-items:flex-end;gap:10px')}>
              <span style={css('font-size:16px')}>{c.name} <span style={sx('font-size:12.5px', { color: c.deltaColor })}>{c.delta}</span></span>
              <span style={css('font-size:27px;letter-spacing:-.02em;line-height:1')}>{c.share}</span>
            </div>
            <div style={css('height:5px;border-radius:3px;background:var(--track);margin-top:8px')}><div style={sx('height:100%;background:var(--acc);border-radius:3px', { width: c.w })} /></div>
            <div style={css('font-size:12.5px;color:var(--mute);margin-top:6px')}>{c.amt} this month</div>
          </div>
        ))}
        {!R.cats.length && <div style={css(empty)}>No spending recorded this month.</div>}
        <div style={css('font-size:12.5px;color:var(--mute);margin-top:12px')}>▲▼ compares with the full previous month.</div>
      </section>
      <div style={css('display:flex;flex-direction:column;gap:30px;min-width:0')}>
        <section style={css('display:flex;flex-direction:column;gap:4px')}>
          <span style={css(title)}>Who spent</span>
          <div style={css('display:flex;height:16px;border-radius:8px;overflow:hidden;background:var(--soft);margin:10px 0 4px')}>
            {R.who.map((w) => <div key={w.key} style={{ width: w.w, background: w.color }} />)}
          </div>
          {R.who.map((w) => (
            <div key={w.key} style={css('display:flex;align-items:center;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)')}>
              <span style={sx('width:14px;height:14px;border-radius:5px', { background: w.color })} />
              <span style={css('flex:1;font-size:16px')}>{w.label}</span>
              <span style={css('font-size:15px;font-weight:500')}>{w.amt}</span>
            </div>
          ))}
        </section>
        <section>
          <span style={css(title)}>Most-visited places</span>
          <div style={css('margin-top:6px')}>
            {R.merchants.map((m) => (
              <div key={m.name} style={css('display:flex;align-items:center;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)')}>
                <span style={css('flex:1;min-width:0;font-size:16px')}>{m.name}</span>
                <span style={css('font-size:13px;color:var(--mute)')}>{m.count}</span>
                <span style={css('font-size:15px;font-weight:500;min-width:84px;text-align:right')}>{m.amt}</span>
              </div>
            ))}
            {!R.merchants.length && <div style={css(empty)}>No purchases recorded this month.</div>}
          </div>
        </section>
      </div>
    </div>
  )
}

export const reportsTab: TabDef = {
  id: 'reports',
  stage: 'cream',
  kicker: () => 'Trends and breakdowns',
  hero: (L) => {
    const R = rep(L)
    return {
      label: 'Spent in ' + mLabel(L.ym), cur: true, num: L.num(Math.round(L.tSpent)), fg: '#ffffff',
      sub: 'Lavender is money in, cream is money out, month by month.', stats: R.stats,
      bars: R.six.map((x) => ({
        h: pc(Math.max(0.02, x.i / R.mx)), bg: LAV, h2: pc(Math.max(0.02, x.e / R.mx)), bg2: CRM, label: MN[+x.m.slice(5) - 1].slice(0, 3),
        title: mLabel(x.m, true) + ' · in ' + L.f(Math.round(x.i)) + ' · out ' + L.f(Math.round(x.e)),
      })),
    }
  },
  Header,
  Body,
}
