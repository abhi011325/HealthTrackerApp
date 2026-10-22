import type { Weight, Gap, Steps, EarnedDay } from './db'
import { addDays, daysBetween, iso, parse, todayDate } from './dates'

export interface Point { date: string; kg: number; evening: boolean; avg: number; n: number }

/** Readings dated within the `days` calendar days ending on `end` (inclusive). */
export const inWindow = (s: { date: string; kg: number }[], end: Date, days: number) =>
  s.filter(p => { const diff = daysBetween(parse(p.date), end); return diff >= 0 && diff < days })

export const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length

/** Sorted live readings with a trailing 7-day average on each. */
export function series(weights: Weight[]): Point[] {
  const s = weights.filter(w => !w.deleted).sort((a, b) => a.date.localeCompare(b.date))
  return s.map(p => { const win = inWindow(s, parse(p.date), 7); return { date: p.date, kg: p.kg, evening: p.evening, avg: mean(win.map(q => q.kg)), n: win.length } })
}

export interface Summary {
  avg: number | null; avgBuilding: number        // avg of last 7 calendar days; building = readings in window when < 3
  today: Point | null
  last: Point | null; gapDays: number           // days since last entry (0 = today)
  weekDelta: number | null                      // mean(last 7 days) - mean(7 before), null if either side < 3 readings
  sinceStart: number | null; startDate: string | null
  missed: string[]                               // dates between last entry and today with no weight and no reason
}

export function summarize(weights: Weight[], gaps: Gap[]): Summary {
  const s = series(weights); const today = todayDate(); const t = iso(today)
  const reasoned = new Set(gaps.filter(g => !g.deleted).map(g => g.date))
  if (!s.length) return { avg: null, avgBuilding: 0, today: null, last: null, gapDays: 0, weekDelta: null, sinceStart: null, startDate: null, missed: [] }
  const last = s[s.length - 1]
  const winNow = inWindow(s, today, 7)
  const avg = winNow.length >= 3 ? mean(winNow.map(q => q.kg)) : last.avg
  const gapDays = daysBetween(parse(last.date), today)
  const missed: string[] = []
  for (let i = 1; i < gapDays; i++) { const d = iso(addDays(today, -i)); if (!reasoned.has(d)) missed.push(d) }
  missed.sort()
  const w1 = inWindow(s, today, 7), w0 = inWindow(s, addDays(today, -7), 7)
  const weekDelta = w1.length >= 3 && w0.length >= 3 ? mean(w1.map(q => q.kg)) - mean(w0.map(q => q.kg)) : null
  return {
    avg, avgBuilding: winNow.length >= 3 ? 0 : winNow.length,
    today: s.find(p => p.date === t) ?? null, last, gapDays, weekDelta,
    sinceStart: avg - s[0].kg, startDate: s[0].date, missed,
  }
}

/** Consecutive logged days ending today or yesterday (a miss today does not break it until tomorrow). */
export function streak(weights: Weight[]): number {
  const have = new Set(weights.filter(w => !w.deleted).map(w => w.date))
  const today = todayDate()
  let d = have.has(iso(today)) ? today : addDays(today, -1)
  let n = 0
  while (have.has(iso(d))) { n++; d = addDays(d, -1) }
  return n
}

// ---------- steps ----------
export interface StepPoint { date: string; count: number; avg: number }

/** Sorted live step days with a trailing 7-day average (mean of the days that have a count). */
export function stepSeries(steps: Steps[]): StepPoint[] {
  const s = steps.filter(x => !x.deleted).sort((a, b) => a.date.localeCompare(b.date))
  return s.map(p => { const win = s.filter(q => { const d = daysBetween(parse(q.date), parse(p.date)); return d >= 0 && d < 7 }); return { date: p.date, count: p.count, avg: mean(win.map(q => q.count)) } })
}

export interface StepsSummary {
  avg: number | null; n: number          // mean of the days logged in the 7 calendar days ending yesterday; n = how many of those 7
  weekDelta: number | null               // that mean minus the one for the 7 days before, null unless both sides have >= 3 days
  missed: string[]                        // days in the 14 before yesterday with no count, from the first entry onward; oldest first; empty until the first entry exists
}

export function summarizeSteps(steps: Steps[]): StepsSummary {
  const live = steps.filter(x => !x.deleted); const have = new Map(live.map(x => [x.date, x.count]))
  const yesterday = addDays(todayDate(), -1)
  const win = (end: Date) => { const out: number[] = []; for (let i = 0; i < 7; i++) { const c = have.get(iso(addDays(end, -i))); if (c !== undefined) out.push(c) } return out }
  const w1 = win(yesterday), w0 = win(addDays(yesterday, -7))
  const missed: string[] = []
  const first = [...have.keys()].sort()[0]
  if (first) for (let i = 14; i >= 1; i--) { const d = iso(addDays(yesterday, -i)); if (d >= first && !have.has(d)) missed.push(d) }
  return { avg: w1.length >= 3 ? mean(w1) : null, n: w1.length, weekDelta: w1.length >= 3 && w0.length >= 3 ? mean(w1) - mean(w0) : null, missed }
}

// ---------- earned day ----------
/** The rule, as agreed in HealthTracker/EARNED-DAY.md. Rates are fixed at 0.7 kg/week for both tests. */
export const EARN_RATE = 0.7

export type DayState = 'earned' | 'taken' | 'sunday' | 'hold' | 'noentry'
export interface DayVerdict {
  state: DayState
  title: string
  detail: string          // the numbers that earned it, or the first rule that failed
  canTake: boolean
}

export function dayVerdict(sum: Summary, earned: EarnedDay[], goalKg: number | null): DayVerdict {
  const today = todayDate(); const t = iso(today)
  const live = earned.filter(e => !e.deleted).map(e => e.date).sort()
  const fmt = (n: number) => Math.abs(n).toFixed(1)
  if (live.includes(t)) return { state: 'taken', title: 'Day taken', detail: 'Food and the workout are your call today. Steps and the sleep window stay.', canTake: false }
  if (today.getDay() === 0) return { state: 'sunday', title: 'Sunday', detail: 'Your free day: no diet, no session. Steps and the sleep window stay.', canTake: false }
  if (!sum.today) return { state: 'noentry', title: "Log today's weight", detail: "The day card needs this morning's reading.", canTake: false }
  if (sum.avg === null || sum.avgBuilding) return { state: 'hold', title: 'Hold the plan today', detail: 'Not enough entries yet.', canTake: false }
  const atGoal = goalKg !== null && sum.avg <= goalKg
  const why: string[] = []
  if (!atGoal) {
    if (sum.weekDelta === null) return { state: 'hold', title: 'Hold the plan today', detail: 'Not enough entries yet for the week comparison.', canTake: false }
    const weekDelta = Math.round(sum.weekDelta * 10) / 10
    const weeks = Math.max(1 / 7, daysBetween(parse(sum.startDate!), today) / 7)
    const pace = (sum.sinceStart ?? 0) / weeks
    if (weekDelta > -EARN_RATE) why.push(`${weekDelta < 0 ? fmt(weekDelta) + ' kg down' : fmt(weekDelta) + ' kg up'} on last week, needs ${EARN_RATE}`)
    if (pace > -EARN_RATE) why.push(`${fmt(pace)} kg a week ${pace <= 0 ? 'down' : 'up'} since start, needs ${EARN_RATE}`)
    const last = live[live.length - 1]
    if (last && daysBetween(parse(last), today) < 7) why.push(`day taken ${fmtDayShort(parse(last))}, next from ${fmtDayShort(addDays(parse(last), 7))}`)
    if (why.length) return { state: 'hold', title: 'Hold the plan today', detail: why.join(' · '), canTake: false }
    return { state: 'earned', title: 'Earned day', detail: `${fmt(weekDelta)} kg down on last week · ${fmt(pace)} kg a week since start`, canTake: true }
  }
  const last = live[live.length - 1]
  if (last && daysBetween(parse(last), today) < 7) return { state: 'hold', title: 'Hold the plan today', detail: `day taken ${fmtDayShort(parse(last))}, next from ${fmtDayShort(addDays(parse(last), 7))}`, canTake: false }
  return { state: 'earned', title: 'Earned day', detail: `At goal (${sum.avg.toFixed(1)} kg, goal ${goalKg}). One a week.`, canTake: true }
}
const fmtDayShort = (d: Date) => d.toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' })
