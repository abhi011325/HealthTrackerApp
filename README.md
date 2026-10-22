# HealthTracker

A phone-installable web app for daily weight and steps, each with a 7-day average. Local-first, syncs to Supabase, one account per family member.

## Run locally
```bash
cp .env.example .env.local   # fill in the Supabase URL and anon key
npm install
npm run dev
```

## One-time setup
1. Create a free Supabase project. In **SQL Editor**, run `supabase/schema.sql`. (A project set up before 2026-10-22 needs `supabase/2026-10-22-steps.sql` once, for the steps table.)
2. In **Authentication > Providers > Email**, turn **off** "Allow new users to sign up" (accounts are created by hand) and turn off "Confirm email".
3. Put the project URL, anon key and service-role key in `.env.local` (see `.env.example`).
4. Create an account: `scripts/create-user.sh "Name" email@example.com`. Hand the password over yourself. Reset one with `scripts/set-password.sh email@example.com`.

## Deploy
The site is GitHub Pages at `https://abhi011325.github.io/HealthTrackerApp/`, served from the `gh-pages` branch. Publish a new version with:
```bash
scripts/deploy.sh
```
It builds with the right base path and force-pushes `dist/` to `gh-pages`. (`deploy/github-pages.yml` is an optional Actions workflow for push-to-deploy; it needs a token with the `workflow` scope.)

## Install on a phone
- iPhone: open the address in Safari, Share, **Add to Home Screen**.
- Android: open it in Chrome, menu, **Install app**.

See `SPEC.md` for how the app behaves.
