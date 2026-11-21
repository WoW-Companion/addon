# WoW Companion addon

The addon is **optional**. The WoW Companion overlay is the recommended way to get advice and
answers while you play; ForeverScribe is required, because it captures
your character for the digest. The addon adds what only an addon can do inside the game UI, and gives
players who can't run the overlay (a Mac, exclusive fullscreen, no extra app) a way to see advice.

What the addon adds:

- **Advice panel.** `/wowc` opens or closes it; drag it to move it. It shows the digest the companion writes
  into the data-only `WoWCompanion_Digest` addon (format: `docs/digest-format.md`), with a compact mode,
  collapsible sections, a hint when the advice may be out of date, and one entry per character.
- **Tracker line.** A small "Next up" line with your next step (off by default; see settings).
- **Minimap button** with a tooltip showing the digest age; `/wowc status` prints versions and queue state.
- **Game tooltips.** Hover an item that is an upgrade in your digest, or a quest that is one of your next
  steps, and a gold "WoW Companion: ..." line is added. Turn it off in settings.
- **Ask about this.** Right-click a panel line, or type `/ask <question>`, to queue a question. It is saved to
  SavedVariables; `/reload` and the overlay answers it (format: `docs/ask-format.md`). The addon shows no
  answers itself.

Hover a line that has an item to see its tooltip. Click a section header to collapse or expand it; the
choice is remembered. `/wowc help` lists the commands; `/wowc reset` restores the panel position.

**Upgrading from 0.1.x:** the in-game Ask box, History and the `WoWCompanion_Answers` folder are gone in 0.2.0.
A leftover `WoWCompanion_Answers` folder is harmless and can be deleted; the addon never deletes your files.

## Install

1. Download the latest `WoWCompanion-<version>.zip` from the
   [Releases](https://github.com/WoW-Companion/addon/releases) page of this repo.
2. Unzip it into `_forever_\Interface\AddOns`. The zip holds the two folders `WoWCompanion` and
   `WoWCompanion_Digest` at its top level, so they land side by side.
3. Fully quit and restart the game the first time, and whenever a new folder is added: the game only
   discovers a new addon folder at startup, so `/reload` is not enough.

To update safely, delete the old `WoWCompanion` folder, unzip the new release over your install, then
fully restart the game (or `/reload` if no folder was added). The zip deliberately holds no
`WoWCompanion_Digest/Digest.lua`: that file holds your data and is
written by the companion, so unzipping never overwrites it. The addon treats it as empty until the
companion writes it. A leftover `WoWCompanion` folder from early versions breaks schema 2.0 digests,
hence the delete. Developers can build the same zip with `make package`.

The digest holds every character (schema 2.0, see `docs/digest-format.md`). If the character you are
logged in on has no entry, the panel shows a short hint with the steps to get one.

For the rest of setup (connecting your AI client and writing the digest), see `docs/quickstart.md` in
the advisor repo.

`/wowc status` prints the addon version, client build, digest age, queued questions, and whether the digest slot addon is installed. 
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
