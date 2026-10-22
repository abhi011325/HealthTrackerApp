<script lang="ts">
  import { onMount } from 'svelte'
  import type { Session } from '@supabase/supabase-js'
  import { supabase } from './lib/supabase'
  import { startAutoSync } from './lib/sync'
  import Login from './screens/Login.svelte'
  import Weight from './screens/Weight.svelte'

  let session = $state<Session | null>(null)
  let ready = $state(false)
  let name = $state('')

  onMount(() => {
    if (!supabase) { ready = true; return }
    supabase.auth.getSession().then(({ data }) => { session = data.session; ready = true })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => { session = s })
    return () => sub.subscription.unsubscribe()
  })

  $effect(() => {
    if (!session || !supabase) return
    name = (session.user.user_metadata?.name as string) || ''
    supabase.from('profiles').select('name').eq('id', session.user.id).maybeSingle().then(({ data }) => { if (data?.name) name = data.name })
    startAutoSync()
  })
</script>

{#if import.meta.env.DEV && import.meta.env.VITE_DEV_NOAUTH}
  <Weight name="Dev" email="dev@local" />
{:else if !supabase}
  <main class="min-h-screen flex items-center justify-center p-6 text-center text-ink-2">
    <p>This build has no database configured.<br />Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY and rebuild.</p>
  </main>
{:else if !ready}
  <main class="min-h-screen"></main>
{:else if !session}
  <Login />
{:else}
  <Weight {name} email={session.user.email ?? ''} />
{/if}
