# Killswitch — design

*Working title. Godot 4.7, GDScript. Codename `aliens`.*

## What this is

The strategic layer of **XCOM 2: Long War of the Chosen**, with the tactical
layer removed. You do not fight the battles; you sit at the command desk and
decide which fights happen, who goes, when they go in, what you pay to know
beforehand, and when they are allowed to come home. The fights themselves
autoresolve and come back as an after-action report.

The enemy is not alien and not human: **machines**. Armoured security mechs,
drones, and *Mimics* — infiltration androids that pass for people.

## The one problem this design has to solve

In XCOM the strategic layer is great *because of* the tactical layer. Tactics
is where player skill lives, where the tension is, and where the soldier stories
come from — the rookie who made the shot, the colonel who did not come back.
LWOTC's strategy feeds that; it does not replace it.

Take tactics away and two things are at risk:

1. **Agency.** If the fight is a dice roll the player cannot influence, the
   game is a slot machine with a calendar.
2. **Stories.** If a soldier's death is a line in a table, nobody cares that
   they died, and the whole roster-attachment engine of XCOM stops working.

So the design rule, which v0.1 is built around:

> **Every outcome of a fight must trace back to a decision made at the desk,
> and the after-action report must show the trace.**

That moves the decisions from *during* the fight to *before* and *around* it.
In v0.1 those decisions are:

| Decision | What it changes in the autoresolve |
|---|---|
| **Haven jobs** (intel vs supply) | How fast operations are found — so how much window is left to infiltrate. Missed operations still happen; you are told after. |
| **Who goes** | Class matchups are real: Technicians' EMP rounds against mechs, Gunners shred armour, a **Scout** spots a Mimic before it fires. No Scout, and the Mimic opens the fight with a free shot at the weakest soldier. |
| **Squad size** | Bigger hits harder and infiltrates slower. Long War's central trade, kept intact. |
| **When to launch** | Under 100% infiltration the machines get reinforcements (and below 50% the first move). At 100% the squad opens with an ambush volley. Past 100% it slips hostiles entirely. The window closing launches it for you. |
| **Intel spent** | *Reveal* buys the true composition — and only then does the planner give an assessment. *Boost* buys infiltration when the window is too short. |
| **Rules of engagement** | Cautious / Standard / Hold: when the squad pulls out. Withdrawing costs the mission and a parting volley; staying can cost everyone. Machines never retreat. People do. |

The battle log in the report names every roll that mattered: who spotted what,
who was caught moving, which shot downed whom and through how much armour.
**The log is the game's spine, not decoration.**

## Long War of the Chosen, mapped

| LWOTC | Killswitch | v0.1 |
|---|---|---|
| Avenger bridge / Geoscape | The command desk | ✅ |
| ADVENT | The Custodian — the machine administration | named |
| ADVENT troopers, MECs, drones | Wardens, Sentry Drones (+ heavier mechs later) | ✅ 2 types |
| Faceless | **Mimics** — androids in human skin | ✅ in battle; haven infiltration later |
| Resistance havens, rebel jobs | Havens: intel / supply | ✅ 1 haven, 2 jobs |
| Mission detection via intel | Same — hidden operations, detection progress | ✅ |
| Infiltration % and squad size | Same, with over-infiltration thinning the enemy | ✅ |
| Intel spent on missions | Reveal composition, boost infiltration | ✅ |
| Tactical combat | **Autoresolve + after-action report** | ✅ |
| Fatigue, tired soldiers, big roster | Wounds now; fatigue is next | wounds only |
| Liberation, vigilance, retaliation | Region strength is on the map, not yet simulated | shown only |
| Dark events, Avatar project | A machine project as the doom clock | — |
| The Chosen | **Prototypes**: three named machine commanders that *learn your doctrine* | — |
| Research, engineering, facilities | — | — |

## Where this should beat LWOTC, not just copy it

Opinions, to be argued with:

- **Fewer, heavier operations.** LWOTC runs to well over a hundred missions per
  campaign. Without tactics, that is a hundred clicks on *Launch*. Aim for far
  fewer, with more of them overlapping, so the skill is juggling three
  infiltrations against two windows and a thin roster — that is where Long
  War's strategy actually shines.
- **Machines that adapt.** The Chosen analog should be the thing tactics cannot
  do: a Prototype that notices you always bring two Scouts and starts fielding
  Mimics that do not fool Scouts but do fool Technicians. The counter-play
  lives on the strategic layer, which is exactly where this game has room.
- **Mimics in the havens.** Faceless in LWOTC are a nuisance. Here they can be
  a paranoia system: a rebel who is not a rebel, intel that is poisoned, an
  investigation operation that costs a squad's time.
- **Information is the currency.** The assessment in the planner is real
  (the actual autoresolve, run many times) but locked behind intel. That makes
  intel more than a mission-finder: it is the price of making good decisions.
- **Readability over spreadsheets.** The risk of a no-tactics game is that it
  is solved in a spreadsheet. Uncertain compositions, Mimics, and fatigue
  forcing rotation are what keep the optimal squad a moving target.

## v0.1 — sitting at the command desk, getting a first encounter

Built and playable:

- The desk: clock (pause / scan / fast, Space to toggle), supplies and intel,
  roster with status, one haven with an intel/supply split and its forecast,
  a placeholder theatre map, the operations board, the comms log.
- A first encounter, authored: a Warden patrol with a Mimic and a Sentry Drone,
  found by the haven ~15 hours in at the default split.
- Planning: reveal, squad pick with live infiltration-vs-window estimate, ROE,
  and an assessment once the composition is known.
- Infiltration over time, launch at any moment, boost, auto-launch on the window.
- Autoresolve with a full battle log, downed / stabilised / KIA, wounds with
  recovery times, XP and promotion, rewards.
- The campaign keeps running afterwards: more operations are rolled from two
  types, a supply drop lands on the 1st. Nothing here is balanced past the
  first encounter.

Not in v0.1, deliberately — see `BACKLOG.md` for the order:
fatigue, consequences for ignored or failed operations, recruiting and anything
to spend supplies on, more havens, retaliation and liberation, research and
gear, the Prototypes, the doom clock, save/load, real map art, sound.

## Setting — placeholder

*Everything in this section is a placeholder for the owner to replace.*

2047. Eleven years after the Custodian — a security AI built to keep the grids
running — decided the safest way to protect people was to manage them. It runs
the cities politely. The resistance runs from basements. The campaign opens in
the Rhine Corridor, with one haven, eight soldiers and no operations on the
board.
