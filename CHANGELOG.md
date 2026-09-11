# Changelog

## 1.6.1
- Packaged builds now cover every supported game type. The 1.6 release zip
  was Era-only: without per-flavor TOC generation the packager collapsed the
  Interface-Classic/BCC/Wrath/Cata lines down to the single plain Interface
  value and built one flavor from it.

## 1.6
- Fix the bounce badge failing to decrement as Prayer of Mending jumps.
- Reduce beep volume by 20%.
- Display name is now "PomPom" throughout, matching the addon folder.
- Update interface versions for Classic Era 1.15.9 and TBC Anniversary 2.5.6.

## 1.5
- Ship four custom `.ogg` beeps in the `sounds/` folder as the only preset options.
- Guard against out-of-range saved `soundIndex` from prior versions.

## 1.4
- Availability check: addon disables itself gracefully for non-priests, priests without Prayer of Mending, and Shadow-spec priests. Config remains accessible; options are disabled with an explanation.
- Combat fade: main tracker fades to 25% out of combat, snaps back to full on combat entry. New "Fade out of combat" toggle in config.
- Re-evaluates on spec / talent / spellbook changes.

## 1.3
- Config layout reworked: checkboxes at the top, sound picker in the middle, sliders at the bottom.
- Trimmed config frame padding.
- Restyled title: bold "PomPom" with a small-caps "PRAYER OF MENDING TRACKER" subtitle and hairline rule.

## 1.2
- Sound dropdown with a **Test** button that plays the currently-selected preset.
- Curated a new set of sound options.

## 1.1
- Added Background opacity slider.
- Play a sound the moment your recast timer expires (edge-triggered) while a PoM is still bouncing.
- Added Enable sounds toggle.

## 1.0
- Initial rewrite as a fresh addon (formerly derived from PoMTracker).
- Icon-forward layout with bounce count as a WoW-style aura badge.
- Two stacked timer bars: 10 s recast (blue) on top, 30 s bounce duration (gold) on bottom.
- Pulsing gold glow on the icon when the recast becomes available while PoM is still bouncing.
- Class-colored target name.
- `/pom` opens a config panel: Lock frame, Scale, Background opacity, Sound picker + Test.
- Draggable frame with a gold border + drag handle when unlocked.
- Self-cast only; ignores other priests' Prayer of Mending.
- Priest-only.
