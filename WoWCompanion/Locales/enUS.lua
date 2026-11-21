-- WoW Companion: the enUS strings. Every player-facing string lives here; see Locales/README.md.
-- A key with no entry falls back to the key itself, so a missing translation never shows nil.

WoWCompanion = WoWCompanion or {}
local WC = WoWCompanion

local L = {
    ADDON_NAME = "WoW Companion",

    -- Panel
    ASK = "Ask",
    HISTORY = "History",
    BACK = "Back",
    PREV = "Prev",
    NEXT = "Next",
    CLEAR = "Clear",
    CONFIRM = "Confirm",
    CANCEL = "Cancel",
    COMPACT = "Compact",
    FULL = "Full",
    ASK_HINT = "Your AI client answers after /reload; /reload again to see the answer.",

    -- Digest
    NO_ADVICE = "No advice yet \226\128\148 the companion hasn't written a digest.",
    STALE_NOTE = "Ask your AI client to refresh your digest, then /reload.",
    UNKNOWN_SCHEMA = "This digest uses an unknown format (schema %s); update the addon.",
    WRONG_CHARACTER = "This digest was written for %s, not %s.",
    DIGEST_HEADER = "%s \226\128\148 updated %s",
    LINE = "  - %s",
    LINE_QUEST = " [quest %s]",
    LINE_ITEM = " [item %s]",
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
    OLDER_THAN_CAPTURE = "Your digest is older than your last capture; ask your AI client to refresh it.",

    -- Button tooltip
    TIP_DIGEST = "Digest: updated %s",
    TIP_DIGEST_NONE = "Digest: none yet",
    TIP_QUEUED = "Questions waiting: %d",
    TIP_ANSWER = "Last answer: %s",
    TIP_ANSWER_NONE = "Last answer: none yet",
    TIP_CLICK = "Click to open",

    -- Questions and answers
    QUESTIONS = "Questions",
    ASK_LINE_Q = "  Q: %s",
    ASK_LINE_A = "  A: %s (%s)",
    ASK_SOURCES = "  sources: %s",
    ASK_QUEUED = "  queued; /reload to send",
    ANSWERS_UNREADABLE = "The answers file is unreadable and was ignored.",
    ANSWERS_MALFORMED = "%d malformed answer(s) were ignored.",

    -- History
    NO_HISTORY = "No saved answers yet.",
    HISTORY_ENTRY = "History: entry %d of %d (Prev = older)",
    HISTORY_ANSWER = "  A: %s",
    HISTORY_ASKED = "  asked %s",
    HISTORY_CLEAR_ASK = "Clear all %d saved answers for this character?",
    COPY_SOURCES = "sources: %s",

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
    SECTION_ask = "Ask box and answers",
    SECTION_history = "History",

    FONT_LABEL = "Text size: %s",
    FONT_small = "Small",
    FONT_normal = "Normal",
    FONT_large = "Large",
    COMPACT_PANEL = "Compact panel (first line of each section)",
    HIDE_TRACKER_COMBAT = "Hide the Next up line in combat",
    HIDE_PANEL_COMBAT = "Hide the panel in combat",
    SHOW_TRACKER = "Show the Next up line",

    -- Tracker
    TRACKER_EMPTY = "Next up: No digest yet",
    TRACKER_NEXT = "Next up: %s",
    TRACKER_MORE = " (+%d more)",

    -- Slash command help
    HELP_TITLE = "WoW Companion commands:",
    HELP_PANEL = "  /wowc - show or hide the panel",
    HELP_ASK = "  /wowc ask <question> (or /ask <question>) - queue a question; it is sent on /reload",
    HELP_HISTORY = "  /wowc history - browse past answers; /wowc history clear - clear them (asks first)",
    HELP_SETTINGS = "  /wowc settings - open the settings page",
    HELP_RESET = "  /wowc reset - restore the panel position and expand all sections",
    HELP_STATUS = "  /wowc status - show versions, digest age, queued questions and installed slots",
    HELP_HELP = "  /wowc help - show this list",

    -- Status
    STATUS_TITLE = "WoW Companion status:",
    STATUS_VERSION = "  Addon %s, client build %s",
    STATUS_UNKNOWN = "unknown",
    STATUS_DIGEST = "  Digest: updated %s, schema %s",
    STATUS_DIGEST_NONE = "  Digest: none yet",
    STATUS_QUEUED = "  Questions waiting for an answer: %d",
    STATUS_ANSWER = "  Last answer: %s",
    STATUS_ANSWER_NONE = "  Last answer: none yet",
    STATUS_SLOT = "  %s: %s",
    STATUS_INSTALLED = "installed",
    STATUS_MISSING = "not installed",

    -- What's new
    WHATS_NEW_TITLE = "What's new in %s",
    GOT_IT = "Got it",
    WHATS_NEW_0_0_1_1 = "Localization: every string now lives in a locale table, ready for translations.",
    WHATS_NEW_0_0_1_2 = "A short note like this one appears once after each update.",
    WHATS_NEW_0_0_1_3 = "Settings, history and the ask box are all in the panel.",
}

WC.L = setmetatable(L, { __index = function(_, key) return key end })
