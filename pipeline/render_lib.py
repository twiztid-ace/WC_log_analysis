"""Non-templating half of ReportRenderLib.psm1 - shared gear/cooldown/caveat
helpers used by build_analysis.py and (later) render_report.py.

The templating primitives (Expand-TemplateLoop, Set-TemplateSlot,
Set-TemplateOptional, etc.) are NOT ported here - those are being replaced
entirely by Jinja2 in Phase 4, per the approved migration plan.

Class-specific data (cooldown target modes, active stat blocks, has_tranquility/
has_rebirth) now lives in pipeline/classes.py rather than being duplicated here -
this module's Get-CooldownTargetMode/Get-ActiveStatBlocks equivalents are thin
wrappers over that single source of truth.
"""

from __future__ import annotations

import datetime as _dt

from jinja2 import Environment, FileSystemLoader, StrictUndefined, select_autoescape

from pipeline import classes as classes_module
from pipeline.numeric import round_net

EM_DASH = "—"
RIGHT_ARROW = "→"
MULT_SIGN = "×"


def make_jinja_env(templates_root: str) -> Environment:
    """Shared Jinja2 config for both the per-boss/raid-overview renderer
    (render_report.py) and the hub-page renderer (hub_pages.py) - kept in one
    place so the two can't drift apart (autoescape/StrictUndefined behavior
    matters for both, see render_report.py's module docstring)."""
    return Environment(
        loader=FileSystemLoader(templates_root),
        autoescape=select_autoescape(["html", "jinja"]),
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
    )


def format_long_date(yyyy_mm_dd: str) -> str:
    """Matches PowerShell's ToString("MMMM d, yyyy") - full month name, day
    with no leading zero, 4-digit year. Built manually rather than via
    strftime's "%-d"/"%#d" (platform-specific: Unix vs Windows use different
    flags for "no leading zero", so neither is portable)."""
    dt = _dt.datetime.strptime(yyyy_mm_dd, "%Y-%m-%d")
    return f"{dt.strftime('%B')} {dt.day}, {dt.year}"

# ===== 19-slot gear order (see CLAUDE.md's "Ground rules") - fixed WoW
# combatantinfo gear[] position, confirmed real, never re-derive this ad hoc. =====
GEAR_SLOT_NAMES = [
    "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet",
    "Wrist", "Hands", "Finger1", "Finger2", "Trinket1", "Trinket2",
    "Back", "MainHand", "OffHand", "Ranged", "Tabard",
]

# OffHand(16) deliberately excluded - a caster off-hand "held" item (orb, tome,
# idol) can't carry a permanent enchant in this era, and combatantinfo's gear[]
# entries carry no item type/subclass field to distinguish it from a real
# off-hand weapon/shield, so the safe default is to never flag this slot.
ENCHANTABLE_SLOT_INDEXES = {0, 2, 4, 6, 7, 8, 9, 14, 15}

# Known, confirmed real per-guid labels for specific multi-rank spells whose
# guid split has actually been investigated - NOT a general "guess what any
# 2-guid spell means" mechanism.
KNOWN_SPELL_RANK_LABELS = {33763: "HoT", 33778: "Bloom"}


def get_known_spell_rank_label(guid: int) -> str | None:
    return KNOWN_SPELL_RANK_LABELS.get(guid)


def get_gear_slot_name(slot_index: int) -> str:
    if 0 <= slot_index < len(GEAR_SLOT_NAMES):
        return GEAR_SLOT_NAMES[slot_index]
    return f"Unknown({slot_index})"


def test_slot_enchantable(slot_index: int, gear_item_at_slot: dict | None = None) -> bool:
    """`gear_item_at_slot` is accepted for signature parity with the PS
    original but unused - the allowlist alone is authoritative now that
    OffHand has been removed from it."""
    return slot_index in ENCHANTABLE_SLOT_INDEXES


def convert_to_bm_number(value) -> float | None:
    """Parses a BM/BMSpells/BMCooldowns/BMBuffs CSV-string field to a float
    or None. Blank/empty -> None (means "no data"), never coerced to 0 (a
    real, meaningful zero)."""
    if value is None:
        return None
    s = str(value).strip()
    if s == "":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def get_cooldown_target_mode(class_name: str, ability_name: str) -> str:
    cfg = classes_module.CLASSES.get(class_name)
    if cfg and ability_name in cfg.target_mode:
        return cfg.target_mode[ability_name]
    return "other"


def format_cooldown_target(targets: list[dict], mode: str) -> str:
    """Collapses a CooldownRows[ability].Targets array (list of {"Target":
    ..., "Timestamp": ...} dicts, matching report_data.json's real JSON
    shape) into the exact display string used across every hand-built page
    in the original pipeline."""
    if mode == "party":
        return "party" if len(targets) > 0 else EM_DASH
    if mode == "self":
        return "self" if len(targets) > 0 else EM_DASH
    if len(targets) == 0:
        return EM_DASH

    order: list[str] = []
    counts: dict[str, int] = {}
    for t in targets:
        name = "self" if t["Target"] == "self" else t["Target"]
        if name not in counts:
            counts[name] = 0
            order.append(name)
        counts[name] += 1

    parts = []
    for name in order:
        if name == "self":
            parts.append("self")
        elif counts[name] > 1:
            parts.append(f"{RIGHT_ARROW} {name} {MULT_SIGN}{counts[name]}")
        else:
            parts.append(f"{RIGHT_ARROW} {name}")
    return ", ".join(parts)


def test_tranquility_include(count: int, top100_used_pct: float | None) -> bool:
    """Exact numeric rule from SKILL.md/CLAUDE.md (Druid Tranquility only)."""
    if top100_used_pct is None:
        return False
    pct = float(top100_used_pct)
    if count > 0 and pct <= 20:
        return True
    if count == 0 and pct >= 50:
        return True
    return False


def test_cooldown_deviates(count: int, top100_used_pct: float | None) -> bool:
    """Generalizes the same threshold to every tracked cooldown for every
    class - feeds RaidWideRollups.CooldownDeviations in the analysis file."""
    if top100_used_pct is None:
        return False
    pct = float(top100_used_pct)
    if count == 0 and pct >= 50:
        return True
    if count > 0 and pct <= 20:
        return True
    return False


def get_canned_caveats(class_name: str, cooldown_rows: dict | None, spell_rows: list[dict] | None) -> list[str]:
    """Fixed, already-documented facts (not per-page discoveries) - tags when
    the trigger condition is met so a findings-authoring step is prompted to
    use the documented caveat language rather than reinvent/misstate it."""
    tags = []
    if class_name == "Priest" and cooldown_rows and "Power Word: Shield" in cooldown_rows:
        tags.append("priest_pws_benchmark_bias")
    if class_name == "Paladin" and cooldown_rows and "Holy Shock" in cooldown_rows:
        has_heal_row = any(int(row["Guid"]) == 33074 for row in (spell_rows or []))
        if not has_heal_row:
            tags.append("paladin_holy_shock_guid_split")
    return tags


def get_active_stat_blocks(class_name: str) -> list[str]:
    cfg = classes_module.CLASSES.get(class_name)
    return list(cfg.active_stat_blocks) if cfg else ["Flask", "Food", "ManaConsumable", "HPM"]


# ===== Mana-timing coaching (Phase 1) =====
#
# WCL v2's `classResources[]` sub-object on a Casts event has field names
# that do NOT mean what they literally say. Confirmed live 2026-07-20 via
# (a) cross-referencing this pipeline's own already-known Lifebloom mana
# cost (report_data.json's ManaCostByGuid: {"33763": 220} - exactly matches),
# and (b) a full-fight self-consistency check (never negative, never exceeds
# the pool, matches worldData.encounter's separate Resources-events
# maxResourceAmount). The real mapping:
#   entry["amount"] -> the character's MAX mana pool (constant all fight)
#   entry["max"]    -> the mana COST of this specific cast
#   entry["type"]   -> the character's CURRENT mana at the moment of this
#                       cast, BEFORE this cast's own cost is deducted
# Do not "fix" these names to look more sensible without re-verifying live -
# this is the real, confirmed shape of WCL's response, not a bug in this file.

def parse_mana_readings(cast_events: list[dict]) -> list[dict]:
    """Extracts one mana reading per cast event that carries classResources
    (some events - e.g. procs with no resourceActor - don't), sorted by
    timestamp. See the module-level note above for the real field mapping."""
    readings = []
    for ev in cast_events:
        cr = ev.get("classResources")
        if not cr:
            continue
        entry = cr[0]
        pool = entry.get("amount")
        current = entry.get("type")
        cost = entry.get("max") or 0
        if not pool:
            continue
        readings.append({
            "Timestamp": ev["timestamp"], "CurrentMana": current, "MaxMana": pool, "Cost": cost,
            "AbilityGuid": ev.get("abilityGameID"),
            "PctAtCast": round_net((current / pool) * 100, 1),
        })
    readings.sort(key=lambda r: r["Timestamp"])
    return readings


def compute_mana_timing(
    cast_events: list[dict], fight_start: float, fight_end: float,
    low_pct_threshold: float = 20, high_pct_threshold: float = 90,
) -> dict | None:
    """Mana-timing summary for one boss kill - zero new API calls, entirely
    derived from classResources already sitting in existing
    fight*_casts_events.json files. Returns None when the fight has no usable
    mana readings (e.g. a non-mana-user, or every cast event lacked
    classResources).

    "Time spent" figures are a step-function approximation (mana level held
    constant from one reading to the next) since readings only exist at cast
    moments, not continuously - a documented approximation, not a measured
    fact, same spirit as this pipeline's other derived-not-logged figures."""
    readings = parse_mana_readings(cast_events)
    if not readings:
        return None

    last = readings[-1]
    # Clamped to 0 - real mana can't go negative; a small negative raw value
    # here just means the "current mana before this cast" reading already
    # accounted for a regen tick this approximation doesn't otherwise model
    # (e.g. Dark Rune landing right at the last cast).
    ending_mana = max(0, last["CurrentMana"] - last["Cost"])
    ending_pct = round_net((ending_mana / last["MaxMana"]) * 100, 1) if last["MaxMana"] else None

    low_mana_casts = sum(1 for r in readings if r["PctAtCast"] < low_pct_threshold)
    high_mana_casts = sum(1 for r in readings if r["PctAtCast"] >= high_pct_threshold)

    points = [(fight_start, readings[0]["PctAtCast"])] + [(r["Timestamp"], r["PctAtCast"]) for r in readings] + [(fight_end, ending_pct)]
    time_low_ms = 0.0
    time_high_ms = 0.0
    for (t0, pct0), (t1, _pct1) in zip(points, points[1:]):
        if pct0 is None:
            continue
        dur = max(0.0, t1 - t0)
        if pct0 < low_pct_threshold:
            time_low_ms += dur
        elif pct0 >= high_pct_threshold:
            time_high_ms += dur

    fight_duration_ms = max(1.0, fight_end - fight_start)
    return {
        "StartingManaPct": readings[0]["PctAtCast"], "EndingManaPctApprox": ending_pct,
        "LowManaCastCount": low_mana_casts, "HighManaCastCount": high_mana_casts,
        "TimeBelowLowThresholdPct": round_net((time_low_ms / fight_duration_ms) * 100, 1),
        "TimeAboveHighThresholdPct": round_net((time_high_ms / fight_duration_ms) * 100, 1),
        "LowThreshold": low_pct_threshold, "HighThreshold": high_pct_threshold,
        "ReadingCount": len(readings),
    }


def test_missed_second_potion(potion_targets: list[dict], fight_end: float, potion_cooldown_ms: float = 120000) -> bool:
    """Real TBC mechanic, not a guess: potions share a fixed 120s internal
    cooldown. Fixed numeric rule (same style/shape as test_tranquility_include):
    flags a real, missed second-use opportunity when exactly one potion was
    used early enough in the fight that the cooldown would have been up again
    before the fight ended, but no second use was ever cast. Never fires for
    zero or 2+ real uses - those aren't a "missed opportunity" by this rule."""
    if len(potion_targets) != 1:
        return False
    first_ts = potion_targets[0].get("Timestamp")
    if first_ts is None:
        return False
    return (fight_end - first_ts) >= potion_cooldown_ms
