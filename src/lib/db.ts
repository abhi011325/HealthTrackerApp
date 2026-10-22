import Dexie, { type Table } from 'dexie'

/** One row per calendar day. `synced` false = not yet pushed to the database. */
export interface Weight { date: string; kg: number; evening: boolean; loggedAt: string; updatedAt: string; deleted: boolean; synced: 0 | 1 }
export interface Gap { date: string; reason: string; updatedAt: string; deleted: boolean; synced: 0 | 1 }
export interface Reason { name: string; lastUsed: string; updatedAt: string; deleted: boolean; synced: 0 | 1 }
/** Steps for one calendar day, typed in from the phone's own step counter (usually the morning after). */
export interface Steps { date: string; count: number; updatedAt: string; deleted: boolean; synced: 0 | 1 }
export interface Meta { key: string; value: string }

class HealthDB extends Dexie {
  weights!: Table<Weight, string>
  gaps!: Table<Gap, string>
  reasons!: Table<Reason, string>
  steps!: Table<Steps, string>
  meta!: Table<Meta, string>
  constructor() {
    super('healthtracker')
    this.version(1).stores({ weights: 'date, synced', gaps: 'date, synced', reasons: 'name, synced, lastUsed', meta: 'key' })
    this.version(2).stores({ steps: 'date, synced' })
  }
}
export const db = new HealthDB()

export async function getMeta(key: string) { return (await db.meta.get(key))?.value }
export async function setMeta(key: string, value: string) { await db.meta.put({ key, value }) }
export async function clearAllLocal() { await Promise.all([db.weights.clear(), db.gaps.clear(), db.reasons.clear(), db.steps.clear(), db.meta.clear()]) }

export const DEFAULT_STEPS_GOAL = 10000
export async function getStepsGoal() { const v = Number(await getMeta('stepsGoal')); return v > 0 ? v : DEFAULT_STEPS_GOAL }
