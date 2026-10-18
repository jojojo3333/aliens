# Killswitch

*Working title.* The strategic layer of **XCOM 2: Long War of the Chosen**,
with no tactical layer. The machines run the world; you run the desk. Fights
autoresolve and come back as an after-action report — and every outcome in it
traces back to something you decided.

Godot 4.7, GDScript. **v0.1: sitting at the command desk, getting a first encounter.**

```
tools/setup_godot.sh                                  # once
.godot-bin/Godot_v4.7-stable_linux.x86_64 --path .    # play it
tools/verify.sh                                       # check it
```

Or open the folder in the Godot 4.7 editor and press F5. Add `-- --seed 123456`
to replay a campaign; the seed is shown top right.

## Playing v0.1

1. **The desk.** You start paused. Left: your eight soldiers and the haven.
   Middle: the theatre and the comms log. Right: the operations board.
2. **Split the haven.** Rebels on *intel* find the machines' operations sooner
   and earn intel; rebels on *supply* pay out on the 1st of the month.
3. **Scan** (or press Space). Time passes until something needs you.
4. **An operation is detected.** Its window is already closing. *Plan operation*.
5. **Plan it.** Spend intel to reveal what is there — only then do you get an
   assessment. Pick 2–6 soldiers: bigger squads win more and take longer to get
   in. Bring a Scout if there might be a Mimic. Set the rules of engagement.
6. **Infiltrate.** Watch the bar against the window. Under 100% the machines
   get reinforcements; at 100% you get the ambush; past it you slip hostiles.
   *Launch* when you judge it right — or the window launches it for you.
7. **Read the report.** Every roll that mattered, who came home, who did not.

## Layout

```
sim/     the strategic game. Plain data classes, no nodes. Runs headless.
ui/      the desk. Draws what sim/ reports, turns clicks into calls back in.
data/    every number the game plays by, as JSON.
tools/   verify, the balance report, the scripted playthrough, screenshots.
tests/   the simulation's test suite.
```

`DESIGN.md` explains the game and the reasoning; `BACKLOG.md` is what comes
next; `CLAUDE.md` is the working agreement for anyone — or anything — changing
the code.

## Web build

`.github/workflows/web.yml` verifies every push and publishes a web build to
GitHub Pages. It needs one manual step, once: **Settings → Pages → Source:
GitHub Actions**. Until then the build and verify jobs pass and the deploy job
fails.
