# CLAUDE.md — working agreement

Read this, then `DESIGN.md`, then `BACKLOG.md`, before doing anything.
`BACKLOG.md` is the queue of everything known to be missing or wanted — and it
is the **only** file that holds one.

## What this is

An XCOM 2: Long War of the Chosen strategy layer with the tactical layer taken
out. Godot 4.7, GDScript. Working title **Killswitch**. You run the command
desk; the fights autoresolve and come back as an after-action report. The enemy
is machines: mechs, drones, and Mimics — androids that pass for people.

`DESIGN.md` holds the one rule the game is built on: **every outcome of a fight
must trace back to a decision made at the desk, and the report must show the
trace.** A change that makes the autoresolve less explainable is a regression
even if every test is green.

Most of the practice below is inherited from Deadweight (the owner's other
project, `cowboysandpirates`), where each rule was learned by breaking it.

## Slice discipline — the most important rule

**Every slice ends with a running, clickable game.** Never leave the project in
a state where `godot --path .` does not launch the desk. What is next is at the
top of `BACKLOG.md`. Build that, and stop at the boundary of what was asked.
If you finish early, the answer is more tests, not more features.

## How this project is built

**`sim/` holds no Node or scene API.** Plain `RefCounted` classes over data. The
whole campaign runs headless — that is how the tests and the balance report
play hundreds of campaigns, and why `ui/` can be thrown away and rebuilt.
`sim/` never reads the wall clock: campaign time is `Campaign.hour`.

**`ui/` draws what `Campaign` reports and turns clicks into calls back in.** It
decides nothing about the game.

**One seeded RNG**, `RunRng` in `sim/rng.gd`. A global `randi()` makes a
campaign unreproducible: no determinism check, no replayable bug report.

**Balance numbers live in `data/*.json`.** Code reads them; code does not
contain them.

**If it matters, it writes a log line.** State the player needs must not be
carried by colour or animation alone. Every event `sim/` emits has wording in
`ui/log_text.gd`, and `verify rules` fails on one that does not.

**Static typing.** `var hours: int = 30`, `func launch() -> void:`.

**The map is placeholder art.** Code draws *state* — contact, havens, markers,
infiltration. Terrain belongs in an art plate under `assets/`, recorded in an
`ASSETS.md` before it is committed (this repository is public and publishes a
web build, so committing art is distributing it).

## Godot 4 gotchas — these have cost real time before

- Godot 4 signal syntax only: `button.pressed.connect(_on_pressed)`.
- No `yield` — use `await`.
- **Never use `get_tree().paused` for the game pause.** It freezes UI input
  too. The sim owns `time_scale` and `Campaign.advance()` respects it.
- **Every UI node must be inside a container or have an explicit size.**
  `set_anchors_preset()` on a fresh node yields a 0x0 rect; use
  `set_anchors_and_offsets_preset()`.
- **Space is `ui_accept`.** A focused button eats it. The desk takes Space in
  `_input`, ahead of the GUI, for exactly that reason.
- **New `class_name` files need an import** before a `--script` run can see
  them. `verify static` imports first.
- Indentation is tabs. `class_name` must be globally unique.

## Verify after every change — run these yourself, do not ask

```
tools/setup_godot.sh       # once: fetches the pinned Godot 4.7 into .godot-bin/
tools/verify.sh rules      # the house rules, as checks instead of prose
tools/verify.sh static     # parses, imports, and validates data/
tools/verify.sh sim        # headless test suite + balance report
tools/verify.sh play       # the desk itself, clicked through and asserted
tools/verify.sh            # all four
```

**`play` is the one that sees the game the player sees.** It boots
`main.tscn`, clicks the real buttons with real mouse events under a virtual
display, steps the clock at a fixed 1/30 s, and asks the running game what is
true through `tools/game_probe.gd` — which may only read.

**Mutation testing**: deliberately break the code, run the check, confirm it
goes red, put the code back. If the check stays green it was decoration.
Re-import between the edit and the run, or Godot may serve the old script.

**A check that cannot fail is worth nothing — and a check that can hang is a
bug.** Every loop in a harness has a bound.

**A change is not done until `tools/verify.sh` is green.** Never weaken a test,
widen a tolerance, or skip a case to get there. If a test is wrong, say so and
say why. If you cannot run the command, say so plainly.

**Report `[PLAY-GATED]` numbers, never tune them.** The balance report prints
win rates and casualties; whether they are *right* is a question about feel,
and nobody can answer it from a headless container. Only the *directions* are
asserted (a Scout matters against a Mimic, infiltrating longer is safer).

## Document map

| File | What it is |
|---|---|
| `DESIGN.md` | What the game is, the LWOTC mapping, the autoresolve contract, what v0.1 contains |
| `BACKLOG.md` | **What is next.** The one ordered queue, and the open questions for the owner |
| `README.md` | How to run it and what you are looking at |
| `CLAUDE.md` | This file |
