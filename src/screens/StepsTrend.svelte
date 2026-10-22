<script lang="ts">
  import type { StepPoint } from '../lib/stats'
  import type { Gap } from '../lib/db'
  import { addDays, daysBetween, fmtDate, iso, parse, todayDate } from '../lib/dates'
  let { points, gaps, goal, metric = 'steps', onmetric }: { points: StepPoint[]; gaps: Gap[]; goal: number; metric?: 'weight' | 'steps'; onmetric?: (m: 'weight' | 'steps') => void } = $props()

  let range = $state(28)
  let tip = $state<{ x: number; y: number; html: string } | null>(null)
  let crossX = $state<number | null>(null)
  let svgEl = $state<SVGSVGElement | null>(null)
  const W = 350, H = 180, L = 40, R = 10, T = 10, B = 24
  const fmtN = (n: number) => Math.round(n).toLocaleString('en-IN')

  const view = $derived.by(() => {
    const today = todayDate()
    const cutoff = range ? addDays(today, -range + 1) : null
    const s = cutoff ? points.filter(p => parse(p.date) >= cutoff) : points
    if (!s.length) return null
    const hi = Math.ceil(Math.max(goal, ...s.map(p => p.count)) / 5000) * 5000
    const first = parse(s[0].date)
    const x0 = cutoff && cutoff > first ? cutoff : first
    const span = Math.max(1, daysBetween(x0, today))
    const X = (d: string) => L + (daysBetween(x0, parse(d)) / span) * (W - L - R)
    const Y = (v: number) => T + ((hi - v) / hi) * (H - T - B)
    const ticks: number[] = []; for (let v = 0; v <= hi; v += 5000) ticks.push(v)
    const xt = [x0, addDays(x0, Math.round(span / 2)), today]
    const bw = Math.max(2, Math.min(10, ((W - L - R) / span) * 0.7))
    let path = ''
    s.forEach((p, i) => { const brk = i === 0 || daysBetween(parse(s[i - 1].date), parse(p.date)) > 3; path += (brk ? 'M' : 'L') + X(p.date).toFixed(1) + ' ' + Y(p.avg).toFixed(1) + ' ' })
    const g = gaps.filter(x => !x.deleted && parse(x.date) >= x0).sort((a, b) => a.date.localeCompare(b.date))
    const bands: { xa: number; xb: number }[] = []
    let i = 0
    while (i < g.length) {
      let j = i
      while (j + 1 < g.length && daysBetween(parse(g[j].date), parse(g[j + 1].date)) === 1 && g[j + 1].reason === g[i].reason) j++
      bands.push({ xa: Math.max(L, X(g[i].date) - 6), xb: X(g[j].date) + 6 })
      i = j + 1
    }
    const have = new Set(s.map(p => p.date))
    const cands = [...s.map(p => ({ date: p.date, p, gap: null as string | null })), ...g.filter(x => !have.has(x.date)).map(x => ({ date: x.date, p: null as StepPoint | null, gap: x.reason }))]
    return { s, X, Y, ticks, xt, path, bands, cands, hi, bw }
  })

  function move(e: MouseEvent | TouchEvent) {
    if (!view || !svgEl) return
    const r = svgEl.getBoundingClientRect()
    const cx = 'touches' in e ? e.touches[0].clientX : e.clientX
    const px = ((cx - r.left) / r.width) * W
    let best = view.cands[0], bd = 1e9
    for (const c of view.cands) { const d = Math.abs(view.X(c.date) - px); if (d < bd) { bd = d; best = c } }
    const x = view.X(best.date)
    const html = best.gap
      ? `${fmtDate(parse(best.date))}<br>No entry · <b>${best.gap}</b>`
      : `${fmtDate(parse(best.date))}<br>Steps <b>${fmtN(best.p!.count)}</b> · Avg <b>${fmtN(best.p!.avg)}</b>`
    const y = best.gap ? T + 40 : view.Y(Math.max(best.p!.count, best.p!.avg))
    tip = { x: Math.min(Math.max((x / W) * r.width, 70), r.width - 70), y: (y / H) * r.height, html }
    crossX = x
  }
  const leave = () => { tip = null; crossX = null }
</script>

<div class="relative px-2.5 pb-2">
  <div class="flex justify-between pb-1 px-1">
    <div class="inline-flex bg-surface rounded-lg p-0.5">
      {#each [['weight', 'Weight'], ['steps', 'Steps']] as [m, label] (m)}
        <button class="text-xs px-2.5 py-1 rounded-md {metric === m ? 'bg-surface-3 text-ink' : 'text-muted'}" onclick={() => onmetric?.(m as 'weight' | 'steps')}>{label}</button>
      {/each}
    </div>
    <div class="inline-flex bg-surface rounded-lg p-0.5">
      {#each [[28, '4w'], [84, '12w'], [0, 'All']] as [r, label] (r)}
        <button class="text-xs px-2.5 py-1 rounded-md {range === r ? 'bg-surface-3 text-ink' : 'text-muted'}" onclick={() => (range = r as number)}>{label}</button>
      {/each}
    </div>
  </div>
  {#if view}
    <svg bind:this={svgEl} viewBox="0 0 {W} {H}" class="w-full h-[180px] block touch-none cursor-crosshair" role="img" aria-label="Steps chart"
      onmousemove={move} onmouseleave={leave} ontouchstart={move} ontouchmove={move} ontouchend={leave}>
      {#each view.ticks as v (v)}
        <line x1={L} x2={W - R} y1={view.Y(v)} y2={view.Y(v)} stroke="#2b2b29" stroke-width="1" />
        <text x={L - 6} y={view.Y(v) + 4} text-anchor="end" fill="#8a897f" font-size="11" class="tnum">{v >= 1000 ? v / 1000 + 'k' : v}</text>
      {/each}
      {#each view.bands as b (b.xa)}
        <rect x={b.xa} y={T} width={b.xb - b.xa} height={H - T - B} rx="4" fill="#fff" opacity="0.04" />
      {/each}
      {#each view.xt as d, i (i)}
        <text x={view.X(iso(d))} y={H - 6} text-anchor={i === 0 ? 'start' : i === 2 ? 'end' : 'middle'} fill="#8a897f" font-size="11">{fmtDate(d)}</text>
      {/each}
      {#each view.s as p (p.date)}
        <rect x={(view.X(p.date) - view.bw / 2).toFixed(1)} y={view.Y(p.count).toFixed(1)} width={view.bw.toFixed(1)} height={(view.Y(0) - view.Y(p.count)).toFixed(1)} rx="1.5" fill="#86b6ef" opacity={p.count >= goal ? 0.9 : 0.5} />
      {/each}
      <line x1={L} x2={W - R} y1={view.Y(goal)} y2={view.Y(goal)} stroke="#8a897f" stroke-width="1" stroke-dasharray="4 4" />
      <text x={W - R} y={view.Y(goal) - 4} text-anchor="end" fill="#8a897f" font-size="10">goal {fmtN(goal)}</text>
      <path d={view.path} fill="none" stroke="#3987e5" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
      {#if crossX !== null}<line x1={crossX} x2={crossX} y1={T} y2={H - B} stroke="#8a897f" stroke-width="1" />{/if}
    </svg>
    {#if tip}
      <div class="absolute pointer-events-none bg-black text-ink border border-line rounded-xl px-2.5 py-1.5 text-xs leading-snug whitespace-nowrap -translate-x-1/2 -translate-y-[110%]" style="left:{tip.x + 10}px; top:{tip.y + 34}px">{@html tip.html}</div>
    {/if}
    <div class="flex gap-3.5 px-1.5 pt-1.5 text-[11px] text-muted">
      <span><i class="inline-block w-2 h-2.5 bg-dot opacity-70 align-middle mr-1.5 rounded-[1px]"></i>Daily</span>
      <span><i class="inline-block w-3.5 h-0.5 bg-accent align-middle mr-1.5"></i>7-day average</span>
      <span><i class="inline-block w-3.5 border-t border-dashed border-muted align-middle mr-1.5"></i>Goal</span>
    </div>
  {:else}
    <p class="text-muted text-sm px-1.5 py-6 text-center">No steps in this range yet.</p>
  {/if}
</div>
