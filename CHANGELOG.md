# Changelog

## 1.1 - 2026-09-27

- Added automatic discovery between compatible online guild members.
- Added rate-limited background requests instead of requiring every profession
  snapshot to be requested manually.
- Announced changed profession links to online addon users and synchronized
  only when the advertised snapshot is newer than the local cache.
- Preserved the manual request button as an explicit refresh action.
- Replaced the profession master-detail view with a full-width expandable
  profession table, including 3.3.5a spell icons, player/rank rows, direct
  profession links, skill, snapshot age, status, and compact filters.
- Rebuilt the member page in the same flat visual language with compact
  32-pixel rows: class icon, name, level and class, zone, rank, and note.
- Expanded roster search to names, classes, zones, ranks, and public notes.
- Made both the MOTD and Guild Information visible at a glance across the full
  member-page width.
- Moved Guild Log and Last Online into focused in-window views and retained
  their existing data, filters, permissions, and CSV export actions.
- Restyled the existing stock Guild Control popup without replacing its
  original 3.3.5a permission and save logic.
- Kept the roster scrollbar inside the window, widened the member page, and
  switched member/filter icons to the original 3.3.5a WorldStateFrame class
  atlas with the Build 12340 coordinates.
- Replaced the oversized member-detail drawer with a compact centered card,
  wider note fields, and flat Guild-View-Extended action buttons.

## 1.0

- Modernized the guild roster while retaining member management, guild
  controls, guild logs, notes, filters, sorting, and automatic roster updates.
- Added a searchable and readable Last Online window.
- Added direct group invitations and a confirmed Leave Guild action.
- Added a copyable two-column CSV export containing character names and guild
  ranks.
- Added a profession-only synchronization tab for World of Warcraft 3.3.5a.
- Captured authentic profession links automatically from the spellbook and
  displayed them as clickable links that open WoW's linked profession window.
- Grouped players by profession and allowed searches by player or profession.
- Added request-based, validated, throttled synchronization between online
  guild members using the legacy addon-message APIs.
- Added German and English interface text.
- Added regression coverage for roster workflows, CSV export, profession-link
  variants, SavedVariables migration, synchronization, and search grouping.
