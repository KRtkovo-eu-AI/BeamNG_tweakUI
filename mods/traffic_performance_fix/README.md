# Traffic Performance Fix

This mini-mod restores the optimized traffic driving tracker from BeamNG.drive 0.36.
It re-enables the `fullTracking` flag so the heavy positional analysis runs only on
player-controlled vehicles, which prevents the frame-time spikes introduced in 0.37
when the same logic ran for every AI traffic car each tick.

Version 1.1 goes further by throttling how often remote AI traffic recalculates its
road alignment. Farther cars reuse cached road data for up to one second, eliminating
the repeated `map.findClosestRoad` calls that still caused micro-stutters in large
traffic pools. The script now emits `[TrafficPerformanceFix]` log lines when the
override loads and whenever an AI vehicle swaps to the lightweight tracker, making it
easy to confirm the mod is active in `BeamNG.log`.

## Installation
1. Zip the contents of this `traffic_performance_fix` folder.
2. Place the resulting archive inside `Documents/BeamNG.drive/mods`.
3. Start the game – the adjusted script will override the stock 0.37 version.

You can also drop the folder as-is into the `mods` directory while developing.
