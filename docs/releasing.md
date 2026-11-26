# Changes and releases

**A normal change never edits the TOC `## Version`, the What's-new lines (`WHATS_NEW_*` in
`WoWCompanion/Locales/enUS.lua`), the `WC.CHANGELOG` table in `WoWCompanion/WhatsNew.lua`, or any CHANGELOG.**
Two branches that bump the version conflict; fragments never do.

## A change

Add `changes/<MISSION-ID>.md` with its player-facing What's-new lines: one line per bullet (`- text`), plain
words for a player, no `/reload` advice. Blank lines and lines starting with `#` are ignored. A purely internal
change adds no fragment.

`make verify` runs `scripts/check-changes.sh`, which fails a branch whose commits change the version or What's
new outside a release-prep commit, with "use changes/<ID>.md".

## A release

`make release-prep` (a maintainer, once, on main or a release branch) reads `changes/*.md` in id order, bumps
`## Version` in both TOCs to the next patch (`BUMP=minor make release-prep` for a minor), adds the
`WHATS_NEW_<version>_<n>` lines and the `WC.CHANGELOG` entry, and deletes the fragments. It refuses when there
are none. Commit the result with the trailer `Release-Prep: true` in the message (a commit that deletes a
`changes/*.md` file also counts). `release.yml` publishes when the TOC version changes on main.
