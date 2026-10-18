#!/usr/bin/env python3
"""The house rules, as checks instead of prose.

    tools/verify.sh rules

Every rule here is written down in CLAUDE.md. Most were inherited from
Deadweight, where each one was broken at least once while it existed only as a
sentence: a rule in a document is something a reader might remember, and a rule
in a check is something that stops them.

Add a rule here the moment one is agreed. If a check turns out to be wrong,
argue with it and change it — do not weaken it to get a green.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

GAME_DIRS = ("sim", "ui")
ALL_GD = ("sim", "ui", "tools", "tests")

findings: list[tuple[str, str, str]] = []   # (severity, rule, detail)


def fail(rule: str, detail: str) -> None:
    findings.append(("ERROR", rule, detail))


def warn(rule: str, detail: str) -> None:
    findings.append(("WARN", rule, detail))


def gd_files(*dirs: str) -> list[Path]:
    out: list[Path] = []
    for d in dirs:
        out.extend(sorted((ROOT / d).rglob("*.gd")))
    return out


def lines_of(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return list(enumerate(text.splitlines(), start=1))


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def strip_comment(line: str) -> str:
    """Crude, but string literals containing # are rare here and a false
    negative is much cheaper than a false positive in a rule check."""
    return line.split("#", 1)[0]


# --- Godot 4 syntax ---------------------------------------------------------
# CLAUDE.md: these are Godot 3 idioms and simply fail to run under 4.x.

def rule_godot4_syntax() -> None:
    old_connect = re.compile(r"""\.connect\(\s*["']""")
    for path in gd_files(*ALL_GD):
        for n, line in lines_of(path):
            code = strip_comment(line)
            if old_connect.search(code):
                fail("godot4-signals",
                     f"{rel(path)}:{n} Godot 3 connect(\"sig\", ...); use sig.connect(callable)")
            if re.search(r"\byield\s*\(", code):
                fail("godot4-await", f"{rel(path)}:{n} yield() is Godot 3; use await")


# --- pause ------------------------------------------------------------------
# CLAUDE.md: get_tree().paused freezes UI input too. The sim owns time_scale.

def rule_pause() -> None:
    for path in gd_files(*ALL_GD):
        for n, line in lines_of(path):
            if "get_tree().paused" in strip_comment(line):
                fail("pause-via-time-scale",
                     f"{rel(path)}:{n} get_tree().paused freezes UI input; the sim owns time_scale")


# --- the sim/ boundary ------------------------------------------------------
# sim/ is a headless library: no Node, no scene API, no wall clock, and it never
# references ui/. This is what lets tools/sim_runner.gd and the tests play whole
# campaigns with no window, and what lets the renderer be thrown away.

SCENE_API = (
    "Node2D", "Node3D", "Control", "Sprite2D", "SubViewport", "Viewport",
    "get_tree()", "get_node(", "add_child(", "queue_redraw(", "CanvasItem",
    "PackedScene", "Input.", "DisplayServer",
)
WALL_CLOCK = ("Time.get_ticks", "Time.get_unix_time", "OS.get_ticks", "Time.get_datetime")


def rule_sim_is_headless() -> None:
    for path in gd_files("sim"):
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"^extends\s+(Node|Control|Node2D|Node3D|CanvasItem)\b", text, re.M):
            fail("sim-headless", f"{rel(path)} extends a Node type; sim/ is RefCounted only")
        for n, line in lines_of(path):
            code = strip_comment(line)
            for token in SCENE_API:
                if token in code:
                    fail("sim-headless", f"{rel(path)}:{n} scene API in sim/: {token}")
            for token in WALL_CLOCK:
                if token in code:
                    fail("sim-wall-clock",
                         f"{rel(path)}:{n} {token} in sim/; campaign time is Campaign.hour")
            if re.search(r"\bres://ui/", code):
                fail("sim-imports-ui", f"{rel(path)}:{n} sim/ must never reference ui/")


# --- one seeded RNG ---------------------------------------------------------
# CLAUDE.md: a global randi()/randf() makes a campaign unreproducible, which
# breaks the balance harness, the determinism check in play.gd, and every bug
# report that quotes a seed. RunRng in sim/rng.gd is the only randomness.

GLOBAL_RNG = re.compile(r"(?<![\w.])(randi|randf|randfn|randomize|randi_range|randf_range|seed)\s*\(")


def rule_one_rng() -> None:
    for path in gd_files(*GAME_DIRS, "tools", "tests"):
        if rel(path) == "sim/rng.gd":
            continue
        for n, line in lines_of(path):
            code = strip_comment(line)
            m = GLOBAL_RNG.search(code)
            if m and not re.search(r"\bfunc\s+" + m.group(1), code):
                fail("one-rng", f"{rel(path)}:{n} global {m.group(1)}(); use the campaign's RunRng")
            if "RandomNumberGenerator.new" in code:
                fail("one-rng", f"{rel(path)}:{n} a second RandomNumberGenerator; use RunRng")


# --- static typing ----------------------------------------------------------
# CLAUDE.md: Godot 4.7 is strict about inference, and untyped code is where
# the runtime type errors that print and carry on come from.

UNTYPED_VAR = re.compile(r"^\s*var\s+[a-z_][a-z0-9_]*\s*(:?=)")


def rule_static_typing() -> None:
    for path in gd_files(*GAME_DIRS):
        bad: list[int] = []
        for n, line in lines_of(path):
            m = UNTYPED_VAR.match(strip_comment(line))
            if m and m.group(1) == "=":
                bad.append(n)
        if bad:
            shown = ", ".join(str(b) for b in bad[:6])
            more = f" (+{len(bad) - 6} more)" if len(bad) > 6 else ""
            fail("static-typing", f"{rel(path)} untyped var at line {shown}{more}")


# --- the invisible-Control trap ---------------------------------------------
# The number one cause of "the game runs but the screen is empty", inherited
# from Deadweight where it cost a session: set_anchors_preset() keeps the old
# offsets, which for a fresh node describe a 0x0 rect.

def rule_control_sizing() -> None:
    for path in gd_files("ui", "tools"):
        for n, line in lines_of(path):
            code = strip_comment(line)
            if "set_anchors_preset(" in code and "set_anchors_and_offsets_preset(" not in code:
                fail("control-sizing",
                     f"{rel(path)}:{n} set_anchors_preset leaves offsets alone and yields a 0x0 "
                     f"node; use set_anchors_and_offsets_preset")


# --- the probe only reads ---------------------------------------------------
# tools/game_probe.gd answers questions about the running game. The moment it
# can also change the game it becomes a second, undocumented way to play, and
# the tests drift away from the game the player gets.

PROBE_MUTATORS = (
    ".dispatch(", ".launch(", ".set_speed(", ".boost(", ".reveal(", ".reassign(",
    ".advance(", ".run_hours(", ".move_to(", ".emit(", "queue_free", "set_process",
    "button_pressed =", ".pressed.",
)


def rule_probe_is_read_only() -> None:
    path = ROOT / "tools" / "game_probe.gd"
    if not path.exists():
        fail("probe-read-only", "tools/game_probe.gd is missing")
        return
    for n, line in lines_of(path):
        code = strip_comment(line)
        for token in PROBE_MUTATORS:
            if token in code:
                fail("probe-read-only", f"tools/game_probe.gd:{n} changes game state: {token}")


# --- every log event has words ----------------------------------------------
# CLAUDE.md: if it matters, it writes a log line — and a log line the player
# cannot read is not one. Every event type sim/ emits must have a wording in
# ui/log_text.gd, or it reaches the player as "<?> type {...}".

def rule_log_events_worded() -> None:
    emitted: dict[str, str] = {}
    for path in gd_files("sim"):
        for n, line in lines_of(path):
            code = strip_comment(line)
            for m in re.finditer(r"""_(?:emit|event)\(\s*"([a-z_]+)\"""", code):
                emitted.setdefault(m.group(1), f"{rel(path)}:{n}")
    words = (ROOT / "ui" / "log_text.gd").read_text(encoding="utf-8", errors="replace")
    worded = set(re.findall(r'^\s*"([a-z_]+)":\s*$', words, re.M))
    for event, where in sorted(emitted.items()):
        if event not in worded:
            fail("log-worded", f"{where} emits '{event}' but ui/log_text.gd has no wording for it")


# --- indentation ------------------------------------------------------------
# CLAUDE.md: tabs, not spaces. Mixed indentation is a parse error.

def rule_tabs() -> None:
    for path in gd_files(*ALL_GD):
        for n, line in lines_of(path):
            if line.startswith("    "):
                fail("tabs-not-spaces", f"{rel(path)}:{n} indented with spaces")
                break


# --- one queue --------------------------------------------------------------
# BACKLOG.md is the only file that may hold a list of future work.

def rule_one_queue() -> None:
    for path in sorted(ROOT.glob("*.md")):
        if path.name == "BACKLOG.md":
            continue
        text = path.read_text(encoding="utf-8", errors="replace").lower()
        if "## next session" in text or "## todo" in text or "## backlog" in text:
            fail("one-queue", f"{rel(path)} holds a queue; BACKLOG.md is the only one")


# --- asset provenance -------------------------------------------------------
# Nothing goes into assets/ without its origin recorded in ASSETS.md: committing
# art to a repository that publishes a web build is distributing it.

ASSET_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".glb", ".gltf", ".ogg", ".wav", ".mp3", ".ttf", ".otf"}


def rule_assets_are_recorded() -> None:
    assets = [p for p in (ROOT / "assets").rglob("*")
              if p.is_file() and p.suffix.lower() in ASSET_SUFFIXES] if (ROOT / "assets").exists() else []
    if not assets:
        return
    doc = ROOT / "ASSETS.md"
    text = doc.read_text(encoding="utf-8", errors="replace") if doc.exists() else ""
    for path in assets:
        if path.name not in text:
            fail("asset-provenance", f"{rel(path)} is committed but not recorded in ASSETS.md")


RULES = [
    rule_godot4_syntax,
    rule_pause,
    rule_sim_is_headless,
    rule_one_rng,
    rule_static_typing,
    rule_control_sizing,
    rule_probe_is_read_only,
    rule_log_events_worded,
    rule_tabs,
    rule_one_queue,
    rule_assets_are_recorded,
]


def main() -> int:
    for rule in RULES:
        rule()

    errors = [f for f in findings if f[0] == "ERROR"]
    warnings = [f for f in findings if f[0] == "WARN"]

    for _, rule, detail in warnings:
        print(f"WARN  [{rule}] {detail}")
    for _, rule, detail in errors:
        print(f"ERROR [{rule}] {detail}", file=sys.stderr)

    if errors:
        print(f"\nhouse rules: {len(errors)} violation(s), {len(warnings)} warning(s)",
              file=sys.stderr)
        return 1
    print(f"house rules OK ({len(RULES)} rules, {len(warnings)} warnings)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
