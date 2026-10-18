# BACKLOG

The one ordered queue. Nothing else in this repository may hold one
(`tools/check_rules.py` enforces it). Top of the list is next. Ordered by
**most strategic depth for the least build**, because the strategic layer is
the whole game.

Each entry ends with a running, clickable game and green `tools/verify.sh`.

## Next

1. **Fatigue and rotation.** A soldier back from an operation is *Tired* for a
   few days: deployable, at a penalty. This is the single cheapest change that
   makes roster depth matter, and it is what turns "send the best four" into
   a decision. Without it, the second encounter is the first one again.

2. **Consequences for ignoring and losing.** Right now an expired or failed
   operation costs only the reward. In Long War a missed operation moves the
   region: Custodian strength up, haven rebels lost, retaliation risk. Without
   this, ignoring the board is free and the intel economy is optional. The
   region strength pips on the map are already drawn for this.

3. **A sink for supplies.** Recruiting (and healing faster, maybe). Supplies
   currently accumulate with nothing to buy, which makes the haven's
   supply job a fake decision. Should land with or right after 2.

4. **Mimics in the haven.** The Faceless analog, done as this game's own
   thing: some rebels are Mimics. They poison intel, and an investigation
   operation can root them out. The theme of the game, on the strategic layer.

5. **A second haven, and contacting regions.** Expansion, the second resource
   sink, and the first time the map is a choice.

6. **Retaliation and liberation.** The region chain from Long War: strength
   climbs, the machines retaliate against havens, a liberation chain pushes
   them back.

7. **Research and gear.** EMP upgrades, armour, scanners — things that change
   the autoresolve's numbers and are bought with supplies and time.

8. **The Prototypes** (Chosen analog): three named machine commanders that
   learn the player's doctrine and field counters to it.

9. **The doom clock.** The Custodian's project, and dark events.

10. **Save / load.** The campaign is a few plain RefCounted classes, so this is
    straightforward; it waits only until the shape of the state settles.

## Art and sound

- **A theatre map plate.** The map is code-drawn placeholder (`ui/map_view.gd`
  says so on screen). Terrain, coasts and borders belong in a plate under
  `assets/`, recorded in an `ASSETS.md`; code keeps drawing state on top.
  `tools/check_rules.py` already refuses committed art without a provenance row.
- **Portraits and class icons** for the roster and the report.
- **Sound.** None yet.

## Open questions for the owner

- **Is the first encounter too safe?** Played "by the book" (four soldiers
  with a Scout, composition revealed, launched at 100%) it is a 100% win with
  ~0.01 dead (`verify sim`). Mistakes cost: no Scout roughly quintuples the
  wounds; launching at 50% drops the win rate to ~40%. That is a tutorial
  shape. If the first fight should cost something even when played well, say
  so — it is a numbers change in `data/`, not code.
- **Cautious ROE does not currently save lives against Standard** at 50%
  infiltration (both ~0.49 dead per fight; Hold ~1.2). The parting volley on
  withdrawal eats the benefit. It may be right — breaking contact under fire
  *is* dangerous — but it means Cautious only trades wins for nothing. Decide
  whether withdrawing should be safer.
- **The setting** in `DESIGN.md` is a placeholder, as are all names.
- **Should the planner's assessment show a number** ("wins 63 of 80") or only
  a word ("Fair")? A number is honest and readable; it also makes the game
  easier to solve.
