<script lang="ts">
  import type { Point } from '../lib/stats'
  import type { Gap } from '../lib/db'
  import { addDays, daysBetween, fmtDate, iso, parse, todayDate } from '../lib/dates'
  let { points, gaps, metric = 'weight', onmetric }: { points: Point[]; gaps: Gap[]; metric?: 'weight' | 'steps'; onmetric?: (m: 'weight' | 'steps') => void } = $props()

  let range = $state(28)
  let tip = $state<{ x: number; y: number; html: string } | null>(null)
  let svgEl = $state<SVGSVGElement | null>(null)
  const W = 350, H = 180, L = 36, R = 10, T = 10, B = 24

  const view = $derived.by(() => {
    const today = todayDate()
    const cutoff = range ? addDays(today, -range + 1) : null
    const s = cutoff ? points.filter(p => parse(p.date) >= cutoff) : points
    if (!s.length) return null
    const ys = s.flatMap(p => [p.kg, p.avg])
    const lo = Math.floor(Math.min(...ys) * 2) / 2 - 0.5, hi = Math.ceil(Math.max(...ys) * 2) / 2 + 0.5
    const first = parse(s[0].date)
    const x0 = cutoff && cutoff > first ? cutoff : first
    const span = Math.max(1, daysBetween(x0, today))
    const X = (d: string) => L + (daysBetween(x0, parse(d)) / span) * (W - L - R)
    const Y = (v: number) => T + ((hi - v) / (hi - lo)) * (H - T - B)
    const ticks = [0, 1, 2, 3, 4].map(i => lo + ((hi - lo) / 4) * i)
    const xt = [x0, addDays(x0, Math.round(span / 2)), today]
    let path = '', area = ''
    const segs: Point[][] = []
    s.forEach((p, i) => { const brk = i === 0 || daysBetween(parse(s[i - 1].date), parse(p.date)) > 3; if (brk) segs.push([]); segs[segs.length - 1].push(p); path += (brk ? 'M' : 'L') + X(p.date).toFixed(1) + ' ' + Y(p.avg).toFixed(1) + ' ' })
    for (const seg of segs) { if (seg.length < 2) continue; area += 'M' + X(seg[0].date).toFixed(1) + ' ' + (H - B) + ' ' + seg.map(p => 'L' + X(p.date).toFixed(1) + ' ' + Y(p.avg).toFixed(1)).join(' ') + ' L' + X(seg[seg.length - 1].date).toFixed(1) + ' ' + (H - B) + ' Z ' }
    // gap bands: consecutive days with the same reason
    const g = gaps.filter(x => !x.deleted && parse(x.date) >= x0).sort((a, b) => a.date.localeCompare(b.date))
    const bands: { xa: number; xb: number; label: string }[] = []
    let i = 0
    while (i < g.length) {
      let j = i
      while (j + 1 < g.length && daysBetween(parse(g[j].date), parse(g[j + 1].date)) === 1 && g[j + 1].reason === g[i].reason) j++
      bands.push({ xa: Math.max(L, X(g[i].date) - 6), xb: X(g[j].date) + 6, label: g[i].reason })
      i = j + 1
    }
    const cands = [...s.map(p => ({ date: p.date, p, gap: null as string | null })), ...g.map(x => ({ date: x.date, p: null as Point | null, gap: x.reason }))]
    return { s, X, Y, ticks, xt, path, area, bands, cands, hi, lo }
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
      : `${fmtDate(parse(best.date))}${best.p!.evening ? ' · evening' : ''}<br>Daily <b>${best.p!.kg.toFixed(1)}</b> · Avg <b>${best.p!.avg.toFixed(1)}</b>`
    const y = best.gap ? T + 40 : view.Y(Math.max(best.p!.kg, best.p!.avg))
    tip = { x: Math.min(Math.max((x / W) * r.width, 70), r.width - 70), y: (y / H) * r.height, html }
    crossX = x
  }
  let crossX = $state<number | null>(null)
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
    <svg bind:this={svgEl} viewBox="0 0 {W} {H}" class="w-full h-[180px] block touch-none cursor-crosshair" role="img" aria-label="Weight chart"
      onmousemove={move} onmouseleave={leave} ontouchstart={move} ontouchmove={move} ontouchend={leave}>
      {#each view.ticks as v (v)}
        <line x1={L} x2={W - R} y1={view.Y(v)} y2={view.Y(v)} stroke="#2b2b29" stroke-width="1" />
        <text x={L - 6} y={view.Y(v) + 4} text-anchor="end" fill="#8a897f" font-size="11" class="tnum">{v.toFixed(1)}</text>
      {/each}
      {#each view.bands as b (b.xa)}
        <rect x={b.xa} y={T} width={b.xb - b.xa} height={H - T - B} rx="4" fill="#fff" opacity="0.04" />
        {#if b.xb - b.xa >= 44}<text x={Math.min(Math.max((b.xa + b.xb) / 2, L + 30), W - R - 30)} y={T + 11} text-anchor="middle" fill="#8a897f" font-size="10">{b.label.length > 14 ? b.label.slice(0, 13) + '…' : b.label}</text>{/if}
      {/each}
      {#each view.xt as d, i (i)}
        <text x={view.X(iso(d))} y={H - 6} text-anchor={i === 0 ? 'start' : i === 2 ? 'end' : 'middle'} fill="#8a897f" font-size="11">{fmtDate(d)}</text>
      {/each}
      <defs><linearGradient id="avgfill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3987e5" stop-opacity=".28" /><stop offset="1" stop-color="#3987e5" stop-opacity="0" /></linearGradient></defs>
      <path d={view.area} fill="url(#avgfill)" />
      <path d={view.path} fill="none" stroke="#3987e5" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
      {#each view.s as p (p.date)}
        {#if p.evening}
          <circle cx={view.X(p.date)} cy={view.Y(p.kg)} r="4" fill="#242423" stroke="#86b6ef" stroke-width="2" />
        {:else}
          <circle cx={view.X(p.date)} cy={view.Y(p.kg)} r="4" fill="#86b6ef" stroke="#242423" stroke-width="2" />
        {/if}
      {/each}
      {#if crossX !== null}<line x1={crossX} x2={crossX} y1={T} y2={H - B} stroke="#8a897f" stroke-width="1" />{/if}
    </svg>
    {#if tip}
      <div class="absolute pointer-events-none bg-black text-ink border border-line rounded-xl px-2.5 py-1.5 text-xs leading-snug whitespace-nowrap -translate-x-1/2 -translate-y-[110%]" style="left:{tip.x + 10}px; top:{tip.y + 34}px">{@html tip.html}</div>
    {/if}
    <div class="flex gap-3.5 px-1.5 pt-1.5 text-[11px] text-muted">
      <span><i class="inline-block w-2 h-2 rounded-full bg-dot align-middle mr-1.5"></i>Morning</span>
      <span><i class="inline-block w-2 h-2 rounded-full border-2 border-dot align-middle mr-1.5"></i>Evening</span>
      <span><i class="inline-block w-3.5 h-0.5 bg-accent align-middle mr-1.5"></i>7-day average</span>
    </div>
  {:else}
    <p class="text-muted text-sm px-1.5 py-6 text-center">No entries in this range yet.</p>
  {/if}
</div>
