# Traffic Performance Fix

This mini-mod restores the optimized traffic driving tracker from BeamNG.drive 0.36.
It re-enables the `fullTracking` flag so the heavy positional analysis runs only on
player-controlled vehicles, which prevents the frame-time spikes introduced in 0.37
when the same logic ran for every AI traffic car each tick.

## Installation
1. Zip the contents of this `traffic_performance_fix` folder.
2. Place the resulting archive inside `Documents/BeamNG.drive/mods`.
3. Start the game – the adjusted script will override the stock 0.37 version.

You can also drop the folder as-is into the `mods` directory while developing.
