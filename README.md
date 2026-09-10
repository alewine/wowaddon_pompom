<p align="center"><img src="logo.png" width="180" alt="PomPom logo"></p>

# PomPom

A minimal Prayer of Mending tracker for World of Warcraft Classic. Self-cast only.

![PomPom tracker](screenshots/tracker.png)

## What it does

- Shows the Prayer of Mending icon, the current target's name (class-colored), and the remaining bounce count as a WoW-style aura badge.
- Two stacked timer bars: **10 s recast cooldown** in blue on top, **30 s bounce duration** in gold on the bottom.
- Pulses the icon in gold when your recast becomes available while a PoM is still bouncing — recast now, don't waste the second charge floating out there.
- Plays a configurable beep the moment the recast timer expires.
- Fades to 25% out of combat and snaps back to full alpha the instant combat starts (toggle in config).
- Draggable when unlocked — a gold border and drag handle appear.
- Priest-only. Also silent on Shadow spec and on priests who haven't trained PoM yet — the config UI explains why in each case.

## Install

**Manual**: download the latest release zip → extract → drop the `PomPom/` folder into `Interface\AddOns\`.

**CurseForge**: (once published) search *PomPom* in your addon manager.

## Configuration

Type `/pom` in chat.

![Config panel](screenshots/config.png)

- **Lock frame** — when off, the tracker gets a gold border and a drag handle. Drag to reposition; the position is saved per character.
- **Enable sounds** — master switch for the recast-ready cue.
- **Fade out of combat** — dims the tracker while OOC so it's not distracting between fights.
- **Sound** dropdown — pick one of four included beeps. **Test** plays the current pick.
- **Scale** — 50% → 200%.
- **Background opacity** — 0% (fully transparent) → 100% (fully opaque).

## When the tracker does nothing

- Non-priest → tracker hidden, config disabled with an explanation.
- Priest without Prayer of Mending in the spellbook (usually a low-level priest) → same.
- Shadow-spec priest → same. Shadow priests don't heal, so tracking PoM isn't useful.

The addon re-checks on spec change, dual-spec swap, or when new spells are learned — no `/reload` needed.

## Files

```
PomPom/
├── PomPom.toc
├── PomPom.lua
└── sounds/
    ├── beep1.ogg
    ├── beep2.ogg
    ├── beep3.ogg
    └── beep4.ogg
```

## Custom sounds

Drop your own `.ogg` (or `.mp3`) into `PomPom/sounds/` and add a row to `SOUND_PRESETS` in `PomPom.lua`:

```lua
{ name = "My Ding", id = "Interface\\AddOns\\PomPom\\sounds\\myding.ogg", kit = false },
```

Keep it short (< 1 s), mono, and around 64–96 kbps for a small file.

## Compatibility

Built and tested on WoW Classic Anniversary (Classic Era 1.15). The TOC also declares Interface support for TBC Classic, Wrath Classic, and Cataclysm Classic. Not intended for Retail.

## License

MIT License. See [LICENSE](LICENSE).

## Author

Zeroseven (Dreamscythe)
