# BeamNG_tweakUI

## Bell 407 Surveying Autopilot – User Guide

This BeamNG.drive UI app lets you configure and run the surveying autopilot that ships with the Bell 407. Follow the steps below to install the hardware, prepare the target, fill in the parameters, and command the helicopter through the entire survey run.

### 1. Hardware preparation
1. Open **Vehicle Config** → *Frame* → *Electronics* and install the `bell_survey_autopilot` part into the **Surveying Autopilot** slot (if it is not already fitted).
2. If the app shows the status message “Surveying Autopilot hardware not detected,” the part is missing from the current configuration—install it and reload the UI.

### 2. Set the navigation target
1. In the game world open the map (default key **M**) and click to place a navigation target. Internally this stores a ground marker that the app reads via `core_groundMarkers.getTargetPos()`.
2. In the app press **Use Navigation Target** to adopt that marker as the start point of the survey pattern. If no target exists, the app shows an error and the autopilot cannot be armed.
3. Alternatively press **Load Home Position** to pull in the helicopter’s spawn point. When no start has been set yet, the field is populated automatically.

### 3. Configure Survey Pattern parameters
All parameters live in the **Survey Pattern** panel. Every change triggers a fresh preview of the planned route on the right-hand canvas.

| Field | Purpose |
|-------|---------|
| **Altitude (m)** | Flight level for the entire pattern; the planner also uses it for the starting waypoint. |
| **Track angle (°)** | Heading of the first leg relative to north; defines the direction of the survey passes. |
| **Leg length (m)** | Length of each survey leg; must be positive (minimum enforced by the script is 0.1 m). |
| **Spacing (m)** | Offset between adjacent legs; negative values mirror the offset direction. |
| **Rows** | Number of survey passes; minimum of 1. |
| **Survey speed (m/s)** | Target speed during the measurement legs. |
| **Finish behavior** | Completion mode to apply after the last waypoint (see section 4). |
| **Transit speed (m/s)** | Optional speed for the transit to the start of the pattern; leave blank to let the script pick a value. |

The **Start point** panel shows the coordinates of the current start location, or “No start point selected.” It also reports whether a home position is available for the return phase.

### 4. Finish and return modes
The three finish modes correspond to the values of `Finish behavior`:
- **Hover at final waypoint** – fly the last leg and hold a hover at the end of the pattern.
- **Return to start** – fly back to the start point, stabilize in a hover, and await further orders.
- **Return home and land** – transit to the home point, land, and shut down.

### 5. Starting and stopping the autopilot
1. Confirm that the hardware is detected (indicator in the upper-left) and that a valid preview is drawn—the map panel should show the lines and start marker.
2. Press **Arm Autopilot**. The UI sends the configuration and the `activate` command. When the app reports an error, the status remains `Idle`.
3. Once the status reads `Armed`, press **Start Survey**. The autopilot will spin the rotor up, lift off, transit, and then fly the pattern.
4. Use **Abort** at any time to send `cancel`, return control to the pilot, and leave the pattern early.
5. After the mission finishes you can press **Reset** to restore the default parameters and clear the preview.

The status panel shows the current flight phase, rotor spin percentage, speed, and the processed waypoint count. Use these values to verify that the script is running through the expected states.

### 6. Troubleshooting & tips
- **Unable to arm the autopilot** – ensure the part is installed and a navigation target exists. `ensureReady()` requires both the hardware and a ground marker; otherwise it returns `missingPart` or `noTarget`.
- **Preview shows “Unable to compute preview.”** – check that the start point has valid coordinates and altitude. The planner derives the route from `startPoint` and your parameters; missing values prevent preview generation.
- **Rotor does not reach RPM threshold** – the autopilot waits until the rotors exceed roughly 85% of the target RPM and stay there for `rotorStableTime`. If the helicopter is heavy on the skids, give it time or raise the collective slightly.
- **Helicopter keeps control after returning** – the **Abort** button always sends `cancel`, which drops the autopilot back to `idle` and hands control back to the player.
- **Home position unavailable** – the autopilot derives it from the spawn OOBB or the current position. If it cannot resolve a home point, the UI displays an error but the mission can continue without it.

### 7. Compatibility
- The scripts and UI are designed for the **Bell 407** with the `Surveying Autopilot` module installed. Other vehicles do not have the `407surveyAutopilot` controller (`isInstalled()` returns `false`).
- The app listens to the standard BeamNG `sensors` and `electrics` data streams, so it works with the default telemetries—no extra mods required.

### 8. Reference files and assets
- `ui/modules/apps/bell407SurveyingAutopilot/app.html` – UI layout, status messages, and controls.
- `ui/modules/apps/bell407SurveyingAutopilot/app.js` – Angular controller that handles button logic and communicates with the Lua extension.
- `Bell407/vehicles/bell407/lua/surveyingAutopilot.lua` – vehicle-side extension that generates patterns and exposes the API.
- `Bell407/vehicles/bell407/lua/controller/407surveyAutopilot.lua` – the autopilot controller that manages spool-up, pattern flight, return, and landing.

> Need a screenshot? Launch the **Bell 407 Surveying Autopilot** app in-game and capture the right-hand preview canvas with the pattern you configured. (A screenshot is not included in this repository.)
