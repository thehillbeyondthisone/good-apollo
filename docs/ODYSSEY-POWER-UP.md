# Bring Odyssey back online

Press **F12** after the successful MCC-5 trim. The chapter advances to the
final pre-entry activation window. Battery C is feeding Main A, Aquarius is
feeding Main B, and the Command Module Computer is in standby. The flight's
power-up go came at **140:09:52 GET**.
[Mission report §5.2.1](https://www.apollojournals.org/alsj/a13/A13_MissionReport.pdf) · [Flight air-to-ground](https://apollojournals.org/afj/ap13fj/27day6-odysseyresurrected.html)

Click each highlighted switch, breaker or DSKY key. **Shift+click** reverses a
selector, **F** locates the current action, and **F12** confirms a callout or an
already-set position. The panel tabs let you inspect and change other loads.
**R** repeats the latest transmission, **M** mutes it, and the captions stay
visible. **F5 / F9** saves and restores the activation. **Shift+F12** restarts it.

- Shed the RCS heater and SCS logic loads. Check bus voltage before taking
  the go.
- Close the Main A computer feed before opening both LM power breakers.
  Main B goes dark during the transfer. Close its battery-bus tie to bring it
  back on Odyssey's own supply.
- Bring up the inverter, both AC buses, telemetry and communications. Use
  the S-band amplifier in LOW. Bring the computer out of standby, key
  **V96** and then **P00**, and bring up the IMU and optics.
- Watch the live current, peak and both bus voltages. Let startup surges settle
  or remove optional loads to recover. Final verification checks the required
  switch positions, equipment feeds and CMC state.

**24 V** was Houston's minimum for the live main buses. The chapter's **20 A**
ceiling is a gameplay budget for the combined modeled DC load. The panel
reconstruction contains selected controls from the read-up, grouped by panel
for desktop use. Individual currents, startup surges, voltage sag and the
DSKY state changes are scenario models. The chapter starts with earlier
pre-entry work already set up, then uses Mattingly's corrected activation order
and Kerwin's cues from the actual execution.
[Checklist read-up](https://apollojournals.org/afj/ap13fj/23day6-thereactivationchecklist.html) · [Actual activation](https://apollojournals.org/afj/ap13fj/27day6-odysseyresurrected.html)

The key arrangement follows Odyssey's recovered DSKY.
[Odyssey DSKY photo](https://www.apollojournals.org/afj/ap08fj/02earth_orbit_tli.html)

Thirty-one offline excerpts use NASA's original Mission Control audio from
tapes T716 and T927. Apollo 13 in Real Time credits the restoration to Ben
Feist and Jeremy Cooper and lists its work under CC BY-NC-SA 3.0. The manifest
records each excerpt's speaker, tape offset, checksum and transcript.
[Restored archive](https://apolloinrealtime.org/13/) · [Clip manifest](../assets/audio/odyssey/manifest.json)
