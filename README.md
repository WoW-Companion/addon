# WoW Companion addon

This addon shows your personal advice inside World of Warcraft: what to do next, in order, with a numbered
route drawn on your map. It only shows things; it never plays the game for you.

![The WoW Companion panel in the game](docs/images/panel.png)

## Works with the WoW Companion app

The addon is a window, and the app is what fills it. Three small pieces work together:

- **ForeverScribe** (another addon) writes down what your character has: level, quests, bags and talents.
  WoW only saves that to disk when you `/reload`, log out or quit.
- **The WoW Companion app** (a small window beside the game) reads that save within seconds, works out your
  next steps and the best route, and writes the advice back into the game's addon folder.
- **This addon** shows that advice in the game: the panel, the numbered route on your map and the minimap
  button. Quest counts update live as you play.

**The loop:** play, `/reload` (WoW saves), the app writes fresh advice within seconds, `/reload` again to see
it. You can also ask a question in the game; the app answers it in its own window.

Without the app, the addon has nothing to show beyond live quest progress.

For setup, see [Getting Started](https://github.com/WoW-Companion/advisor/blob/main/docs/getting-started.md)
in the advisor repo.

## A tour of the addon

**The panel.** Type `/wowc` to open or close it, and drag it to move it. It lists your next steps, grouped in
sections you can collapse. Hover a line and the matching badge on the map lights up (and the other way round).
Click a quest to open it in your quest log, or click anything else, or right-click, to open a small detail
card. The card has a question already filled in: send it to the app, or copy it into your own AI chat. You can
also type `/ask <question>` any time. If the advice looks old, the panel says so.

**The route on the map.** Your steps appear on the world map as numbered gold badges, with lines between the
steps still to do. A small line reading `Step 3/12: <quest> · 85 yd NE` tracks the next step and ticks off as
you accept and turn in quests. This needs the plan file the app writes, so nothing is drawn until the app has
run.

**The minimap button.** Hover it to see how old your advice is. Left-click shows or hides the panel,
right-click opens the options, shift-left-click shows or hides the route on the map, and you can drag it
around the minimap.

![The minimap button and its tooltip](docs/images/minimap-button-tooltip.png)

**The options window.** Almost every choice is a setting, and changes apply at once, with no `/reload`: what
is shown, hover and click behaviour, and colours, opacity and sizes. A small **Reset** button next to any
changed setting puts that one back, and **Reset all** restores everything.

![The options window](docs/images/options-window.png)

![Choosing the route colour](docs/images/options-route-colour.png)

Hovering an item or quest in the game's own tooltips also adds a gold "WoW Companion" line when it is one of
your upgrades or next steps. You can turn that off in the options.

## Install

1. Download the latest `WoWCompanion-<version>.zip` from the
   [Releases](https://github.com/WoW-Companion/addon/releases) page.
2. Unzip it into your game's `Interface\AddOns` folder. Two folders, `WoWCompanion` and
   `WoWCompanion_Digest`, land side by side.
3. Fully quit and restart the game. This is needed the first time, and whenever a new folder is added,
   because the game only finds new addon folders at startup. If an update adds no new folder, `/reload` is
   enough.

To update, delete the old `WoWCompanion` folder, unzip the new release, then restart (or `/reload` as above).
The zip never contains `WoWCompanion_Digest/Digest.lua`, because that file holds your advice and is written by
the app, so unzipping never overwrites it. Until the app writes it, the addon treats it as empty. The digest
covers every character; if the one you are on has no entry, the panel shows a short hint.

## Slash commands

| Command | What it does |
| --- | --- |
| `/wowc` | Show or hide the panel |
| `/wowc options` | Open the options window (`/wowc settings` and `/wowc config` do the same) |
| `/wowc plan …` | Show or hide the next-step line; `map`, `lines` and `arrows` toggle the badges, route lines and arrowheads; `size small\|normal\|large` sets the badge size |
| `/wowc reset visuals` | Put every colour, opacity and size back to its default (asks first) |
| `/wowc reset all` | Put every setting back to its default; saved positions stay (asks first) |
| `/ask <question>` | Queue a question for the app; `/reload` to hand it over |

`/wowc status` prints versions and digest age, and `/wowc help` lists everything, including `/wowc reset`
(restores the panel position).

## Read-only promise

This addon only reads game state and displays it. It never casts spells, uses items, sends chat, whispers,
mail or addon messages, buys, sells, posts or bids, automates input or movement, or moves data out of the game
by any side channel. `ReloadUI` is only ever called as the direct result of your own slash command. A test
(`tests/guard.lua`) scans the addon's Lua for forbidden calls and fails the build if it finds one.

## For developers

`make verify` runs the read-only guard and the tests with `luajit` against a stubbed client API
(`tests/wow_stub.lua`); the game is not needed. `make package` builds the release zip.

- Digest file format: `docs/digest-format.md`. Ask queue format: `docs/ask-format.md`.
- The app writes `WoWCompanion_Digest/Digest.lua` (the digest) and, with advisor 0.6.0 or later,
  `WoWCompanion_Digest/Plan.lua` (the route). Both are data-only; the plan refreshes at the next `/reload`.
- Upgrading from 0.1.x: the in-game Ask box, History and the `WoWCompanion_Answers` folder are gone. A
  leftover folder is harmless; the addon never deletes your files.

## License

MIT, see `LICENSE`. Copyright (c) 2026 WoW Companion contributors.

WoW Companion is a fan project. It is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc.
