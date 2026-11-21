# WoW Companion addon

A small in-game panel for World of Warcraft: Forever that shows the advice the
WoW Companion writes for you. Type `/wowc` to open or close it; drag it to move
it, and it remembers where you left it. It shows the digest the companion writes into the data-only
`WoWCompanion_Digest` addon (format: `docs/digest-format.md`), or says that no
advice has been written yet.

Type `/ask <question>` (or `/wowc ask <question>`) to queue a question. It is saved to
SavedVariables and goes out on `/reload` or logout; answers appear under the question once the
companion writes them into `WoWCompanion_Answers` (format: `docs/ask-format.md`).

Hover a line that has an item to see its tooltip. Click a section header to collapse or expand it; the
choice is remembered. The panel shows how old the digest is and, past 12 hours, reminds you to refresh it.
`/wowc help` lists the commands; `/wowc reset` restores the panel position and expands all sections.

## Install

1. Download the latest `WoWCompanion-<version>.zip` from the
   [Releases](https://github.com/WoW-Companion/addon/releases) page of this repo.
2. Unzip it into `_forever_\Interface\AddOns`. The zip holds the three folders `WoWCompanion`,
   `WoWCompanion_Digest` and `WoWCompanion_Answers` at its top level, so they land side by side.
3. Fully quit and restart the game the first time, and whenever a new folder is added: the game only
   discovers a new addon folder at startup, so `/reload` is not enough.

To update safely, delete the old `WoWCompanion` folder, unzip the new release over your install, then
fully restart the game (or `/reload` if no folder was added). The zip deliberately holds no
`WoWCompanion_Digest/Digest.lua` or `WoWCompanion_Answers/Answers.lua`: those files hold your data and are
written by the companion, so unzipping never overwrites them. The addon treats them as empty until the
companion writes them. A leftover `WoWCompanion` folder from early versions breaks schema 2.0 digests,
hence the delete. Developers can build the same zip with `make package`.

The digest holds every character (schema 2.0, see `docs/digest-format.md`). If the character you are
logged in on has no entry, the panel shows a short hint with the steps to get one.

For the rest of setup (connecting your AI client and writing the digest), see `docs/quickstart.md` in
the advisor repo.

`/wowc status` prints the addon version, client build, digest age, queued questions, the age of the
last answer and whether the two slot addons are installed. 
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
