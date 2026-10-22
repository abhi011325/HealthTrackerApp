<script lang="ts">
  import { supabase } from '../lib/supabase'
  import { exportJson, resetAll, setStepsGoal } from '../lib/store'
  import { getStepsGoal } from '../lib/db'
  let { email, onclose, onreset }: { email: string; onclose: () => void; onreset: () => void } = $props()
  let mode = $state<'menu' | 'password' | 'goal'>('menu')
  let pw1 = $state(''), pw2 = $state(''), msg = $state(''), busy = $state(false)
  let goal = $state(10000), goalInput = $state('')
  const fmtN = (n: number) => n.toLocaleString('en-IN')
  void getStepsGoal().then(g => { goal = g; goalInput = String(g) })

  async function saveGoal(e: Event) {
    e.preventDefault()
    const g = parseInt(goalInput.replace(/[^0-9]/g, ''), 10)
    if (!(g > 0 && g < 100000)) { msg = 'Enter a number of steps, like 10000.'; return }
    busy = true; await setStepsGoal(g); goal = g; busy = false
    msg = ''; mode = 'menu'
  }

  async function changePassword(e: Event) {
    e.preventDefault(); if (!supabase) return
    if (pw1.length < 8) { msg = 'At least 8 characters.'; return }
    if (pw1 !== pw2) { msg = 'The two entries differ.'; return }
    busy = true; const { error } = await supabase.auth.updateUser({ password: pw1 }); busy = false
    msg = error ? error.message : 'Password changed.'; if (!error) { pw1 = pw2 = ''; setTimeout(() => { mode = 'menu'; msg = '' }, 900) }
  }
  async function startFresh() {
    if (!confirm('Delete all your entries? This cannot be undone.')) return
    busy = true
    try { await resetAll(); onreset(); onclose() } catch (e) { msg = 'Could not reset: ' + (e as Error).message }
    busy = false
  }
  async function signOut() { await supabase?.auth.signOut() }
</script>

<div class="fixed inset-0 z-20 bg-black/55 flex items-end" onclick={onclose} role="presentation">
  <div class="w-full max-w-md mx-auto bg-surface rounded-t-3xl px-5 pt-3 pb-10" onclick={e => e.stopPropagation()} role="dialog" aria-label="Settings" tabindex="-1">
    <div class="w-9 h-1 rounded bg-line mx-auto mb-4"></div>
    {#if mode === 'menu'}
      <h2 class="text-base font-semibold">Settings</h2>
      <p class="text-muted text-sm mb-4">Signed in as {email}</p>
      <div class="flex flex-col gap-2">
        <button class="row" onclick={exportJson}><span>Backup</span><small>download your data</small></button>
        <button class="row" onclick={() => { goalInput = String(goal); mode = 'goal' }}><span>Steps goal</span><small>{fmtN(goal)} a day</small></button>
        <button class="row" onclick={() => (mode = 'password')}><span>Change password</span><small></small></button>
        <button class="row text-danger" disabled={busy} onclick={startFresh}><span>Start fresh</span><small>delete all my entries</small></button>
        <button class="row" onclick={signOut}><span>Sign out</span><small></small></button>
      </div>
      {#if msg}<p class="text-danger text-sm mt-3">{msg}</p>{/if}
      <button class="w-full h-12 mt-4 rounded-2xl bg-surface-2 text-ink-2 font-semibold" onclick={onclose}>Close</button>
    {:else if mode === 'goal'}
      <h2 class="text-base font-semibold mb-1">Steps goal</h2>
      <p class="text-muted text-sm mb-3">The dashed line on the steps chart. Change it whenever the plan changes.</p>
      <form onsubmit={saveGoal} class="flex flex-col gap-3">
        <input type="text" inputmode="numeric" pattern="[0-9]*" bind:value={goalInput} placeholder="10000" class="h-12 rounded-2xl border border-line bg-surface-2 px-4 text-center text-xl font-semibold tnum outline-none focus:border-accent" />
        {#if msg}<p class="text-sm text-danger">{msg}</p>{/if}
        <div class="flex gap-2 mt-1">
          <button type="button" class="h-12 px-4 rounded-2xl bg-surface-2 text-ink-2 font-semibold" onclick={() => { mode = 'menu'; msg = '' }}>Back</button>
          <button type="submit" disabled={busy} class="flex-1 h-12 rounded-2xl bg-accent text-white font-semibold">Save</button>
        </div>
      </form>
    {:else}
      <h2 class="text-base font-semibold mb-3">Change password</h2>
      <form onsubmit={changePassword} class="flex flex-col gap-3">
        <input type="password" bind:value={pw1} placeholder="New password" autocomplete="new-password" class="h-12 rounded-2xl border border-line bg-surface-2 px-4 outline-none focus:border-accent" />
        <input type="password" bind:value={pw2} placeholder="Repeat it" autocomplete="new-password" class="h-12 rounded-2xl border border-line bg-surface-2 px-4 outline-none focus:border-accent" />
        {#if msg}<p class="text-sm {msg === 'Password changed.' ? 'text-ok' : 'text-danger'}">{msg}</p>{/if}
        <div class="flex gap-2 mt-1">
          <button type="button" class="h-12 px-4 rounded-2xl bg-surface-2 text-ink-2 font-semibold" onclick={() => { mode = 'menu'; msg = '' }}>Back</button>
          <button type="submit" disabled={busy} class="flex-1 h-12 rounded-2xl bg-accent text-white font-semibold">Save</button>
        </div>
      </form>
    {/if}
  </div>
</div>

<style>
  .row { width: 100%; text-align: left; background: var(--color-surface-2); border-radius: 16px; padding: 14px 16px; font-size: 15px; display: flex; justify-content: space-between; align-items: center; }
  .row small { color: var(--color-muted); font-size: 12px; }
</style>
