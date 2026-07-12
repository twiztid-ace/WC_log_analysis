# ATNF Healer Analysis — Claude Code orientation

This is a WoW Classic (TBC/SSC-TK era) raid healer analysis pipeline: pull real combat
log data from Warcraft Logs' v1 API, benchmark it against Top 100 parses, and generate
a static HTML site auditing each healer's performance per boss kill.

**Read `WORKFLOW.md` first, in full, before touching anything.** It is the single
source of truth for this project — API endpoints, file formats, known bugs, and 24
numbered "gotchas" documenting real mistakes already made and fixed. Assume anything
not in WORKFLOW.md is unverified. This file is just a map to get you oriented quickly;
WORKFLOW.md has the actual depth.

## You can do something I (this conversation's Claude) couldn't

This whole project was built through a text-based chat where I could never execute
PowerShell myself — every script had to be handed to the person to run, with results
pasted back as text before I could react. That was slow and error-prone (see gotcha
#19 in WORKFLOW.md for a bug that only got caught because of exactly this friction).

**You're running in an environment with real command execution.** Actually run the
`.ps1` scripts. Actually inspect the JSON output files directly instead of asking the
person to paste console output. This should make you meaningfully more effective at
catching bugs than I was — use that.

One catch: these scripts are Windows PowerShell 5.1-specific in places (see gotcha
#13 on `-UseBasicParsing`, gotcha #14 on BOM/encoding issues, gotcha #19 on the
`if/else` array-collapse bug). If you're not running on Windows, don't assume they'll
behave identically on PowerShell 7+/pwsh on Linux/Mac — test before trusting.

## Two generations of this pipeline — don't confuse them

This project has a **simple v1** (already shipped, live on 4 healer sites) and an
**enhanced v2** (in progress, Druid-only so far). Reading the repo cold, both look
like "real output" — they're not at the same maturity, and mixing them up is the
main way to get confused here.

- **v1 (simple)**: gear check + basic spell composition + a couple of other checks,
  built on the old `/report/tables/` healing view (5-entry truncation bug and all —
  see WORKFLOW.md gotcha #4/#15). This is what produced the 4 fully-built healer
  sites currently sitting at the repo root (`crowns/`, `danceswtrees/`, `lippies/`,
  `vajomee/`, plus the root `index.html` homepage). Treat these as a finished
  snapshot of the *old* methodology, not a template for new output — regenerating
  them with the v2 pipeline is future work, not done.
- **v2 (enhanced)**: events-based healing/casts (no truncation), cooldown/utility
  tracking with self-vs-other targets, real buff uptime (flask/food snapshot + Tree
  of Life interval reconstruction), Top 100 benchmarking, CSV summarization. Only
  **Resto Druid** has this so far, and it's mid-pull, not complete (see "Current
  state" below). No v2 healer site has been generated yet — `examples/` has one
  reference page but it's out of date (see below).

## Repo structure

```
WORKFLOW.md                          <- read this first, full pipeline documentation
CLAUDE.md                            <- this file

scripts/
  pull_character_TEMPLATE.ps1        <- pulls one specific healer's full raid night (v2, events-based)
  pull_top100_druid.ps1              <- Top 100 Resto Druid benchmark pull, v2/enhanced, parallelized
  pull_top100_paladin.ps1            <- Top 100 Paladin/Holy pull — v1/simple, healing TABLE only
  pull_top100_priest_holy.ps1        <- Top 100 Priest/Holy pull — v1/simple, healing TABLE only
  pull_top100_shaman.ps1             <- Top 100 Resto Shaman pull — v1/simple, healing TABLE only
  pull_top100_TEMPLATE.ps1           <- generic template these three v1 scripts were generated
                                         from; still the base for any new v1-style class pull
  summarize_class_benchmarks.ps1     <- condenses raw Top 100 pulls into benchmark_*.csv files
                                         (Druid-specific cooldown/buff columns only apply once
                                         run against v2-style Druid data)

templates/
  design_tokens.md                   <- the site's design system (colors, type, layout rules)
  boss_page_template.html            <- generic per-boss-kill page (any class, v1-style data)
  boss_page_template_druid.html      <- Resto Druid variant (extra cooldowns/consumables section,
                                         needs v2-style events/consumables data to fill in)
  raid_overview_template.html        <- per-raid-night page (gear audit + 10-boss summary)
  healer_raidlist_template.html      <- per-healer page (list of raid nights analyzed)
  site_index_template.html           <- site homepage (list of healers)

reference/
  warcraftlogs_api.json              <- the real v1 API swagger spec (this environment's fetch
                                         tool couldn't render the live JS docs page - see gotcha
                                         #17 - this static copy is what unblocked several fixes)

examples/
  healer_audit_hydross.html          <- ONE real filled v1-generation example page (Danceswtrees
                                         on Hydross). Predates the buff-uptime fix and the whole
                                         events-based rewrite — still shows the old "temporarily
                                         unavailable" note for flask/food/Tree of Life and uses
                                         the truncated healing table underneath. Useful only as a
                                         rough visual reference, not as ground truth for either
                                         generation's current data shape.

Live v1 site output (already generated, at repo root — not templates, actual pages):
  index.html                         <- site homepage, links to all 4 healers below
  crowns/, danceswtrees/, lippies/, vajomee/
    index.html                       <- per-healer raid-night list
    {date}/index.html                <- raid overview for that night
    {date}/healer_audit_{boss}.html  <- one per boss kill (v1 methodology)
```

Not included here (repo-specific, never shared in the source conversation):
`apikey.txt` (gitignored, WCL API key), `.gitignore`.

## Current state — what's solid vs. what's open

**v1 (simple) — shipped:**
- 4 healer sites fully built and live at repo root (`crowns/`, `danceswtrees/`,
  `lippies/`, `vajomee/`), each with all 10 SSC/TK boss kills for one raid night.
  This is the old gear-check + basic-spell-composition methodology — not being
  extended further, only kept as-is until v2 replaces it per class.
- `pull_top100_paladin.ps1`, `pull_top100_priest_holy.ps1`, `pull_top100_shaman.ps1`
  have all been run — `data\Classes\{Paladin,Priest,Shaman}\2026-07-10\` is
  populated for all 10 bosses, with `benchmark_summary.csv` and
  `benchmark_spell_composition.csv` already generated for at least Paladin and
  Priest. This is v1-generation data (healing table, 5-entry truncation risk per
  gotcha #15) — do not treat it as equivalent to Druid's v2 data.

**v2 (enhanced) — in progress, Druid only:**
- Pipeline validated end to end on real data: events-based healing/casts (no
  truncation), cooldown/utility tracking with self-vs-other targets, buff uptime
  (flask/food snapshot + real Tree of Life interval reconstruction), the Druid boss
  page template.
- `pull_top100_druid.ps1` (RunspacePool, `-MaxThreads 10` default, thread-safe via
  `ConcurrentDictionary` + a `TryAdd`-based claim mechanism for `deaths`) has
  actually been run for **5 of 10 bosses** as of the last check: Hydross,
  Karathress, Leotheras, Lurker, Morogrim — confirmed by listing
  `data\Classes\Druid\2026-07-10\` directly. Vashj, Al'ar, Void Reaver, Solarian,
  and Kael'thas have not been pulled yet. **Verify this against the actual folder
  before trusting a boss count someone recalls from memory** — this number has
  drifted from reality before.
- `summarize_class_benchmarks.ps1` has NOT yet been run against this Druid pull —
  no `benchmark_*.csv` files exist in `data\Classes\Druid\2026-07-10\` yet.
- No v2 healer site (raid overview + boss pages built from real Druid events data)
  has been generated yet for any healer.

**Explicitly open, in priority-ish order:**
1. Finish the remaining 5 Druid bosses through `pull_top100_druid.ps1`, then run
   `summarize_class_benchmarks.ps1` before trusting a complete Druid benchmark
   dataset.
2. Generate an actual v2 healer site (at least one full raid night) to prove the
   enhanced pipeline end-to-end, including a raid overview page — see gear-audit
   regression note below, this hasn't been exercised since the events-based rewrite.
3. Gear audit has an undiscovered-but-expected regression: the old healing *table*
   embedded `gear` per player for free; healing *events* don't carry it at all.
   Nobody's built a raid overview page since the events-based rewrite, so this
   hasn't been hit yet, but it will be — see WORKFLOW.md's "Regression to know
   about" note for the fix (a `combatantinfo` events pull).
4. `resources`/`resources-gains` (HPM, mana-over-time) were abandoned after
   `resourcetype=mana`/`resourcetype=0` both failed — but the real swagger spec
   later revealed the correct param name is `abilityid`, and **nobody's gone back
   and actually tested it**. Cheap, real opportunity if you want it.
5. Tranquility's guid is unknown/unobserved — `$cooldownGuids["Tranquility"]` is an
   empty array in both pull scripts and will silently show 0 forever until someone
   adds the real guid once it's actually seen in a pull.
6. Paladin/Priest/Shaman are still on the v1/simple, truncation-prone table
   approach — none of the events-based/cooldown/buff-uptime work has been ported to
   them yet. Porting a class means: writing its own `pull_top100_{class}.ps1` on
   the Druid model (not the TEMPLATE model), and its own
   `boss_page_template_{class}.html` per WORKFLOW.md's "Site structure" section.
7. One narrow, accepted gap: ~0.5% of Top 100 parses (1 real case observed) have no
   `combatantinfo` snapshot even within the 2-minute backward buffer, likely a
   late-joining player — currently just reported as a failure for that one player's
   consumables data, not chased further.

## Ground rules (condensed from WORKFLOW.md — read the real thing for why)

- **Never fabricate or estimate a number that wasn't actually pulled.** If data is
  missing or a source is known-unreliable, say so explicitly rather than guessing or
  omitting silently.
- **No letter grades, ever** — percentile numbers only (gotcha #9). This was an
  explicit, deliberate design correction; don't reintroduce it.
- **Group by ability guid, never by display name** (gotcha #2) — names are localized
  per client. But also: **don't merge different guids that share a display name**
  without checking first (gotcha #20) — sometimes that's a real mechanical
  distinction (Lifebloom's HoT-tick vs. bloom-burst are different guids), not noise.
- **Test one real API call before building a pull script around an assumption** —
  this pattern (ask for one small diagnostic, read the real response, THEN write
  code) caught almost every bug in WORKFLOW.md's gotcha list. Don't skip it just
  because you can now run things yourself.

## Hosting — GitHub Pages

The repo is already on GitHub: **`twiztid-ace/WC_log_analysis`** (public), default
branch **`master`** (not `main` — worth noting since that's the more common default
name now). The person manages it day-to-day through **SourceTree**, not the raw git
CLI.

**Git CLI is available even though it's not on PATH.** SourceTree bundles its own
git at `%LOCALAPPDATA%\Atlassian\SourceTree\git_local\bin\git.exe`. Call it with a
full path (or `-C <repo-path>`) to inspect real repo state directly — confirmed
working:
```powershell
& "$env:LOCALAPPDATA\Atlassian\SourceTree\git_local\bin\git.exe" -C "C:\Users\raymo\wc_logs" status
```
Prefer this over asking the person to run/paste git output, same reasoning as the
"you can do something I couldn't" section above. `apikey.txt` is confirmed **not**
tracked (`git ls-files` doesn't list it) — safe as long as `.gitignore` isn't
changed to drop that line.

**Chosen approach: separate code from the served static site using a `docs/`
folder**, not a dedicated `gh-pages` branch. GitHub Pages supports serving from
`/docs` on a normal branch (Settings → Pages → Source → Deploy from a branch →
`master` / `/docs`), which avoids juggling an orphan branch in a GUI client like
SourceTree — a plain commit+push to `docs/` is enough to publish, no branch
switching required.

**What this means for the current repo layout — not done yet, real migration
required:** the live v1 site output (`index.html`, `crowns/`, `danceswtrees/`,
`lippies/`, `vajomee/`) currently sits at the **repo root**, alongside `scripts/`,
`data/`, `templates/`, `reference/`. To use the `/docs` scheme as intended (site
output separated from code/raw data), these need to move under a new `docs/`
folder at repo root, preserving their internal structure exactly — the pages use
relative links (`../index.html`, etc.), so moving the whole tree together keeps
those working; moving pieces individually would break them. `scripts/`, `data/`,
`templates/`, `reference/`, `examples/`, `WORKFLOW.md`, `CLAUDE.md` stay where they
are — Pages only serves what's inside `docs/`, so keeping them at root just means
they're not web-served (still visible in the repo browser itself, since the repo
is public — Pages scoping doesn't hide them, it just keeps them out of the
served site).

**One-time setup on github.com (not doable via git/API from here):**
1. Confirm repo visibility: Settings → General → Danger Zone → should already say
   Public.
2. After the `docs/` migration lands on `master`: Settings → Pages → Source →
   "Deploy from a branch" → Branch: `master`, folder: `/docs` → Save.
3. Resulting URL: `https://twiztid-ace.github.io/WC_log_analysis/` — a **project
   site**, served from a subpath, not domain root. Smoke-test the first deploy
   specifically for any accidentally-absolute (`/index.html`-style) links; the
   site already uses relative links throughout per WORKFLOW.md's zip-delivery
   convention, so this should already be fine, but hasn't been verified live.

**Ongoing publish workflow once set up:** regenerate/edit the static pages under
`docs/`, commit, push via SourceTree — GitHub rebuilds Pages automatically
(typically under a minute), no separate build step, since this has always been
plain static HTML/CSS with no bundler.

**Not done automatically by writing this section:** the `docs/` folder migration
and the GitHub Pages toggle itself are both real, visible changes (one moves
already-linked files, the other exposes a public URL) — confirm before either
happens rather than assuming this documentation update means it's live.
