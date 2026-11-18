# Hands-on Apollo 13 power-down

Start **Launch Aquarius.cmd** and press **F12**. Read the callout, operate the
switches and breakers yourself, and press **F12** to confirm the group. The
checklist advances when the requested positions match. Use **F** to look at the
next control, then click its ring. **Shift+F12** restarts the exercise. **F2**,
**F3**, **F4**, and **F11** exit into their respective checkout presets.
Press **F12** after the final callout to continue into the [CO₂ adapter chapter](CO2-ADAPTER.md).

The exercise starts from a sandbox equipment checkout with a fresh battery
allocation. Its 13 callouts cover 93 branch and selector positions from
79:37:48 GET through the approximate 82:30 low-power summary. Text callouts
summarize the flight conversation, and GET labels show the source chronology.
The simulation clock advances at its normal rate between callouts.

The [air-to-ground transcript](https://apollojournals.org/afj/ap13fj/13day4-leaving-moon.html)
distinguishes read-up, crew intent, and confirmed operation. The final breaker
group begins when the crew reported that they were starting. The callout directs
you from panel 11 to panel 16. Individual motion times and ordering inside that
group are unknown, so the exercise accepts the positions in any order. Later
lighting and heater amendments supersede earlier instructions. The checklist
covers explicitly identified positions. Unspecified baseline breakers retain
their sandbox states.

Leave all four panel 16 RCS heater breakers closed and move the panel 3
selectors to OFF. Quad 1 was sealed closed on Aquarius and is locked during
the exercise. The crew's later spoken panel number differs from Houston's
explicit instruction. The game uses the panel 3 selectors from the inventory.

Cabin floods respond to their selector and breaker. Pulling the inverter
offline removes AC integral lighting. Opening the LGC/DSKY and IMU operate
breakers leaves IMU standby powered. The DSKY goes dark and the stepped
computer halts. Reclosing the powered LGC branch retains magnetic-core words
and runs the restart after the nominal 250 ms inhibit. [LGC power](LGC-POWER.md)

As the floods, inverter, LGC, and IMU operate circuits lose power, the estimated
temperature eases down from the illustrative 68°F start toward 52°F. The cold
endpoint falls within the reported 49–55°F range in Aquarius. The exercise
compresses the thermal response to a 45-second time constant and retains a
small amount of window fill for navigation. **P** pauses the shared clock and
cooling. [NASA environmental report](https://ntrs.nasa.gov/api/citations/19760005585/downloads/19760005585.pdf)

**F5** saves checklist progress, temperature, physical controls, electrical
state, and the stepped computer together. **F9** restores them so partially
completed groups can be resumed. Earlier checkpoints start at 68°F when
loaded. Electrical readouts show partial equipment loads. The historical power
budget remains open.

The [source catalog](../reference/electrical-powerdown-sequence.json) is
reproduced by `node tools/build-powerdown-sequence.cjs`. The headless sequence
runner verifies the replay dataset. The actual-scene `-PowerDownTest` exercises
the desktop controls, callout gates, power-linked lighting, cooling, and native
checkpoints.
