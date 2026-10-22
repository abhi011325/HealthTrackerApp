# HealthTracker

A phone-installable web app for daily weight with a 7-day average. Local-first, syncs to Supabase, one account per family member.

## Run locally
```bash
cp .env.example .env.local   # fill in the Supabase URL and anon key
npm install
npm run dev
```

## One-time setup
1. Create a free Supabase project. In **SQL Editor**, run `supabase/schema.sql`.
2. In **Authentication > Providers > Email**, turn **off** "Allow new users to sign up" (accounts are created by hand) and turn off "Confirm email".
3. Put the project URL, anon key and service-role key in `.env.local` (see `.env.example`).
4. Create an account: `scripts/create-user.sh "Name" email@example.com`. Hand the password over yourself. Reset one with `scripts/set-password.sh email@example.com`.

## Deploy
Pushes to `main` build and publish to GitHub Pages via `deploy/github-pages.yml` (move it to `.github/workflows/` once hosting is decided; pushing it needs a token with the `workflow` scope). Set repository **Variables** `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (the anon key is safe to expose; row-level security protects the data).

## Install on a phone
- iPhone: open the address in Safari, Share, **Add to Home Screen**.
- Android: open it in Chrome, menu, **Install app**.

See `SPEC.md` for how the app behaves.
