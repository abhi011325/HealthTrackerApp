<script lang="ts">
  import { supabase } from '../lib/supabase'
  let email = $state(''), password = $state(''), error = $state(''), busy = $state(false)

  async function signIn(e: Event) {
    e.preventDefault(); if (!supabase || busy) return
    busy = true; error = ''
    const { error: err } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    if (err) error = err.message === 'Invalid login credentials' ? 'Wrong email or password.' : err.message
    busy = false
  }
</script>

<main class="min-h-screen flex flex-col justify-center px-6 pb-16 max-w-md mx-auto">
  <h1 class="text-3xl font-semibold mb-1">HealthTracker</h1>
  <p class="text-muted text-sm mb-6">Sign in to continue.</p>
  <form onsubmit={signIn}>
    <label class="block text-xs text-muted mb-1.5" for="email">Email</label>
    <input id="email" type="email" bind:value={email} autocomplete="username" inputmode="email" required
      class="w-full h-12 rounded-2xl border border-line bg-surface-2 px-4 text-base outline-none focus:border-accent" />
    <label class="block text-xs text-muted mb-1.5 mt-4" for="password">Password</label>
    <input id="password" type="password" bind:value={password} autocomplete="current-password" required
      class="w-full h-12 rounded-2xl border border-line bg-surface-2 px-4 text-base outline-none focus:border-accent" />
    {#if error}<p class="text-danger text-sm mt-3">{error}</p>{/if}
    <button type="submit" disabled={busy} class="w-full h-12 mt-6 rounded-2xl bg-accent text-white font-semibold disabled:opacity-60">{busy ? 'Signing in…' : 'Sign in'}</button>
  </form>
  <p class="text-xs text-muted mt-4 leading-relaxed">You stay signed in on this phone until you sign out.</p>
</main>
