-- WoW Companion: the enUS strings. Every player-facing string lives here; see Locales/README.md.
-- A key with no entry falls back to the key itself, so a missing translation never shows nil.

WoWCompanion = WoWCompanion or {}
local WC = WoWCompanion

local L = {
    ADDON_NAME = "WoW Companion",

    -- Panel
    COMPACT = "Compact",
    FULL = "Full",

    -- Digest
    NO_ADVICE = "No advice yet \226\128\148 the companion hasn't written a digest.",
    STALE_NOTE = "Ask your AI client to refresh your digest, then /reload.",
    UNKNOWN_SCHEMA = "This digest uses an unknown format (schema %s); update the addon.",
    NO_ENTRY = "No advice for %s yet.",
    HINT_RELOAD = "1. Type /reload so ForeverScribe saves this character.",
    HINT_ASK = "2. Ask your AI to update your WoW Companion digest (or run: wowc-advisor digest).",
    HINT_RELOAD_AGAIN = "3. Type /reload again.",
    DIGESTS_HERE = "Digests here for: %s",
    DIGEST_HEADER = "%s \226\128\148 updated %s",
    LINE = "  - %s",
    OPEN_SECTION = "[-] %s",
    CLOSED_SECTION = "[+] %s",
    AGE_NOW = "just now",
    AGE_MINUTES = "%d min ago",
    AGE_HOURS = "%d h ago",
    AGE_DAYS = "%d d ago",
    next_quests = "Next quests",
    upgrades = "Upgrades",
    keep_materials = "Keep materials",
    notes = "Notes",
    dungeons = "Dungeons",
    talents = "Talents",
    DUNGEON_NAME = "%s: ",
    OLDER_THAN_CAPTURE = "Advice may be out of date: /reload (the overlay refreshes it) or run wowc-advisor digest.",
    OUT_OF_DATE_SHORT = "Advice may be out of date",

    -- Button tooltip
    TIP_DIGEST = "Digest: updated %s",
    TIP_OUT_OF_DATE = "Advice may be out of date",
    TIP_DIGEST_NONE = "Digest: none yet",
    TIP_QUEUED = "Questions queued: %d",
    TIP_CLICK = "Click to open",

    -- Ask about this (right-click a digest line) and /ask
    ASK_QUEUED = "Queued for WoW Companion. /reload and the overlay will answer it.",
    ASK_ITEM_SUBJECT = "%s (item %d)",
    ASK_ABOUT_quest = "Where do I go for %s, and what's the fastest route?",
    ASK_ABOUT_upgrade = "Where does %s drop, and is it worth farming?",
    ASK_ABOUT_material = "What should I make with %s?",
    ASK_ABOUT_dungeon = "Should I run %s now, and what should I bring?",
    ASK_ABOUT_talent = "Why %s next for my spec?",

    -- Settings
    SCALE_LABEL = "Panel scale: %.2f",
    LOCK_PANEL = "Lock panel position",
    OPEN_ON_LOGIN = "Open the panel on login",
    SHOW_SECTION = "Show %s",
    SECTION_quests = "Next quests",
    SECTION_upgrades = "Upgrades",
    SECTION_materials = "Keep materials",
    SECTION_notes = "Notes",
    SECTION_dungeons = "Dungeons",
    SECTION_talents = "Talents",

    FONT_LABEL = "Text size: %s",
    FONT_small = "Small",
    FONT_normal = "Normal",
    FONT_large = "Large",
    COMPACT_PANEL = "Compact panel (first line of each section)",
    HIDE_TRACKER_COMBAT = "Hide the Next up line in combat",
    HIDE_PANEL_COMBAT = "Hide the panel in combat",
    SHOW_TOOLTIPS = "Add WoW Companion lines to item and quest tooltips",
    SHOW_TRACKER = "Show the Next up line",

    -- Game tooltips
    TOOLTIP_UPGRADE = "WoW Companion: upgrade for %s",
    TOOLTIP_UPGRADE_ANY = "WoW Companion: upgrade for your gear",
    TOOLTIP_NEXT_STEP = "WoW Companion: next step #%d",

    -- Tracker
    TRACKER_NONE = "No digest for %s",
    TRACKER_EMPTY = "Next up: No digest yet",
    TRACKER_NEXT = "Next up: %s",
    TRACKER_MORE = " (+%d more)",

    -- Slash command help
    PLAN_STEP = "Step %d/%d: %s",
    PLAN_DISTANCE = " · %d yd %s",
    PLAN_ELSEWHERE = " · another zone",
    PLAN_DONE = "Plan complete (%d steps)",
    PLAN_PIN_LINE = "Step %d: %s",
    SHOW_PLAN_TRACKER = "Show the plan step tracker",
    SHOW_PLAN_MAP = "Show the plan on the map",
    PLAN_TRACKER_ON = "Plan tracker: on",
    PLAN_TRACKER_OFF = "Plan tracker: off",
    PLAN_MAP_ON = "Plan pins on the map: on",
    PLAN_MAP_OFF = "Plan pins on the map: off",
    HELP_PLAN = "  /wowc plan [map] - show or hide the plan step tracker (or, with map, the plan pins)",
    HELP_TITLE = "WoW Companion commands:",
    HELP_PANEL = "  /wowc - show or hide the panel",
    HELP_ASK = "  /wowc ask <question> (or /ask <question>) - queue a question; the overlay answers it after /reload",
    HELP_SETTINGS = "  /wowc settings - open the settings page",
    HELP_RESET = "  /wowc reset - restore the panel position and expand all sections",
    HELP_STATUS = "  /wowc status - show versions, digest age, queued questions and the digest slot",
    HELP_HELP = "  /wowc help - show this list",

    -- Status
    STATUS_TITLE = "WoW Companion status:",
    STATUS_VERSION = "  Addon %s, client build %s",
    STATUS_UNKNOWN = "unknown",
    STATUS_DIGEST = "  Digest: updated %s, schema %s",
    STATUS_DIGEST_NONE = "  Digest: none yet",
    STATUS_QUEUED = "  Questions queued: %d",
    STATUS_SLOT = "  %s: %s",
    STATUS_INSTALLED = "installed",
    STATUS_MISSING = "not installed",

    -- What's new
    WHATS_NEW_TITLE = "What's new in %s",
    GOT_IT = "Got it",
    WHATS_NEW_0_1_0_1 = "One digest now holds every character; a character with no entry gets a three-step hint.",
    WHATS_NEW_0_1_0_2 = "The stale-digest warning shows only when your character has moved on since the digest.",
    WHATS_NEW_0_1_0_3 = "Panel rows no longer draw without text, and raw id tags are hidden.",
    WHATS_NEW_0_1_0_4 = "After adding a new addon folder, restart the game fully; /reload is not enough.",
    WHATS_NEW_0_1_1_1 = "The addon now comes as a ready-to-install zip on its GitHub Releases page.",
    WHATS_NEW_0_1_1_2 = "The zip leaves out your digest and answers files, so updating never overwrites them.",
    WHATS_NEW_0_1_1_3 = "After adding a new addon folder, restart the game fully; /reload is not enough.",
    WHATS_NEW_0_3_0_1 = "The advisor's quest route now shows on the world map as numbered pins, and the next step on the minimap.",
    WHATS_NEW_0_3_0_2 = "A small movable tracker shows the next step with its distance and direction, and ticks off as you play.",
    WHATS_NEW_0_3_0_3 = "Type /wowc plan to hide or show the tracker and /wowc plan map for the pins.",
    WHATS_NEW_0_3_1_1 = "Fixed plan pins on the world map landing in the wrong place."
    WHATS_NEW_0_2_0_1 = "The in-game Ask box, History and Answers folder are gone; the overlay answers questions now.",
    WHATS_NEW_0_2_0_2 = "Right-click a panel line (or type /ask) to queue a question, then /reload for the overlay to answer it.",
    WHATS_NEW_0_2_0_3 = "Item and quest tooltips now note upgrades and next steps from your digest (can be turned off in settings).",
    WHATS_NEW_0_2_0_4 = "You can delete the leftover WoWCompanion_Answers folder.",
}

WC.L = setmetatable(L, { __index = function(_, key) return key end })
