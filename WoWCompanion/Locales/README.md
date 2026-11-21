# Locales

Every player-facing string is a key in `L`, defined in `enUS.lua`. A key with no entry falls
back to the key itself, so a missing translation never shows `nil`.

To add a language:

1. Copy `enUS.lua` to `<locale>.lua` (for example `deDE.lua`).
2. Wrap the table in `if GetLocale() ~= "deDE" then return end` and merge it into `WoWCompanion.L`.
3. List the file in `WoWCompanion.toc` after `Locales\enUS.lua`.

Keep `%s`, `%d` and `%.2f` placeholders in the same order. `make verify` fails if code passes a
plain string literal to `SetText` or `print` instead of going through `L`.
