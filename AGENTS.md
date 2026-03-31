# AGENTS

Shared project instructions for coding agents and collaborators.

## Scope
- This file applies to the entire repository.
- Prefer small, targeted changes; avoid broad refactors unless requested.

## Build And Run
- Build and deploy with:
  - `./shell/build.sh <path-to-asm-file>`
- Primary example used in this repo:
  - `./shell/build.sh projects/sprite_demo/main.asm`
- VS Code task `Run on C64` is expected to work with active file input.

## Assembly Project Conventions
- Target: C64 (6502 assembly, 64tass-compatible syntax).
- Keep map/tile data human-editable and grouped by level row labels.
- Preserve tile-id semantics unless explicitly changed:
  - `0` sky/empty
  - `1` ground
  - `2` stone
  - `3` grass/top
  - `4` flag
- Keep comments short and practical; explain only non-obvious logic.

## Gameplay/Design Guardrails
- Keep levels beatable from the default spawn.
- If moving win targets/flags, ensure they remain reachable within camera/scroll limits.
- For end states (game over / final win), preserve restart flow and prompt behavior.

## Level Design Checklist
- Flag placement: ensure at least one `4` tile is in a reachable world column.
- Camera reachability: highest visible world column is `max_scroll + 39`; keep the required flag route at or before that.
- Traversal route: ensure there is at least one continuous playable path from spawn to flag (ground, ledges, or platforms).
- Holes: if a pit is wider than the normal jump, provide a required alternate crossing (platform/step chain) and a way to land safely.
- Verticality: if using all 5 tile rows, include at least one practical climb route up and one route back down (or a safe drop).
- Regression check: after level/map edits, build and run once to verify the flag can still be reached in-game.

## Editing Rules
- Do not revert unrelated user changes.
- Preserve existing naming/style where practical.
- After gameplay/map edits, run a build to validate assembly output.

## When Unsure
- Prefer asking one focused question instead of making sweeping assumptions.
