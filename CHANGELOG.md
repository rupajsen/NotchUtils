# Changelog

All notable changes to NotchUtils are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.1.0] - 2026-11-01

### Added

- **Thermals tab:** live temperatures and fan speeds.
- **Fan control:** Automatic, Manual and Max on MacBook Pro models with a notch. See [which Macs get what](https://github.com/rupajsen/NotchUtils#what-your-mac-gets).
- **Closed notch:** a fan indicator while the fans are under manual control, and a short notice if they return to automatic.

### Good to know

- **Optional root helper:** fan control needs a small background service with administrator access. Nothing is installed until you set it up, and you can remove it from the Thermals tab. The [README](https://github.com/rupajsen/NotchUtils#fan-control-safety) explains what it does and the risks.
- **Tested on M1 Pro only:** other MacBook Pro models are marked Experimental. Please [tell us how it goes](https://github.com/rupajsen/NotchUtils/discussions).
- **Not yet tried on real hardware:** waking from sleep, restarting with the helper installed, and closing the lid with an external display attached.
- **Install note:** this build isn't notarized, so macOS will warn you the first time you open it. The [README](https://github.com/rupajsen/NotchUtils#apple-could-not-verify-notchutils) explains how to open it anyway.

## [1.0.0] - 2026-11-01

The first public release.

### Added

- **Now Playing:** album art, seek bar and playback controls for Spotify and Apple Music.
- **Timer:** presets, ±1 minute adjustments and a countdown in the closed notch.
- **Shelf:** drag files onto the notch, drag them back out or send them with AirDrop.
- **System:** battery, CPU, memory and storage gauges, a volume slider, Keep Awake, Screenshot, Sleep Display and Open at Login.
- **Closed notch activity:** current track, running timer, charging flash and Keep Awake.
- **Credits:** with links for viewing the source and suggesting ideas.
- Haptic feedback when the notch opens and closes.

### Install note

This build isn't notarized, so macOS will warn you the first time you open it. The [README](https://github.com/rupajsen/NotchUtils#apple-could-not-verify-notchutils) explains how to open it anyway.

This is an early release, so please [share ideas](https://github.com/rupajsen/NotchUtils/discussions/categories/ideas) and [report bugs](https://github.com/rupajsen/NotchUtils/issues/new/choose).
