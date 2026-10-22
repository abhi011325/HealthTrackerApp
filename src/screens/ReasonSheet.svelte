<script lang="ts">
  import { fmtDay, parse } from '../lib/dates'
  import type { Reason } from '../lib/db'
  let { dates, reasons, onclose, onsave }: { dates: string[]; reasons: Reason[]; onclose: () => void; onsave: (entries: { date: string; reason: string }[]) => void } = $props()

  // eslint-disable-next-line svelte/valid-compile
  let vals = $state<Record<string, string>>(Object.fromEntries($state.snapshot(dates).map(d => [d, ''])))
  let active = $state<string | null>(null)

  const first = $derived(dates[0])
  const showSameAll = $derived(!!vals[first] && dates.length > 1 && dates.slice(1).some(d => vals[d] !== vals[first]))
  const suggestions = (q: string) => { const ql = q.trim().toLowerCase(); return reasons.map(r => r.name).filter(n => n.toLowerCase().includes(ql)) }
  const isNew = (q: string) => q.trim() && !reasons.some(r => r.name.toLowerCase() === q.trim().toLowerCase())

  function pick(d: string, r: string) { vals[d] = r; active = null }
  function sameForAll() { for (const d of dates) vals[d] = vals[first] }
  function save() { const entries = dates.filter(d => vals[d].trim()).map(d => ({ date: d, reason: vals[d].trim() })); if (entries.length) onsave(entries) }
</script>

<div class="fixed inset-0 z-20 bg-black/55 flex items-end" onclick={onclose} role="presentation">
  <div class="w-full max-w-md mx-auto bg-surface rounded-t-3xl px-5 pt-3 pb-10 max-h-[85vh] overflow-y-auto" onclick={e => e.stopPropagation()} role="dialog" aria-label="Missed days" tabindex="-1">
    <div class="w-9 h-1 rounded bg-line mx-auto mb-4"></div>
    <h2 class="text-base font-semibold">Missed days</h2>
    <p class="text-muted text-sm mb-4">{dates.length} {dates.length === 1 ? 'day' : 'days'} with no weight logged. One reason per day.</p>

    {#each dates as d, i (d)}
      <div class="flex items-center gap-2.5 mb-2">
        <div class="w-[92px] shrink-0 text-[13px] text-ink-2">{fmtDay(parse(d))}</div>
        <div class="relative flex-1">
          <input value={vals[d]} placeholder={reasons.length ? 'Type or pick' : 'Type a reason'} autocomplete="off"
            oninput={e => (vals[d] = (e.target as HTMLInputElement).value)}
            onfocus={() => (active = d)} onblur={() => setTimeout(() => { if (active === d) active = null }, 150)}
            class="w-full h-11 rounded-xl border border-line bg-surface-2 px-3 text-[15px] outline-none focus:border-accent" />
          {#if active === d && (suggestions(vals[d]).length || isNew(vals[d]))}
            <ul class="absolute left-0 right-0 z-10 mt-1.5 p-1 bg-surface-2 border border-line rounded-xl max-h-44 overflow-auto">
              {#each suggestions(vals[d]) as r (r)}
                <li><button type="button" class="w-full text-left px-2.5 py-2.5 rounded-lg text-sm text-ink-2 hover:bg-surface-3 hover:text-ink" onmousedown={() => pick(d, r)}>{r}</button></li>
              {/each}
              {#if isNew(vals[d])}
                <li><button type="button" class="w-full text-left px-2.5 py-2.5 rounded-lg text-sm text-accent hover:bg-surface-3" onmousedown={() => pick(d, vals[d].trim())}>Add “{vals[d].trim()}”</button></li>
              {/if}
            </ul>
          {/if}
        </div>
      </div>
      {#if i === 0 && showSameAll}
        <button type="button" class="text-xs text-accent mb-2.5 ml-[102px]" onclick={sameForAll}>Use this for all days</button>
      {/if}
    {/each}

    <div class="flex gap-2 mt-4">
      <button type="button" class="h-12 px-4 rounded-2xl bg-surface-2 text-ink-2 font-semibold" onclick={onclose}>Not now</button>
      <button type="button" class="flex-1 h-12 rounded-2xl bg-accent text-white font-semibold" onclick={save}>Save</button>
    </div>
  </div>
</div>
