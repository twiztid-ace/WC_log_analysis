# Druid v2 pipeline — TODO / known issues

Living tracker for bugs and open work on the enhanced (v2, events-based) Druid
pipeline specifically. Not a duplicate of WORKFLOW.md's gotcha list — cross-references
it where relevant, but this file is for *tracking status* (open/in-progress/done),
WORKFLOW.md stays the deep explanation of *why*. Update this as items get fixed or
new ones get found — don't let it go stale.

## Blocking the "best version" report — do these first

- [x] **Build one real v2 boss page end-to-end.** Done for Danceswtrees / Hydross
      the Unstable (2026-07-07): `docs/danceswtrees/2026-07-07/healer_audit_hydross.html`,
      built entirely from real data (healing/casts events, consumables, real WCL
      percentile cross-matched by exact report/fight ID, real Top 100 benchmark
      comparison). `boss_page_template_druid.html`'s placeholder set held up
      against real data with no structural surprises — union-of-spell-lists,
      self/other cooldown targeting, boolean vs. real-% buff display all worked
      as documented. (CLAUDE.md open item #1)
- [ ] **Extend to the other 9 bosses for Danceswtrees's 2026-07-07 raid night.**
      Only Hydross is done. `docs/danceswtrees/2026-07-07/index.html` (the v2 raid
      overview) already has explicit "not migrated" pending rows for the rest,
      each linking to its real v1 page in the meantime — see "New folder
      convention" below before touching any of these.
- [x] *Mostly resolved:* **Gear audit regression.** Confirmed the `combatantinfo`
      events pull (same mechanism as flask/food) works for getting real gear back
      — pulled it live for Danceswtrees/Hydross and built a real gear audit
      section in the v2 raid overview from it. Also discovered `parses/character`
      responses already include a real average item level in the
      `ilvlKeyOrPatch` field (verified: matched the combatantinfo-computed
      average, 120, exactly) — a future boss page's header `{{ITEM_LEVEL}}` may
      not need a fresh combatantinfo pull at all, just this field. Still open:
      the audit is scoped to ONE fight's snapshot — WORKFLOW.md's "confirm gear
      is identical across all kills before presenting one audit" rule hasn't
      been satisfied yet, since the other 9 kills have no v2 combatantinfo pull.
- [ ] **Two new real findings from that one gear snapshot, unresolved:** (1) a gem
      recount directly from the raw data gives 13 non-meta gems, not the 12 v1's
      original audit stated — a real discrepancy between v1's write-up and what
      the data actually shows, not yet reconciled either direction. (2) one gear
      slot shows no item equipped (generic empty-slot icon in the raw
      `combatantinfo` response) — real, but which slot it is couldn't be
      determined from the data alone this session.
- [x] **"Union of both spell lists" requirement — now fully verified, not just
      exercised.** The Top100-avg switch (below) surfaced 2 real benchmark-only
      guids (Regrowth 9857/9858, ~0.9%/0.6% of the Top 100 average) that
      Danceswtrees never cast — didn't show up at all under the old Top-10-only
      view. The Hydross page now genuinely shows both as real 0% rows per the
      union rule, the actual edge case this requirement exists for, not just the
      trivial case where both lists already matched.
- [x] *Reviewed, not live-tested:* **`pull_character_TEMPLATE.ps1` compatibility.**
      Read the full script this session — output field shapes (`sourceName`,
      `totalAmount`, `totalOverheal`, `events[]`, `flaskActive`/`foodActive`/
      `treeOfLifeUptimePct`) match what the Hydross page consumed with no
      adjustment needed. All Danceswtrees data used was from an existing pre-session
      pull, though — this confirms the format still lines up, not that a *fresh*
      run of the script still works end-to-end. A real live test pull is still
      worth doing at some point.

## Top100-avg methodology switch (2026-07-12)

- [x] **Switched every "Top 10 avg" aggregate to "Top 100 avg."** Was: spell
      composition, target coverage, cooldown/utility casts, and flask/food/Tree
      of Life stats were all computed over only the best 10 of the ~100 real
      parses pulled per boss, throwing away ~90 real data points for a noisier
      10-person average. Now: every one of those aggregates uses the full real
      sample (`SampleSize`/`SampleUsed` still reports the true count, not
      assumed to be exactly 100). `HPS_Top1` and `HPS_Median` were already
      whole-sample stats and didn't change. Updated: `summarize_class_benchmarks.ps1`
      (columns renamed `Top10*` → `Top100*` throughout both CSVs and code),
      `boss_page_template_druid.html` (all "Top 10" language → "Top 100"),
      WORKFLOW.md's benchmark-methodology descriptions, and the real Hydross
      page's numbers/findings fully recomputed against the new CSVs — not just
      relabeled. Regenerated all 4 Druid `benchmark_*.csv` files against real
      active data to confirm.
- [ ] **New bug found via this switch: Nature's Swiftness's self-cast % is
      probably wrong in the benchmark, and possibly any similarly self-only
      spell.** `summarize_class_benchmarks.ps1`'s self/other classification is
      `sourceName -eq targetName`. Self-only spells with no real target (NS,
      possibly others) get logged by WCL with `target = {"name": "Environment",
      ...}`, not the caster — so `targetName` is `null`/"Environment", never
      equal to `sourceName`, and every self-cast of a spell shaped like this
      gets silently counted as "not self." Confirmed real on Hydross:
      `benchmark_cooldowns.csv` shows NS at 0% self across the full 100-person
      sample, which isn't plausible for a spell that can only ever be cast on
      the caster. Not fixed yet — the Hydross page's coverage-note flags this
      number as unreliable rather than trusting it, but the underlying
      classification bug is still live in the script.

## Known data gaps / report-copy caveats

- [x] *Deprioritized, not needed for now:* **Tranquility's guid is unobserved** —
      `$cooldownGuids["Tranquility"]` is an empty array, so `benchmark_cooldowns.csv`
      shows 0 casts/0% used for every boss regardless of reality. Originally risky
      because a report could read "0% of the Top 100 used Tranquility" as a real
      finding — but the 2026-07-12 conditional-display rule (Tranquility's row on a
      boss page only appears when the character's usage is a real deviation from
      Top100UsedPct) already neutralizes that risk: a permanently-0 benchmark number
      just means the row never gets shown as "notable," not that a wrong number gets
      surfaced. Revisit adding the real guid only if Tranquility usage actually needs
      to be tracked for some other reason later — not blocking anything right now.
- [ ] **`resources`/`resources-gains` (HPM, mana-over-time) still untested** with
      the correct `abilityid` param (the earlier `resourcetype` guess was
      confirmed wrong). Not blocking, just unclaimed upside.
- [x] *Checked, not a bug:* `benchmark_buffs.csv` showing identical
      Flask%/Food% for some bosses (e.g. Morogrim 70/70, from the old Top-10-only
      view — worth a fresh look now that the aggregate is Top 100) is a genuine
      correlation among prepared raiders, not a code bug — spot-checked real
      `_consumables.json` files and confirmed flask/food are computed
      independently (found real divergent cases: flask-no-food, neither).
- [ ] **~0.5% of Top 100 parses (1 in ~200) have no `combatantinfo` snapshot** even
      within the 2-minute backward buffer, likely a late-joining player. Reported
      as a failure for that player's consumables specifically, never treated as
      "no flask" — if the specific character being reported on hits this, that
      boss's flask/food section has a real, honest gap. Don't paper over it.
- [ ] **The ≥2,900-event warning is a heuristic, not a guaranteed-complete check.**
      No confirmed real truncation on `/report/events/` yet, but nothing rules it
      out on an unusually long fight (Vashj/Kael'thas run long). Worth a second
      look if a report's numbers look implausibly low for a specific long kill.

## Real bugs found this session, not yet fixed

- [ ] **A parse that drops out of the Top 100 and later re-enters is mishandled.**
      Confirmed by re-reading `pull_top100_druid.ps1`'s diff logic: it only checks
      parses with `status == "active"` to decide what's new, so a re-appearing
      archived parse gets treated as brand-new — wastefully re-fetched from the
      API even though identical data already sits in `archived\{Boss}\`, its
      manifest entry gets overwritten (losing the original `firstSeenAt`), and the
      stale archived copy is never cleaned up or reconciled. Ends up with the same
      parse's files in both `active\` and `archived\` at once. Not hit yet in
      testing (nothing has re-entered across the two live runs so far), but real
      and findable the moment it happens.
- [ ] **`manifest.json` has no pruning, grows indefinitely.** Already ~1.3MB at
      1,000 active parses; archived entries kept forever by design. Not urgent,
      just a scaling note for whatever eventually reads this file often.

## New folder convention — read before building the remaining 9 boss pages

Established this session, real and in use now: v1 and v2 output for the same
healer+raid-night live side by side, never overwriting each other.
```
docs/{healer}/{date}-v1/    <- original v1 pages, frozen, git-tracked reference
docs/{healer}/{date}/       <- new v2 pages, built incrementally as each boss gets done
```
`docs/danceswtrees/index.html` links to both explicitly ("SSC / TK - V1" / "SSC / TK
- V2" rows). **Never write directly into a `-v1` folder** — this session already
made that mistake once (overwrote the live v1 Hydross page by accident before this
convention existed) and had to restore it from git history. Always create/edit only
under the plain `{date}` folder for new v2 work.

## Explicitly out of scope for now

- Paladin/Priest/Shaman are still v1 (healing TABLE, truncation-prone) AND the old
  date-stamped-folder convention. Not being worked on until Druid v2 is proven out
  end-to-end. `summarize_class_benchmarks.ps1 -DateFolder {date}` now fails loudly
  instead of silently writing empty CSVs if pointed at v1 data it can't parse — see
  WORKFLOW.md gotcha #25.
