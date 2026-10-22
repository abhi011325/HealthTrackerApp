# HealthTracker — build spec (v1: weight, v1.1: steps, v1.2: earned day)

Agreed with Abhishek on 2026-10-22 from the mockup in `HealthTracker/mockups/weight-screen.html`.

## Purpose
One screen a day, under 20 seconds: log the morning weight, see the 7-day average, know at a glance when the last entry was. Family members each get their own account and see only their own data. More features (meals, lifts, sleep, steps, Sunday review) come later on the same base.

## Stack
- Svelte 5 + TypeScript + Vite, Tailwind 4, dark only.
- PWA (`vite-plugin-pwa`): installable on iPhone (Safari > Add to Home Screen) and Android (Chrome > Install), works offline, auto-updates on next open.
- Data on the phone in IndexedDB (Dexie). Source of record is Supabase (Postgres) with row-level security.
- Hosting: static files on GitHub Pages (`gh-pages` branch, public repo), published with `scripts/deploy.sh`.
- No paid services. The only secret is the Supabase service-role key, kept in `.env.local` on the Mac for the account scripts; the app ships only the public anon key.

## Accounts
- Email + password. No self sign-up (switched off in Supabase). Accounts are created by `scripts/create-user.sh`, which generates a 14-character password; Abhishek hands it over himself. `scripts/set-password.sh` resets one.
- Session persists on the device until Sign out. Change password in Settings.
- A `profiles` row (name) is created by trigger for every account; the name is shown as "Hi <name>".

## Screen: Weight
1. **Header**: "Hi <name>", sync dot (green synced / amber waiting or offline with count / red error; tap = sync now), today's date, settings gear.
2. **Hero**: 7-day average, big. Grey when fewer than 3 readings in the last 7 calendar days (then shows the last known average with a "building, n of 7" row).
3. **Status card** (one line per fact): `Today <kg> [· evening]` or `Today no entry yet` + `Last entry <day> · <kg>`; `<n> days missed · Add reason ›` only when there are unexplained gaps; `Average building, n of 7` when applicable.
4. **Entry**: number pre-filled with today's entry or the last reading, −/+ in 0.1 kg steps, Save. One entry per day; saving again replaces. Saved after 12:00 local = marked `evening`. Hint shown when it will be. No date picker.
5. **Tiles**: *This week vs last* = mean(readings in last 7 days) − mean(readings in the 7 before); dash with "not enough entries" unless both sides have ≥3 readings. *Since start* = current average − first reading.
6. **Trend** (collapsed, "Show trend"): daily dots (hollow = evening), 7-day average line broken on gaps > 3 days, 4w/12w/All, y-axis clean 0.5 steps, x ticks first/middle/last. Gap bands shaded; label only when wide enough; touch/hover tooltip gives the day's daily + average, or the gap reason.

## Steps (added 2026-10-22, from `mockups/steps-screen.html`)
- **Entry card** under the weight card, with its own **Save** button, so steps can be logged on a day with no weight (travelling without a scale) and saving steps never touches the weight. One field only: yesterday (with "saved n" once entered). Numbers are typed from the phone's own step counter; one count per day, saving again replaces. Below it, "n days missing · Add ›" appears when any day in the 14 before yesterday has no count (counted from the first steps entry, so a new user sees nothing); it opens a sheet with one row per missing day, like the weight reasons sheet. Fill what you can; blank rows stay missing.
- **Tile** "Steps · 7-day average": mean of the days logged in the 7 calendar days ending yesterday, with "n of 7 days"; dash with "building, n of 7" below three days. Right side: change vs the 7 days before (red down, green up) when both sides have ≥3 days, else the goal.
- **Trend**: the collapsed trend has a Weight / Steps switch. Steps shows daily bars (brighter at or above goal), the 7-day average line broken on gaps > 3 days, a dashed goal line, and the same 4w/12w/All ranges and touch tooltip. Missed-day reason bands carry over.
- **Goal**: Settings > Steps goal (default 10,000), stored on `profiles.steps_goal` so every device agrees; mirrored locally in `meta.stepsGoal`.
- No reasons flow for missing step days, no streaks, no plan awareness.

## Earned day (added 2026-10-22, from `mockups/earned-day.html`; rule in `HealthTracker/EARNED-DAY.md`)
- **Day card** under the status card, visible all day. States: *Earned day* (green, the two numbers that earned it, **Take today** button), *Day taken* (green, "Food and the workout are your call today. Steps and the sleep window stay." + Undo), *Sunday* (green, "Your free day: no diet, no session."), *Hold the plan today* (grey, the first rule that failed), *Log today's weight* (no reading yet).
- **Rule**, both rates fixed at 0.7 kg/week. Above the goal weight: week-vs-last (rounded to 0.1) ≤ −0.7, pace since the first reading ≤ −0.7 kg/week, and no taken day in the last 7 days. At or below the goal (7-day average ≤ goal): only the 7-day rule. Sunday is never a taken day. Needs 3+ readings on both sides of the week comparison.
- **Take today** writes `earned_days(date)` for today; tapping Undo the same day soft-deletes it. Untaken days are not recorded, so a green card can stay green on later days.
- **Goal weight**: Settings > Goal weight, per user on `profiles.goal_kg` (nullable; "not set" until chosen; treated as "above goal" while unset), mirrored in `meta.goalKg`.
- Not built: the maintenance ceiling (goal + 3 kg → 4-week cut banner).

## Missed days and reasons
- Missed = calendar days between the last entry and today (exclusive of today) with neither a weight nor a reason.
- Sheet lists one row per missed day, each with a type-or-pick field. The list is that user's own past reasons (most recent first); no presets. Typing something new offers "Add …" and saves it to their list. "Use this for all days" appears when the first row is filled and others differ. Optional; never blocks.
- Reasons live in `reasons` (per user); gap entries in `gaps` (date → reason). Removing a reason from the list soft-deletes it; past gaps keep their text.

## Sync (local-first)
- Every write goes to Dexie first with `synced=0`, then `sync()` runs immediately. Triggers: app open, every save, `online` event, app returns to foreground, tap on the dot.
- Push: upsert all `synced=0` rows. Pull: rows with `updated_at` > last pull. Conflict: later `updated_at` wins. Soft-delete via `deleted` so removals propagate.
- `profiles.reset_at`: **Start fresh** calls `reset_my_data()` (deletes the user's rows server-side, stamps `reset_at`); every device clears its local copy when it sees a newer `reset_at`, so a reset holds across devices.

## Settings sheet
Backup (download JSON of weights, gaps, reasons, steps, earned days) · Goal weight · Steps goal · Change password · Start fresh (confirm, then reset as above) · Sign out.

## Database (`supabase/schema.sql`)
`profiles(id, name, reset_at, steps_goal)`, `weights(user_id, date, kg, evening, logged_at, updated_at, deleted)`, `gaps(user_id, date, reason, updated_at, deleted)`, `reasons(user_id, name, last_used, updated_at, deleted)`, `steps(user_id, date, count, updated_at, deleted)`, `earned_days(user_id, date, updated_at, deleted)`; `profiles.goal_kg`. RLS on all: `auth.uid() = user_id`.

## Out of scope for v1
Plan awareness (phases, projections, targets), reminders, sharing between users, Google sign-in, export formats other than JSON, light theme.
