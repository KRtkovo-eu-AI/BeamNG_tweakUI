# Legacy Freeroam Vehicle Selector

This mod restores the classic vehicle selection dialog that was used in BeamNG.drive 0.36 when playing in Freeroam. Version 0.37 replaced the pause-menu "Vehicles" option with the new `vehicleSelector` interface, which some players may not prefer. By re-enabling the legacy menu, pressing <kbd>Esc</kbd> and choosing **Vehicles** once again opens the familiar dialog from 0.36.

## Features

- Forces the game to open the legacy Freeroam vehicle selector dialog shipped with BeamNG.drive 0.36.
- Redirects all Freeroam-specific entry points (including mod-filtered selectors) back to the legacy interface.
- Leaves all other vehicle selector functionality untouched, allowing the game to continue using the newer systems where needed.

## Installation

1. Copy the contents of this repository into a zipped archive (or the BeamNG mods folder) so that the `modInfo.json` file is at the root of the mod.
2. Place the resulting archive (or folder) into `Documents/BeamNG.drive/mods/`.
3. Launch BeamNG.drive 0.37 or newer. The mod activates automatically after the extensions finish loading.

## Notes

- The legacy dialog does not support the additional filtering options introduced by the new `vehicleSelector`. When the game requests a filtered list (e.g., "mods only"), the legacy window is opened instead and the request is logged in the console.
- The original 0.37 vehicle selector remains untouched for other game modes that still rely on it.
- If the mod is disabled or removed, the game will revert to using the new selector on the next launch.

## Troubleshooting

If the legacy dialog does not appear, ensure that:

- The mod is enabled inside the in-game **Repository → Mods Manager**.
- No other mod overrides `core_vehicles` or `ui_vehicleSelector` in a conflicting way.
- The game is running version 0.37 (or a compatible update) where the new selector is present.

Logs mentioning `vehicleSelectorLegacyFreeroam` can be found in the game's console and `beamng.log`, which may help diagnose conflicts.
