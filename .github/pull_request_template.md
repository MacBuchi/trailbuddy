## What

<!-- What changes and why. English, as everywhere on GitHub. -->

## Tests

<!-- What was run; which test was made red on purpose (counter-probe). -->

## Checklist

- [ ] Visible feature? Entry in `kFeatureHighlights` plus its demo in `highlight_demos.dart` — or one sentence why not.
- [ ] Version bump + `CHANGELOG.md` block if anything under `lib/`, `web/` or `assets/` changed.
- [ ] New network target, permission or data category? → `web/datenschutz.html`, its English `web/privacy.html` and `docs/play-console.md` in this PR.
- [ ] Schema change? → `patch_NNN`, `schema.sql` structure **and** seed list; `tool/schema_check.sh` extended for new columns/embeds/RPCs.
- [ ] Concept touched? → `docs/konzept-trails.md` says the same thing as the code.
- [ ] UI a tour points at changed (map buttons, tool rail, filter sheet, trail sheet, bottom bar)? → anchors still there; `map_tour_flow_test` green.
