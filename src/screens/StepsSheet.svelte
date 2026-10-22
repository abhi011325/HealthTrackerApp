<script lang="ts">
  import { fmtDay, parse } from '../lib/dates'
  let { dates, onclose, onsave }: { dates: string[]; onclose: () => void; onsave: (entries: { date: string; count: number }[]) => void } = $props()

  // eslint-disable-next-line svelte/valid-compile
  let vals = $state<Record<string, string>>(Object.fromEntries($state.snapshot(dates).map(d => [d, ''])))
  const parseCount = (v: string) => parseInt((v || '').replace(/[^0-9]/g, ''), 10)
  function oninput(d: string, e: Event) { const digits = (e.target as HTMLInputElement).value.replace(/[^0-9]/g, '').slice(0, 5); vals[d] = digits ? Number(digits).toLocaleString('en-IN') : '' }
  function save() { const entries = dates.map(d => ({ date: d, count: parseCount(vals[d]) })).filter(e => e.count > 0 && e.count < 100000); if (entries.length) onsave(entries) }
</script>

<div class="fixed inset-0 z-20 bg-black/55 flex items-end" onclick={onclose} role="presentation">
  <div class="w-full max-w-md mx-auto bg-surface rounded-t-3xl px-5 pt-3 pb-10 max-h-[85vh] overflow-y-auto" onclick={e => e.stopPropagation()} role="dialog" aria-label="Missing steps" tabindex="-1">
    <div class="w-9 h-1 rounded bg-line mx-auto mb-4"></div>
    <h2 class="text-base font-semibold">Missing steps</h2>
    <p class="text-muted text-sm mb-4">{dates.length} {dates.length === 1 ? 'day' : 'days'} with no steps logged. The Health app still has them; fill in what you can.</p>

    {#each dates as d (d)}
      <div class="flex items-center gap-2.5 mb-2">
        <div class="w-[92px] shrink-0 text-[13px] text-ink-2">{fmtDay(parse(d))}</div>
        <input type="text" inputmode="numeric" pattern="[0-9]*" value={vals[d]} placeholder="steps" oninput={e => oninput(d, e)}
          class="flex-1 w-0 min-w-0 h-11 rounded-xl border border-line bg-surface-2 px-3 text-center text-lg font-semibold tnum outline-none focus:border-accent placeholder:text-sm placeholder:font-normal" />
      </div>
    {/each}

    <div class="flex gap-2 mt-4">
      <button type="button" class="h-12 px-4 rounded-2xl bg-surface-2 text-ink-2 font-semibold" onclick={onclose}>Not now</button>
      <button type="button" class="flex-1 h-12 rounded-2xl bg-accent text-white font-semibold" onclick={save}>Save</button>
    </div>
  </div>
</div>
