# Crew flight notebook

The paper flight book follows the live procedure: **find**, **do**, **check**.
Each outstanding control position is its own instruction. Setting a control
updates the next target; confirming a callout uses the existing procedure
verification and cannot skip unfinished positions.

The six-page **Welcome aboard** orientation covers notebook handling, control
hover labels, switch and finger interactions, guidance, navigation and menus.
Every page has an enabled **Next page** button so you can read ahead without
performing a spacecraft action. Practice feedback records what you have tried.
The final **Begin procedure** page yields to the current procedure (the water
checkout in a fresh cabin). Replay through **Flight controls → Quick cabin
orientation**.

In VR the notebook is a movable cabin object. Hold **grip** within 14 cm of any
part of the cover or edge, or **aim and grip** within 1.2 m to pick it up. You
can squeeze before reaching the book. A lighter squeeze acquires it, with a
lower release threshold to prevent grip jitter. Grabs require a clear path;
they cannot pass through cabin structure. Release grip once after returning
from a menu or tracking loss before grabbing again. Move and rotate your hand to position
it, then release grip. The book retains a gentle release velocity and spin;
looking around and changing a step do not reposition it. **X** explicitly recalls
it within reach. **Stow** hides it; B/Y → **Flight notebook** reopens it.
Aim and release the trigger on an enabled **Confirm / Continue** to acknowledge
a completed callout. Opening the runtime dashboard cancels pending clicks.
**B/Y → Floating info → OFF** hides the small status window independently of
the notebook. Recalling or reopening the book leaves that window hidden.

On desktop, **N** opens/stows the book. Click its buttons to confirm completed
callouts; **F** still locates the current mission target. Odyssey mounts the same
page beside its live power meters and highlights the required station control.
Power-down, CO₂ assembly, MCC-5 and Odyssey all supply individual instructions.
The latter three chapters retain their existing desktop availability.

Amber guidance marks the relevant panel and current control or assembly part
with a soft glow and small particles. Each new step briefly shows a direction
cue if the target is out of view. **FIND** on the page or **A** in VR reveals it
again. Desktop **F** locates the current notebook target, including orientation
and water checkout; the camera stays upright beside the dispenser. Hover
with a controller ray or bring its fingertip close to see the control name,
position and applicable value beside the control. Controller pointers retain
their ivory filament, cuff rings and amber sight; constant hand labels stay off.
Save and restore remain available through the flight menu. Desktop **F2** still
selects the powered-checkout preset.

An amber **Do the action above / auto-advances** strip is status, not a button. Follow the notebook's
physical instruction first; the real control state determines when to continue.
Completed callouts show an enabled **Confirm / Continue** button. Successful
water dispensing and shutoff enable **Finish water check**, which acknowledges
checkout without silently starting a mission. **Start power-down** then begins
the next procedure explicitly.

## Water checkout

1. Select the ivory dispenser body below the aft ECS controls to move it from
   **BRACKETED** to **FREE**. Use **FIND** if you cannot see it.
2. Open either **DES H₂O** or **ASC H₂O** on the ECS panel.
3. Select the round cap at the nozzle tip to move it from **FITTED** to
   **REMOVED**. It parks beside the nozzle, clear of the water path.
4. Aim at the small ivory side button and **hold** the controller trigger (or left mouse).
   Small water beads leave the nozzle while the trigger is held.
5. Release and verify that the beads stop. Select **FINISH WATER CHECK** on the
   book. Replace the cap after use. **START POWER-DOWN** begins a separate procedure.

This procedure appears as the default cabin-checkout notebook. A fitted cap or
closed feed gives a specific blocked-path message. Beads follow the dispenser's
moving nozzle. They provide visual feedback for the existing logical water path;
water pressure, volume, drinking and tank depletion remain unmodeled. The fitted
cap shares the nozzle axis in both dispenser poses, and a flexible supply hose
follows the dispenser collar. Hover text identifies the body, cap and side-button
actions separately.

## Verification

`test_flight_notebook.gd` checks actual procedure gating, every chapter's
instructions, printed text bounds, flush readout mounting, dispenser feedback
and world-plane notebook clicks including held-trigger and lost-tracking cases.
Run with `--headless --script res://tests/test_flight_notebook.gd -- --self-test
--systems-test --manual-clock` against the built project. Results are written to
`output/flight-notebook-tests.json`. `capture_flight_notebook.gd` renders the
desktop page, XR meshes and Odyssey placement without claiming headset use.
`test_cabin_onboarding.gd` verifies all six pages, practice feedback, completion,
replay and desktop wording without initializing XR or operating any controls.

`test_notebook_hands.gd` checks actual page clicks by ray and controller-tip
contact, the FIND button, text bounds, hand grabbing/release and no automatic repositioning.
`test_lighting_water.gd` adds 90 real-scene checks for cap/nozzle and hose alignment,
upright keyboard location of every water step, hold/release/acknowledgement gating,
and dimmer, flood, shade and power-loss lighting responses. `capture_lighting_pass.gd`
renders forward/aft checkout, the bracketed and flowing dispenser, completed
water instructions, shaded darkness and a powered utility lamp in Compatibility
or Mobile. Neither test claims physical headset acceptance.
`test_free_float.gd` checks released momentum and spin, slow drift, structural
collisions and held translation/rotation collision checks. Damping and impact
materials are perceptual approximations. The notebook has mass and inertia in
the cabin frame; it does not yet exchange momentum with a simulated astronaut,
respond to modeled cabin ventilation or persist its pose in checkpoints.
