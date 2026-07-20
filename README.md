# Guild View Extended

Guild View Extended replaces the basic guild view with an expanded interface for **Ascension WoW on the World of Warcraft 3.3.5a client**.

## Features

- Search the guild roster by member name
- Filter members by class, rank, and online status
- Sort the roster using extended columns
- Review last-online information with configurable time filters
- Open member details and supported guild-management actions
- Access guild controls and member invitations when permitted
- View guild-related information and diagnostic logs in dedicated panels

## Screenshots
<img width="2385" height="1160" alt="Screenshot 2026-07-20 175229" src="https://github.com/user-attachments/assets/e4c887d0-63af-442d-a37b-bc1d134d5bf7" />
<img width="1865" height="1162" alt="Screenshot 2026-07-20 175215" src="https://github.com/user-attachments/assets/74308b87-6b3b-4783-b4b0-f68a4217e04c" />
<img width="2252" height="1149" alt="Screenshot 2026-07-20 175239" src="https://github.com/user-attachments/assets/a225d865-d02c-41c9-a97a-071352523c05" />


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

## Compatibility notes

The addon is designed specifically for Ascension's 3.3.5a client and relies on Blizzard guild-frame globals available in that environment. It replaces the global guild/friends toggle behavior, so compatibility with other addons that replace the same interface should be tested. The current interface and diagnostics contain a mixture of German and client-localized text.

## Privacy

The repository contains addon source only. Do not publish files from `WTF/Account/.../SavedVariables`, because those files may contain account, character, or guild-specific data.

## License and disclaimer

No open-source license is currently granted by this repository. All rights are reserved unless the repository owner states otherwise.

Guild View Extended is an independent community addon and is not affiliated with or endorsed by Ascension or Blizzard Entertainment.
