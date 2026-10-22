import { db, setMeta, type Weight, type Gap, type Reason, type Steps } from './db'
import { iso, todayDate, isEveningNow } from './dates'
import { sync } from './sync'
import { supabase } from './supabase'

/** Writes go local first, then kick a sync. Reads come from Dexie. */
export async function saveToday(kg: number) {
  const now = new Date().toISOString()
  const w: Weight = { date: iso(todayDate()), kg: Math.round(kg * 10) / 10, evening: isEveningNow(), loggedAt: now, updatedAt: now, deleted: false, synced: 0 }
  await db.weights.put(w)
  void sync()
}

export async function saveGapReasons(entries: { date: string; reason: string }[]) {
  const now = new Date().toISOString()
  const gaps: Gap[] = entries.map(e => ({ date: e.date, reason: e.reason.trim(), updatedAt: now, deleted: false, synced: 0 }))
  await db.gaps.bulkPut(gaps)
  const names = [...new Set(gaps.map(g => g.reason))]
  const reasons: Reason[] = names.map(name => ({ name, lastUsed: now, updatedAt: now, deleted: false, synced: 0 }))
  await db.reasons.bulkPut(reasons)
  void sync()
}

/** Steps for one or more past days (yesterday, or older days that were missed). One row per day; saving again replaces. */
export async function saveSteps(entries: { date: string; count: number }[]) {
  const now = new Date().toISOString()
  const rows: Steps[] = entries.map(e => ({ date: e.date, count: Math.round(e.count), updatedAt: now, deleted: false, synced: 0 }))
  await db.steps.bulkPut(rows)
  void sync()
}

/** The daily steps goal lives on the profile so every device of this user sees the same line. */
export async function setStepsGoal(goal: number) {
  await setMeta('stepsGoal', String(goal))
  if (!supabase) return
  const { data: { session } } = await supabase.auth.getSession()
  if (session) await supabase.from('profiles').update({ steps_goal: goal }).eq('id', session.user.id)
}

export async function removeReason(name: string) {
  const now = new Date().toISOString()
  await db.reasons.put({ name, lastUsed: now, updatedAt: now, deleted: true, synced: 0 })
  void sync()
}

export async function loadAll() {
  const [weights, gaps, reasons, steps] = await Promise.all([db.weights.toArray(), db.gaps.toArray(), db.reasons.toArray(), db.steps.toArray()])
  return { weights: weights.filter(w => !w.deleted), gaps: gaps.filter(g => !g.deleted), reasons: reasons.filter(r => !r.deleted).sort((a, b) => b.lastUsed.localeCompare(a.lastUsed)), steps: steps.filter(s => !s.deleted) }
}

export async function exportJson() {
  const data = await loadAll()
  const blob = new Blob([JSON.stringify({ exportedAt: new Date().toISOString(), ...data }, null, 2)], { type: 'application/json' })
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `healthtracker-${iso(todayDate())}.json`; a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 5000)
}

/** Start fresh: server rows deleted via a security-definer function, then the local copy. */
export async function resetAll() {
  if (supabase) {
    const { data, error } = await supabase.rpc('reset_my_data')
    if (error) throw error
    await db.transaction('rw', db.weights, db.gaps, db.reasons, db.steps, db.meta, async () => {
      await db.weights.clear(); await db.gaps.clear(); await db.reasons.clear(); await db.steps.clear()
      await db.meta.put({ key: 'resetAt', value: data as string })
    })
  } else {
    await db.weights.clear(); await db.gaps.clear(); await db.reasons.clear(); await db.steps.clear()
  }
}
