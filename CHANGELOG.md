# Changelog

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
