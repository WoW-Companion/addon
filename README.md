# WoW Companion addon

A small in-game panel for World of Warcraft: Forever that shows the advice the
WoW Companion writes for you. Type `/wowc` to open or close it; drag it to move
it, and it remembers where you left it. It shows the digest the companion writes into the data-only
`WoWCompanion_Digest` addon (format: `docs/digest-format.md`), or says that no
advice has been written yet.

Type `/ask <question>` (or `/wowc ask <question>`) to queue a question. It is saved to
SavedVariables and goes out on `/reload` or logout; answers appear under the question once the
companion writes them into `WoWCompanion_Answers` (format: `docs/ask-format.md`).

## Install

Copy the `WoWCompanion`, `WoWCompanion_Digest` and `WoWCompanion_Answers` folders into `_forever_\Interface\AddOns`, then restart
the game or type `/reload`. `make package` builds `dist/WoWCompanion-<version>.zip`
if you prefer a zip.

## Read-only promise

This addon only reads game state and displays it. It never casts spells, uses
items, sends chat, whispers, mail or addon messages, buys, sells, posts or bids,
automates input or movement, or moves data out of the game by any side channel.
`ReloadUI` is only ever called as the direct result of your own slash command.
A test (`tests/guard.lua`) scans the addon's Lua for forbidden calls and fails
the build if it finds one.

## Development

`make verify` runs the read-only guard and the tests with `luajit` against a
stubbed client API (`tests/wow_stub.lua`); the game is not needed.

## License

MIT, see `LICENSE`. Copyright (c) 2026 WoW Companion contributors.

WoW Companion is a fan project. It is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc.
