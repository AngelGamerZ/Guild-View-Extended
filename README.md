# Guild View Extended

Guild View Extended replaces the basic guild view with an expanded interface for **Ascension WoW on the World of Warcraft 3.3.5a client**.

## Features

- Search the guild roster by member name
- Filter members by class, rank, and online status
- Sort the roster using extended columns
- Review last-online information with configurable time filters
- Export all guild character names as a copyable one-column CSV
- Invite a selected guild member directly from the member detail window
- Leave the guild from the player's own roster context menu with confirmation
- Refresh member and guild-note changes automatically while the window is open
- Open member details and supported guild-management actions
- Access guild controls and member invitations when permitted
- View guild-related information and diagnostic logs in dedicated panels

## Requirements

- Ascension WoW
- World of Warcraft client version 3.3.5a
- Interface version `30300`
- A guild membership for roster features

## Installation

1. Download or clone this repository.
2. Copy the `Guild-View-Extended` folder into `Interface/AddOns/`.
3. Confirm the final path is `Interface/AddOns/Guild-View-Extended/Guild-View-Extended.toc`.
4. Restart the client or reload the UI.

## Commands

- `/gve` or `/guildview` opens the extended guild view.
- `/gve log` opens the copyable diagnostic log.

## Member actions and live updates

- Left-click a guild member to open the existing member detail window. The
  **Invite GRP** button directly above **Remove** sends an immediate group
  invitation. It is disabled for the player's own character.
- Right-click the player's own character in the roster and choose
  **Gilde verlassen** or **Leave Guild**. A confirmation dialog must be
  accepted before `GuildLeave()` is called.
- While Guild View Extended is visible, it requests the complete roster every
  five seconds. The existing `GUILD_ROSTER_UPDATE` path then refreshes members,
  public notes, officer notes, filters, counts, and an open member detail
  window. Offline members remain enabled.

## CSV export

1. Open Guild View Extended with `/gve` or the normal guild shortcut.
2. Click **CSV exportieren** on a German client or **Export CSV** on another
   client. The button is at the top of the guild-log panel on the right.
3. If the complete roster is not ready yet, the addon requests it and waits for
   `GUILD_ROSTER_UPDATE`. Offline members are included.
4. In the export window, press `Ctrl+C`; the complete text is already selected.
5. Open the Raid Helper web interface, select its character-name CSV import,
   paste the copied text (or save it as a UTF-8 `.csv` file), and start the
   import. Map the `character_name` header if the interface asks for a column.

The export contains exactly one column named `character_name`. It does not
contain rank, level, class, zone, online state, public notes, or officer notes.
Names are exported without realm suffixes, deduplicated case-insensitively, and
sorted deterministically. No HTTP request or automatic clipboard access is
used, and no export data is stored in `GVEConfig`.

Example:

```csv
character_name
Arthas
Jaina
Thrall
```

## Backup and rollback

The pre-export source state is stored in
`Guild-View-Extended-pre-csv-20260728-144106.zip` in this addon directory.
Its SHA-256 is
`9566F98931959ABBD4D9DCF280F8258B5601EF8CDD38A5F8C03AD670CDA74BEA`.

To roll back, close World of Warcraft, move the current addon directory to a
safe temporary name, extract the archive into `Interface/AddOns/`, and verify
that the resulting path is
`Interface/AddOns/Guild-View-Extended/Guild-View-Extended.toc`. The archive
contains the complete pre-change directory, including its Git metadata.

An additional snapshot from immediately before the member-action and live
refresh changes is stored as
`Guild-View-Extended-pre-guild-actions-20260728-145630.zip` with SHA-256
`91120A28F5D3DF4F76134487156286392374E8E5D7C05EEC81AE860EBB467843`.

## Development tests

From the addon directory, run `lua tests/csv_export_test.lua` with a Lua
5.1-compatible runtime. The test loads the production addon source with small
WoW API stubs and verifies empty, single-member, Unicode, escaping,
deduplication, sorting, 5,000/5,001-member, dialog, Escape, offline-roster, and
asynchronous event cases. It also verifies group invitations, the confirmed
guild-leave action, and the automatic roster refresh timer.

## Compatibility notes

The addon is designed specifically for Ascension's 3.3.5a client and relies on Blizzard guild-frame globals available in that environment. It replaces the global guild/friends toggle behavior, so compatibility with other addons that replace the same interface should be tested. The current interface and diagnostics contain a mixture of German and client-localized text.

## Privacy

The repository contains addon source only. Do not publish files from `WTF/Account/.../SavedVariables`, because those files may contain account, character, or guild-specific data.

## License and disclaimer

No open-source license is currently granted by this repository. All rights are reserved unless the repository owner states otherwise.

Guild View Extended is an independent community addon and is not affiliated with or endorsed by Ascension or Blizzard Entertainment.
