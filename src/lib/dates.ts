/** Local calendar helpers. Dates are 'YYYY-MM-DD' strings in the phone's time zone. */
export const todayDate = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d }
export const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
export const parse = (s: string) => new Date(s + 'T00:00:00')
export const addDays = (d: Date, n: number) => { const x = new Date(d); x.setDate(x.getDate() + n); return x }
export const daysBetween = (a: Date, b: Date) => Math.round((b.getTime() - a.getTime()) / 86400000)
export const fmtDate = (d: Date) => d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })
export const fmtDay = (d: Date) => d.toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' })
export const isEveningNow = () => new Date().getHours() >= 12
