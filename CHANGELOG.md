# Changelog

## 1.1.2 - 2026-08-28

- Enlarged and reorganized the Last Online window for better readability.
- Added a live, case-insensitive member-name search that combines with the
  existing offline-duration filter.
- Added a rank column heading, clearer result counts, deterministic tie
  sorting, scroll reset after filtering, and explicit empty-result messages.
- Made Escape close the window from the focused search field and request fresh
  roster data whenever the window opens.
- Widened the local test build further, placed the search in a clearly bordered
  panel, forced long ranks to remain on one line, and added alternating row
  backgrounds plus subtle separators between members.

## 1.1.1 - 2026-07-28

- Added the guild rank to the CSV export as the second `guild_rank` column.
- Kept each rank paired with the first retained spelling of a deduplicated
  character name and applied CSV escaping to both values.

## 1.1.0 - 2026-07-28

- Added a localized, copyable one-column CSV export for all loaded guild members.
- Added asynchronous roster loading before export when guild data is not ready.
- Added name cleanup, realm removal, CSV escaping, case-insensitive deduplication,
  deterministic sorting, and a 5,000-name safety limit.
- Added a non-modal export dialog with character count, full-text selection,
  a close button, and Escape support.
- Added an `Invite GRP` action directly above the remove-member button in the
  member detail window.
- Added a confirmed `Leave Guild` action to the player's own roster context
  menu.
- Added automatic five-second roster refreshes while Guild View Extended is
  open, so member and note changes appear without reopening the window.

## 1.0.0 - 2026-07-19

- Initial public source release for Ascension WoW 3.3.5a.
- Added roster search, class/rank/online filtering, sorting, last-online views, member details, guild controls, and diagnostic logging.
