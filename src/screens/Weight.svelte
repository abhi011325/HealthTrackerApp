<script lang="ts">
  import { onMount } from 'svelte'
  import { liveQuery } from 'dexie'
  import { db, getStepsGoal, DEFAULT_STEPS_GOAL, type Weight, type Gap, type Reason, type Steps } from '../lib/db'
  import { series, summarize, streak, stepSeries, summarizeSteps } from '../lib/stats'
  import { addDays, fmtDate, fmtDay, iso, parse, todayDate, isEveningNow } from '../lib/dates'
  import { saveToday, saveGapReasons, saveSteps } from '../lib/store'
  import { onSync, sync, type SyncState } from '../lib/sync'
  import Trend from './Trend.svelte'
  import StepsTrend from './StepsTrend.svelte'
  import ReasonSheet from './ReasonSheet.svelte'
  import StepsSheet from './StepsSheet.svelte'
  import Settings from './Settings.svelte'

  let { name, email }: { name: string; email: string } = $props()

  let weights = $state<Weight[]>([]), gaps = $state<Gap[]>([]), reasons = $state<Reason[]>([]), steps = $state<Steps[]>([])
  let stepsGoal = $state(DEFAULT_STEPS_GOAL), metric = $state<'weight' | 'steps'>('weight')
  let stepInput = $state(''), stepsMsg = $state('')
  let syncState = $state<SyncState>('synced'), pending = $state(0)
  let trendOpen = $state(false), sheet = $state<'none' | 'reason' | 'steps' | 'settings'>('none')
  let input = $state(''), savedMsg = $state(''), prefilled = $state(false)

  const sum = $derived(summarize(weights, gaps))
  const days = $derived(streak(weights))
  const hour = new Date().getHours()
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'
  let popKey = $state(0)
  const points = $derived(series(weights))
  const stepPoints = $derived(stepSeries(steps))
  const st = $derived(summarizeSteps(steps))
  const stepsByDate = $derived(new Map(steps.map(x => [x.date, x.count])))
  const fmtN = (n: number) => Math.round(n).toLocaleString('en-IN')
  const yesterday = iso(addDays(todayDate(), -1))
  const liveReasons = $derived(reasons.filter(r => !r.deleted).sort((a, b) => b.lastUsed.localeCompare(a.lastUsed)))
  const todayLabel = todayDate().toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' })
  const fmt = (n: number) => n.toFixed(1)
  const signed = (n: number) => (n > 0 ? '+' : '') + n.toFixed(1)

  onMount(() => {
    const subs = [
      liveQuery(() => db.weights.toArray()).subscribe(v => { weights = v.filter(w => !w.deleted) }),
      liveQuery(() => db.gaps.toArray()).subscribe(v => { gaps = v.filter(g => !g.deleted) }),
      liveQuery(() => db.reasons.toArray()).subscribe(v => { reasons = v }),
      liveQuery(() => db.steps.toArray()).subscribe(v => { steps = v.filter(x => !x.deleted) }),
      liveQuery(() => db.meta.get('stepsGoal')).subscribe(() => { void getStepsGoal().then(g => (stepsGoal = g)) }),
    ]
    const off = onSync((s, n) => { syncState = s; pending = n })
    return () => { subs.forEach(s => s.unsubscribe()); off() }
  })

  // Pre-fill once with today's entry, else the last reading.
  $effect(() => { if (!prefilled && (sum.today || sum.last)) { input = fmt((sum.today ?? sum.last)!.kg); prefilled = true } })

  function step(d: number) { input = fmt((parseFloat(input) || 0) + d) }
  async function save() {
    const v = parseFloat(input); if (!(v > 20 && v < 400)) return
    await saveToday(v)
    popKey++; burst()
    savedMsg = `Logged ${fmt(v)} kg. Nice.`; setTimeout(() => (savedMsg = ''), 2500)
  }
  function burst() {
    const colors = ['#3987e5', '#86b6ef', '#e8b14a', '#199e70', '#f0efec']
    for (let i = 0; i < 22; i++) {
      const el = document.createElement('i'); el.className = 'confetti'
      el.style.background = colors[i % colors.length]; el.style.setProperty('--dx', `${(Math.random() - 0.5) * 260}px`)
      el.style.left = `${35 + Math.random() * 30}%`; el.style.animationDelay = `${Math.random() * 120}ms`
      document.body.appendChild(el); setTimeout(() => el.remove(), 1100)
    }
  }
  async function onReasons(entries: { date: string; reason: string }[]) { await saveGapReasons(entries); sheet = 'none' }

  function onStepInput(e: Event) {
    const digits = (e.target as HTMLInputElement).value.replace(/[^0-9]/g, '').slice(0, 5)
    stepInput = digits ? Number(digits).toLocaleString('en-IN') : ''
  }
  async function saveYesterdaySteps() {
    const count = parseInt(stepInput.replace(/[^0-9]/g, ''), 10)
    if (!(count > 0 && count < 100000)) return
    await saveSteps([{ date: yesterday, count }])
    stepInput = ''
    stepsMsg = `Saved ${fmtN(count)} steps for yesterday`; setTimeout(() => (stepsMsg = ''), 3000)
  }
  async function onMissingSteps(entries: { date: string; count: number }[]) {
    await saveSteps(entries); sheet = 'none'
    stepsMsg = 'Saved ' + entries.map(e => `${fmtN(e.count)} for ${fmtDate(parse(e.date))}`).join(' · '); setTimeout(() => (stepsMsg = ''), 4000)
  }
</script>

<main class="min-h-screen max-w-md mx-auto px-5 pt-[max(14px,env(safe-area-inset-top))] pb-10 flex flex-col">
  <header class="flex justify-between items-center mb-3.5">
    <h1 class="text-[17px] font-semibold">{greeting}{name ? `, ${name}` : ''}</h1>
    <div class="flex items-center gap-2.5 text-[13px] text-muted">
      <button class="inline-flex items-center gap-1.5 text-[11px]" onclick={() => void sync()} title="Tap to sync now">
        <i class="w-[7px] h-[7px] rounded-full {syncState === 'synced' ? 'bg-ok' : syncState === 'error' ? 'bg-danger' : 'bg-warn'}"></i>
        {syncState === 'synced' ? 'synced' : syncState === 'syncing' ? 'syncing' : syncState === 'offline' ? `offline · ${pending} waiting` : syncState === 'error' ? `${pending} waiting` : `${pending} waiting`}
      </button>
      <span>{todayLabel}</span>
      <button class="w-[30px] h-[30px] rounded-full bg-surface-2 text-ink-2" onclick={() => (sheet = 'settings')} aria-label="Settings">⚙</button>
    </div>
  </header>

  <section class="text-center mt-1.5 hero-glow">
    <div class="relative text-xs text-muted uppercase tracking-[.8px]">7-day average</div>
    {#key popKey}
    <div class="relative pop text-[66px] font-semibold leading-[1.05] tracking-[-1.5px] tnum {sum.avgBuilding ? 'text-muted' : ''}">
      {sum.avg === null ? '–' : fmt(sum.avg)}<small class="text-[22px] font-medium text-ink-2 tracking-normal ml-1">kg</small>
    </div>
    {/key}
    {#if days >= 2}
      <div class="relative inline-flex items-center gap-1.5 mt-2 px-3 py-1 rounded-full text-xs font-medium chip">🔥 {days}-day streak</div>
    {:else if sum.last && !sum.today}
      <div class="relative inline-flex items-center gap-1.5 mt-2 px-3 py-1 rounded-full text-xs text-muted bg-surface-2">Log today to start a streak</div>
    {/if}
  </section>

  <section class="card rounded-2xl mt-3.5 overflow-hidden text-sm">
    {#if !sum.last}
      <div class="row"><span class="text-muted">Today</span><span class="text-ink-2">no entries yet, log your first weight below</span></div>
    {:else if sum.today}
      <div class="row"><span class="text-muted">Today</span><span class="tnum">{fmt(sum.today.kg)} kg{#if sum.today.evening}<span class="text-ink-2">&nbsp;· evening</span>{/if}</span></div>
    {:else}
      <div class="row"><span class="text-muted">Today</span><span class="text-ink-2">no entry yet</span></div>
      <div class="row"><span class="text-muted">Last entry</span><span class="tnum">{sum.gapDays === 1 ? 'Yesterday' : fmtDay(parse(sum.last.date))}<span class="text-ink-2">&nbsp;· {fmt(sum.last.kg)} kg</span></span></div>
    {/if}
    {#if sum.missed.length}
      <div class="row"><span class="text-muted">{sum.missed.length} {sum.missed.length > 1 ? 'days' : 'day'} missed</span><button class="text-accent font-medium" onclick={() => (sheet = 'reason')}>Add reason ›</button></div>
    {/if}
    {#if sum.avgBuilding}
      <div class="row"><span class="text-muted">Average</span><span class="text-ink-2">building, {sum.avgBuilding} of 7</span></div>
    {/if}
  </section>

  <section class="card rounded-2xl mt-2.5 p-3.5">
    <div class="flex justify-between text-xs text-muted mb-2"><span>Today's weight</span><span>{isEveningNow() ? 'will be marked as evening' : ''}</span></div>
    <div class="flex items-center gap-2">
      <div class="flex items-center gap-1.5 flex-1">
        <button class="shrink-0 w-11 h-12 rounded-2xl bg-surface text-2xl active:bg-surface-3" onclick={() => step(-0.1)} aria-label="minus 0.1">−</button>
        <input type="number" step="0.1" inputmode="decimal" bind:value={input} onkeydown={e => e.key === 'Enter' && save()}
          class="flex-1 w-0 min-w-0 h-12 text-center text-[28px] font-semibold bg-surface border border-line rounded-2xl tnum outline-none focus:border-accent" />
        <button class="shrink-0 w-11 h-12 rounded-2xl bg-surface text-2xl active:bg-surface-3" onclick={() => step(0.1)} aria-label="plus 0.1">+</button>
      </div>
      <button class="shrink-0 h-12 px-5 rounded-2xl bg-accent text-white font-semibold text-[15px] shadow-[0_6px_20px_rgba(57,135,229,.35)] active:scale-95 transition-transform" onclick={save}>Save</button>
    </div>
    <div class="text-xs text-muted mt-2 text-right min-h-[14px]">{savedMsg}</div>
  </section>

  <section class="card rounded-2xl mt-2.5 p-3.5">
    <div class="flex justify-between text-xs text-muted mb-2"><span>Steps</span><span>from the Health app</span></div>
    <div class="flex items-center gap-2">
      <div class="shrink-0 w-[118px] text-sm text-ink-2 leading-tight">
        Yesterday
        <small class="block text-[11px] text-muted">{fmtDate(parse(yesterday))}{stepsByDate.has(yesterday) ? ` · saved ${fmtN(stepsByDate.get(yesterday)!)}` : ''}</small>
      </div>
      <input type="text" inputmode="numeric" pattern="[0-9]*" placeholder="steps" value={stepInput} oninput={onStepInput} onkeydown={e => e.key === 'Enter' && saveYesterdaySteps()}
        class="flex-1 w-0 min-w-0 h-12 text-center text-[22px] font-semibold bg-surface border border-line rounded-2xl tnum outline-none focus:border-accent placeholder:text-sm placeholder:font-normal" />
      <button class="shrink-0 h-12 px-5 rounded-2xl bg-accent text-white font-semibold text-[15px] shadow-[0_6px_20px_rgba(57,135,229,.35)] active:scale-95 transition-transform" onclick={saveYesterdaySteps}>Save</button>
    </div>
    <div class="flex justify-between items-center text-xs mt-2 min-h-[14px]">
      {#if st.missed.length}<button class="text-accent font-medium" onclick={() => (sheet = 'steps')}>{st.missed.length} {st.missed.length > 1 ? 'days' : 'day'} missing · Add ›</button>{:else}<span></span>{/if}
      <span class="text-muted text-right">{stepsMsg}</span>
    </div>
  </section>

  <section class="grid grid-cols-2 gap-2.5 mt-2.5">
    <div class="card rounded-2xl px-3.5 py-3">
      <div class="text-xs text-muted">This week vs last</div>
      <div class="text-xl font-semibold mt-0.5 tnum {sum.weekDelta !== null && sum.weekDelta < 0 ? 'text-ok' : ''}">{#if sum.weekDelta === null}—<span class="text-[13px] font-medium text-ink-2 ml-1">not enough entries</span>{:else}{signed(sum.weekDelta)}<span class="text-[13px] font-medium text-ink-2 ml-1">kg</span>{/if}</div>
    </div>
    <div class="card rounded-2xl px-3.5 py-3">
      <div class="text-xs text-muted">Since start{#if sum.startDate}&nbsp;· {fmtDate(parse(sum.startDate))}{/if}</div>
      <div class="text-xl font-semibold mt-0.5 tnum {sum.sinceStart !== null && sum.sinceStart < 0 ? 'text-ok' : ''}">{#if sum.sinceStart === null}—{:else}{signed(sum.sinceStart)}<span class="text-[13px] font-medium text-ink-2 ml-1">kg</span>{/if}</div>
    </div>
    <div class="card rounded-2xl px-3.5 py-3 col-span-2 flex justify-between items-center">
      <div>
        <div class="text-xs text-muted">Steps · 7-day average</div>
        <div class="text-xl font-semibold tnum">{#if st.avg === null}—<span class="text-[13px] font-medium text-ink-2 ml-1">{st.n ? `building, ${st.n} of 7` : 'no steps yet'}</span>{:else}{fmtN(st.avg)}<span class="text-[13px] font-medium text-ink-2 ml-1">{st.n} of 7 days</span>{/if}</div>
      </div>
      <div class="text-right text-[13px] tnum {st.weekDelta === null ? 'text-ink-2' : st.weekDelta < 0 ? 'text-danger' : 'text-ok'}">
        {#if st.weekDelta !== null}{st.weekDelta < 0 ? '−' : '+'}{fmtN(Math.abs(st.weekDelta))}<small class="block text-[11px] text-muted">vs last week</small>{:else}<small class="block text-[11px] text-muted">goal {fmtN(stepsGoal)}</small>{/if}
      </div>
    </div>
  </section>

  <section class="card rounded-2xl mt-2.5">
    <button class="w-full flex justify-between items-center px-3.5 py-3.5 text-sm text-ink-2" onclick={() => (trendOpen = !trendOpen)}>
      <span>{trendOpen ? 'Hide trend' : 'Show trend'}</span><span class="text-muted transition-transform {trendOpen ? 'rotate-90' : ''}">›</span>
    </button>
    {#if trendOpen}
      {#if metric === 'weight'}<Trend {points} {gaps} {metric} onmetric={m => (metric = m)} />{:else}<StepsTrend points={stepPoints} {gaps} goal={stepsGoal} {metric} onmetric={m => (metric = m)} />{/if}
    {/if}
  </section>
</main>

{#if sheet === 'reason'}
  <ReasonSheet dates={sum.missed} reasons={liveReasons} onclose={() => (sheet = 'none')} onsave={onReasons} />
{:else if sheet === 'steps'}
  <StepsSheet dates={st.missed} onclose={() => (sheet = 'none')} onsave={onMissingSteps} />
{:else if sheet === 'settings'}
  <Settings {email} onclose={() => (sheet = 'none')} onreset={() => { input = ''; prefilled = false }} />
{/if}

<style>
  .row { display: flex; justify-content: space-between; align-items: center; padding: 11px 14px; }
  .row + .row { border-top: 1px solid var(--color-line); }
</style>
