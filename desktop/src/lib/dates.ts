// Months are "YYYY-MM", days "YYYY-MM-DD", in local time (same as the iPhone app).
export const MN = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
export const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
export const pad = (n: number) => String(n).padStart(2, '0')
export const ymOf = (d: Date) => d.getFullYear() + '-' + pad(d.getMonth() + 1)
export const isoOf = (d: Date) => ymOf(d) + '-' + pad(d.getDate())
export const addM = (ym: string, n: number) => { const p = ym.split('-').map(Number); return ymOf(new Date(p[0], p[1] - 1 + n, 1)) }
export const dim = (ym: string) => { const p = ym.split('-').map(Number); return new Date(p[0], p[1], 0).getDate() }
export const mLabel = (ym: string, short?: boolean) => { const p = ym.split('-').map(Number); return (short ? MN[p[1] - 1].slice(0, 3) : MN[p[1] - 1]) + ' ' + p[0] }
export const isoD = (s: string) => { const p = s.split('-').map(Number); return new Date(p[0], p[1] - 1, p[2]) }
/** "Sat 21 Nov" */
export const dLab = (d: Date) => WD[d.getDay()] + ' ' + d.getDate() + ' ' + MN[d.getMonth()].slice(0, 3)
export const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
/** Months from a to b ("YYYY-MM"). */
export const mBetween = (a: string, b: string) => { const p = a.split('-').map(Number), q = b.split('-').map(Number); return (q[0] - p[0]) * 12 + q[1] - p[1] }
