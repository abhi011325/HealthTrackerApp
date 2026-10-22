import { supabase } from './supabase'
import { db, getMeta, setMeta, clearAllLocal } from './db'

/** Local-first sync. Every save lands in IndexedDB first; this pushes unsynced rows and pulls newer ones.
 *  Runs on app open, after every save, when the phone comes back online and when the app returns to the foreground.
 *  Conflicts: the row with the later updated_at wins. */
export type SyncState = 'synced' | 'waiting' | 'offline' | 'error' | 'syncing'
let listeners: ((s: SyncState, pending: number) => void)[] = []
export const onSync = (fn: (s: SyncState, pending: number) => void) => { listeners.push(fn); return () => { listeners = listeners.filter(l => l !== fn) } }
const emit = async (s: SyncState) => { const n = await pendingCount(); listeners.forEach(l => l(s, n)) }
export async function pendingCount() {
  const [a, b, c, d, e] = await Promise.all([db.weights.where('synced').equals(0).count(), db.gaps.where('synced').equals(0).count(), db.reasons.where('synced').equals(0).count(), db.steps.where('synced').equals(0).count(), db.earned.where('synced').equals(0).count()])
  return a + b + c + d + e
}

let running: Promise<void> | null = null
export function sync(): Promise<void> { if (running) return running; running = run().finally(() => { running = null }); return running }

async function run() {
  if (!supabase) return
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return
  if (!navigator.onLine) { await emit('offline'); return }
  const uid = session.user.id
  await emit('syncing')
  try {
    // 0. A reset elsewhere wipes this device's copy before anything is pushed back up.
    const { data: prof } = await supabase.from('profiles').select('reset_at, steps_goal, goal_kg').eq('id', uid).maybeSingle()
    const seenReset = (await getMeta('resetAt')) ?? ''
    if (prof?.reset_at && prof.reset_at > seenReset) { await clearAllLocal(); await setMeta('resetAt', prof.reset_at) }
    if (prof?.steps_goal) await setMeta('stepsGoal', String(prof.steps_goal))
    await setMeta('goalKg', prof?.goal_kg != null ? String(prof.goal_kg) : '')

    // 1. Push
    const w = await db.weights.where('synced').equals(0).toArray()
    if (w.length) {
      const { error } = await supabase.from('weights').upsert(w.map(x => ({ user_id: uid, date: x.date, kg: x.kg, evening: x.evening, logged_at: x.loggedAt, updated_at: x.updatedAt, deleted: x.deleted })))
      if (error) throw error
      await db.weights.bulkPut(w.map(x => ({ ...x, synced: 1 })))
    }
    const g = await db.gaps.where('synced').equals(0).toArray()
    if (g.length) {
      const { error } = await supabase.from('gaps').upsert(g.map(x => ({ user_id: uid, date: x.date, reason: x.reason, updated_at: x.updatedAt, deleted: x.deleted })))
      if (error) throw error
      await db.gaps.bulkPut(g.map(x => ({ ...x, synced: 1 })))
    }
    const r = await db.reasons.where('synced').equals(0).toArray()
    if (r.length) {
      const { error } = await supabase.from('reasons').upsert(r.map(x => ({ user_id: uid, name: x.name, last_used: x.lastUsed, updated_at: x.updatedAt, deleted: x.deleted })))
      if (error) throw error
      await db.reasons.bulkPut(r.map(x => ({ ...x, synced: 1 })))
    }
    const st = await db.steps.where('synced').equals(0).toArray()
    if (st.length) {
      const { error } = await supabase.from('steps').upsert(st.map(x => ({ user_id: uid, date: x.date, count: x.count, updated_at: x.updatedAt, deleted: x.deleted })))
      if (error) throw error
      await db.steps.bulkPut(st.map(x => ({ ...x, synced: 1 })))
    }
    const ed = await db.earned.where('synced').equals(0).toArray()
    if (ed.length) {
      const { error } = await supabase.from('earned_days').upsert(ed.map(x => ({ user_id: uid, date: x.date, updated_at: x.updatedAt, deleted: x.deleted })))
      if (error) throw error
      await db.earned.bulkPut(ed.map(x => ({ ...x, synced: 1 })))
    }

    // 2. Pull anything newer than the last pull
    const since = (await getMeta('pulledAt')) ?? '1970-01-01T00:00:00Z'
    let newest = since
    const [ws, gs, rs, ss, es] = await Promise.all([
      supabase.from('weights').select('*').gt('updated_at', since),
      supabase.from('gaps').select('*').gt('updated_at', since),
      supabase.from('reasons').select('*').gt('updated_at', since),
      supabase.from('steps').select('*').gt('updated_at', since),
      supabase.from('earned_days').select('*').gt('updated_at', since),
    ])
    for (const q of [ws, gs, rs, ss, es]) if (q.error) throw q.error
    for (const row of ws.data ?? []) {
      const local = await db.weights.get(row.date)
      if (!local || local.updatedAt < row.updated_at) await db.weights.put({ date: row.date, kg: Number(row.kg), evening: row.evening, loggedAt: row.logged_at, updatedAt: row.updated_at, deleted: row.deleted, synced: 1 })
      if (row.updated_at > newest) newest = row.updated_at
    }
    for (const row of gs.data ?? []) {
      const local = await db.gaps.get(row.date)
      if (!local || local.updatedAt < row.updated_at) await db.gaps.put({ date: row.date, reason: row.reason, updatedAt: row.updated_at, deleted: row.deleted, synced: 1 })
      if (row.updated_at > newest) newest = row.updated_at
    }
    for (const row of rs.data ?? []) {
      const local = await db.reasons.get(row.name)
      if (!local || local.updatedAt < row.updated_at) await db.reasons.put({ name: row.name, lastUsed: row.last_used, updatedAt: row.updated_at, deleted: row.deleted, synced: 1 })
      if (row.updated_at > newest) newest = row.updated_at
    }
    for (const row of ss.data ?? []) {
      const local = await db.steps.get(row.date)
      if (!local || local.updatedAt < row.updated_at) await db.steps.put({ date: row.date, count: Number(row.count), updatedAt: row.updated_at, deleted: row.deleted, synced: 1 })
      if (row.updated_at > newest) newest = row.updated_at
    }
    for (const row of es.data ?? []) {
      const local = await db.earned.get(row.date)
      if (!local || local.updatedAt < row.updated_at) await db.earned.put({ date: row.date, updatedAt: row.updated_at, deleted: row.deleted, synced: 1 })
      if (row.updated_at > newest) newest = row.updated_at
    }
    await setMeta('pulledAt', newest)
    await emit('synced')
  } catch (e) {
    console.warn('sync failed', e)
    await emit(navigator.onLine ? 'error' : 'offline')
  }
}

/** Wire the automatic triggers once. */
export function startAutoSync() {
  window.addEventListener('online', () => void sync())
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') void sync() })
  void sync()
}
