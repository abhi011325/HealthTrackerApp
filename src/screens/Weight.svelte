<script lang="ts">
  import { onMount } from 'svelte'
  import { liveQuery } from 'dexie'
  import { db, type Weight, type Gap, type Reason } from '../lib/db'
  import { series, summarize, streak } from '../lib/stats'
  import { fmtDate, fmtDay, parse, todayDate, isEveningNow } from '../lib/dates'
  import { saveToday, saveGapReasons } from '../lib/store'
  import { onSync, sync, type SyncState } from '../lib/sync'
  import Trend from './Trend.svelte'
  import ReasonSheet from './ReasonSheet.svelte'
  import Settings from './Settings.svelte'

  let { name, email }: { name: string; email: string } = $props()

  let weights = $state<Weight[]>([]), gaps = $state<Gap[]>([]), reasons = $state<Reason[]>([])
  let syncState = $state<SyncState>('synced'), pending = $state(0)
  let trendOpen = $state(false), sheet = $state<'none' | 'reason' | 'settings'>('none')
  let input = $state(''), savedMsg = $state(''), prefilled = $state(false)

  const sum = $derived(summarize(weights, gaps))
  const days = $derived(streak(weights))
  const hour = new Date().getHours()
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'
  let popKey = $state(0)
  const points = $derived(series(weights))
  const liveReasons = $derived(reasons.filter(r => !r.deleted).sort((a, b) => b.lastUsed.localeCompare(a.lastUsed)))
  const todayLabel = todayDate().toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' })
  const fmt = (n: number) => n.toFixed(1)
  const signed = (n: number) => (n > 0 ? '+' : '') + n.toFixed(1)

  onMount(() => {
    const subs = [
      liveQuery(() => db.weights.toArray()).subscribe(v => { weights = v.filter(w => !w.deleted) }),
      liveQuery(() => db.gaps.toArray()).subscribe(v => { gaps = v.filter(g => !g.deleted) }),
      liveQuery(() => db.reasons.toArray()).subscribe(v => { reasons = v }),
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

  <section class="grid grid-cols-2 gap-2.5 mt-2.5">
    <div class="card rounded-2xl px-3.5 py-3">
      <div class="text-xs text-muted">This week vs last</div>
      <div class="text-xl font-semibold mt-0.5 tnum {sum.weekDelta !== null && sum.weekDelta < 0 ? 'text-ok' : ''}">{#if sum.weekDelta === null}—<span class="text-[13px] font-medium text-ink-2 ml-1">not enough entries</span>{:else}{signed(sum.weekDelta)}<span class="text-[13px] font-medium text-ink-2 ml-1">kg</span>{/if}</div>
    </div>
    <div class="card rounded-2xl px-3.5 py-3">
      <div class="text-xs text-muted">Since start{#if sum.startDate}&nbsp;· {fmtDate(parse(sum.startDate))}{/if}</div>
      <div class="text-xl font-semibold mt-0.5 tnum {sum.sinceStart !== null && sum.sinceStart < 0 ? 'text-ok' : ''}">{#if sum.sinceStart === null}—{:else}{signed(sum.sinceStart)}<span class="text-[13px] font-medium text-ink-2 ml-1">kg</span>{/if}</div>
    </div>
  </section>

  <section class="card rounded-2xl mt-2.5">
    <button class="w-full flex justify-between items-center px-3.5 py-3.5 text-sm text-ink-2" onclick={() => (trendOpen = !trendOpen)}>
      <span>{trendOpen ? 'Hide trend' : 'Show trend'}</span><span class="text-muted transition-transform {trendOpen ? 'rotate-90' : ''}">›</span>
    </button>
    {#if trendOpen}<Trend {points} {gaps} />{/if}
  </section>
</main>

{#if sheet === 'reason'}
  <ReasonSheet dates={sum.missed} reasons={liveReasons} onclose={() => (sheet = 'none')} onsave={onReasons} />
{:else if sheet === 'settings'}
  <Settings {email} onclose={() => (sheet = 'none')} onreset={() => { input = ''; prefilled = false }} />
{/if}

<style>
  .row { display: flex; justify-content: space-between; align-items: center; padding: 11px 14px; }
  .row + .row { border-top: 1px solid var(--color-line); }
</style>
