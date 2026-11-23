// Budget months that start on a chosen day (Household.cycleStart, 1–28; 1 = calendar months).
// A period is keyed "YYYY-MM" like a month, named after the month most of its days are in:
// with start 25, "2026-11" runs 25 Oct – 24 Nov; with start 10, "2026-11" runs 10 Nov – 9 Dec.
// Same rules as the iPhone app (Model/Period.swift).
import { addM, dim, isoD, isoOf, MN, mLabel, pad } from './dates'

export interface PeriodRange { from: string; to: string }

/** The household's start day, clamped to 1…28. */
export const cycleStartOf = (h: { cycleStart?: number | null } | null | undefined) => {
  const s = Math.round(Number(h?.cycleStart) || 1)
  return Math.max(1, Math.min(28, s))
}

/** Period key of the period an ISO date ("YYYY-MM-DD") falls in. */
export function periodKey(iso: string, start = 1): string {
  const ym = iso.slice(0, 7)
  if (start <= 1) return ym
  const startMonth = Number(iso.slice(8, 10)) >= start ? ym : addM(ym, -1)
  return start <= 15 ? startMonth : addM(startMonth, 1)
}

const startDate = (m: string, start: number) => m + '-' + pad(Math.min(start, dim(m)))

/** First and last day of period `key`, both inclusive. */
export function periodRange(key: string, start = 1): PeriodRange {
  if (start <= 1) return { from: key + '-01', to: key + '-' + pad(dim(key)) }
  const startMonth = start <= 15 ? key : addM(key, -1)
  const next = isoD(startDate(addM(startMonth, 1), start))
  return { from: startDate(startMonth, start), to: isoOf(new Date(next.getFullYear(), next.getMonth(), next.getDate() - 1)) }
}

/** Whole days from a to b (ISO dates; b − a). */
export const daysBetween = (a: string, b: string) => Math.round((isoD(b).getTime() - isoD(a).getTime()) / 86400000)

/** 1-based day number of `iso` in a period starting `from`. */
export const dayIndex = (from: string, iso: string) => daysBetween(from, iso) + 1

export const periodDays = (key: string, start = 1) => { const r = periodRange(key, start); return dayIndex(r.from, r.to) }

export const contains = (key: string, iso: string, start = 1) => { const r = periodRange(key, start); return iso >= r.from && iso <= r.to }

export const shiftPeriod = (key: string, n: number) => addM(key, n)

/** "25 Oct" */
const dm = (iso: string) => Number(iso.slice(8, 10)) + ' ' + MN[Number(iso.slice(5, 7)) - 1].slice(0, 3)

/** "25 Oct – 24 Nov" */
export const rangeLabel = (key: string, start = 1) => { const r = periodRange(key, start); return dm(r.from) + ' – ' + dm(r.to) }

/** "November 2026", plus " · 25 Oct – 24 Nov" when the budget month doesn't start on the 1st. */
export const periodLabel = (key: string, start = 1, short?: boolean) =>
  mLabel(key, short) + (start > 1 ? ' · ' + rangeLabel(key, start) : '')

/**
 * When a bill on `day` of the month is due inside period `key`: the date with day
 * min(day, days in that month) that falls inside the range (start month or the next one).
 * Its calendar month ("YYYY-MM", the first 7 characters) is the bill's `paid` key.
 */
export function billDue(day: number, key: string, start = 1): string {
  const r = periodRange(key, start)
  for (const m of [r.from.slice(0, 7), r.to.slice(0, 7)]) {
    const iso = m + '-' + pad(Math.min(day, dim(m)))
    if (iso >= r.from && iso <= r.to) return iso
  }
  // Unreachable for periods of a month, kept as a safe fallback.
  return r.from
}
