# Legacy Freeroam Vehicle Selector

This mod restores the classic vehicle selection dialog that was used in BeamNG.drive 0.36 when playing in Freeroam. Version 0.37 replaced the pause-menu "Vehicles" option with the new `vehicleSelector` interface, which some players may not prefer. Instead of forcing one or the other, the mod adds a choice dialog so that pressing <kbd>Esc</kbd> and selecting **Vehicles** lets you open either interface on demand.

## Features

- Adds a Freeroam-only prompt with two buttons: **Classic (0.36)** and **Modern (0.37)** vehicle selectors.
- Keeps the stock BeamNG.drive 0.37 selector available for other game modes and for players who prefer the new UI.
- Preserves the legacy 0.36 selector so long-time players can switch back instantly without disabling the mod.

## Installation

1. Copy the contents of this repository into a zipped archive (or the BeamNG mods folder) so that the `modInfo.json` file is at the root of the mod.
2. Place the resulting archive (or folder) into `Documents/BeamNG.drive/mods/`.
3. Launch BeamNG.drive 0.37 or newer. The mod activates automatically after the extensions finish loading.

## Notes

- The choice dialog appears whenever Freeroam asks for a vehicle selector (pause menu, quick access, or `Ctrl` + `E`). Pick **Classic (0.36)** to open the legacy window, or **Modern (0.37)** to use BeamNG.drive's current UI.
- If the game requests a filtered selector (e.g., "mods only"), the prompt explains that the legacy UI ignores the filter. Choosing the modern selector honours the request.
- Disabling or removing the mod restores the default behaviour on the next launch.

## Troubleshooting

If the legacy dialog does not appear, ensure that:

- The mod is enabled inside the in-game **Repository → Mods Manager**.
- No other mod overrides `core_vehicles` or `ui_vehicleSelector` in a conflicting way.
- The game is running version 0.37 (or a compatible update) where the new selector is present.

Logs mentioning `vehicleSelectorLegacyFreeroam` can be found in the game's console and `beamng.log`, which may help diagnose conflicts.
