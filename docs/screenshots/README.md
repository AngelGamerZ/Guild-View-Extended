# Screenshot sources

`render.html` mirrors the dimensions, column order, row heights, colors,
member-detail geometry, and profession accordion used by Guild-View-Extended
1.1. All names, guild text, notes, ranks, skills, and timestamps are explicit
example data and do not come from a real guild.

The class atlas is the same original World of Warcraft atlas referenced by the
addon (`Interface\WorldStateFrame\Icons-Classes`). Profession and toolbar
icons use their matching World of Warcraft icon artwork.

Run `node scripts/render-screenshots.cjs` from the repository root to recreate
`members.png`, `details.png`, and `professions.png`. Set `GVE_CHROME` when
Chrome is installed at a non-default location.
