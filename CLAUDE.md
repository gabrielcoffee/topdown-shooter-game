# CLAUDE.md

Top-down zombie shooter in LÖVE (Lua). Plan in PLAN.md, progress tracking in PROGRESS.md.

## Working with Gabriel

- **After implementing any feature, end with a simple summary of the most important data/tune values**, as a bullet list, so he can track what's going on and know what to ask to change. Example:
  - ak reload time: 2.7s
  - pistol reload time: 2s
- **Commit only when a feature feels finished** — not every prompt. Commits authored as gabrielcoffee, never any Claude attribution or Co-Authored-By trailer. Push after committing.
- Design/plan discussions stay at macro level (which class owns what, how pieces talk). No function-by-function detail unless asked.
- **`tune.lua` is the source of truth for all gameplay numbers.** Gabriel edits it directly (sometimes in other sessions) — always re-read it before reporting or changing values, never trust conversation memory. New tunable values go in tune.lua, not hardcoded. U key in game reloads it + restarts run.
