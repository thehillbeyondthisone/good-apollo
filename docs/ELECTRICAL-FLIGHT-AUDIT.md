# Electrical flight chronology and accounting audit

The historical schedule is better constrained, but **full flight validation
remains open**. The new source ledger is
`reference/electrical-flight-audit.json`; regenerate it with
`tools/build-electrical-flight-audit.py`. The CLI's `profile-audit` and
`reported-budget` commands use its calculated scenarios. Those reports remain
explicitly independent-validation failures, even when an assumed schedule
produces a small reserve residual.

## What the primary records establish

The most useful additional source is the NASA Flight Control Division's
[Mission Operations Report, 28 April 1970](https://apollojournals.org/afj/ap13fj/pdf-hr/a13-mission-ops-report.pdf),
Appendix G, TELMU Post Mission Report. Full rendered leaves G-1 through G-6
(PDF 235–240) were visually reviewed. Its values describe flight operation;
they are distinct from the Flight Director's available/planning profile.

| Event or condition | Evidence | Primary locator |
|---|---|---|
| LM internal power by about 57:44; initial load eventually 45–50 A | Activation transient; no exact constant-duration interval given | TELMU G-1, PDF 235 |
| Load reduced to 35–40 A at 60:40 | Early reduction before the final deep powerdown | TELMU G-2, PDF 236 |
| Initial loads 28–50 A until about 82:30, then average 12.5 A | The PC+2 engine shutdown at 79:32 did not immediately complete deep electrical powerdown | TELMU G-5, PDF 239 |
| Early CDR/LMP bus-power split 4:1 | Cross-ties open 60:34–63:40 and 78:16–80:00; equal sharing is not the flown history | TELMU G-5, PDF 239 |
| Battery 6 online 111:57; CM connection 112:05, drawing about 8 A for charging | Intermittent use through the final switchover. TELMU gives about 140:00. Crew callouts put the breaker operation around 140:10–140:11. | TELMU G-6, PDF 240 and [air-to-ground transcript](https://apollojournals.org/afj/ap13fj/27day6-odysseyresurrected.html) |
| Battery 5 online 133:30 | Separate from the start of overall reactivation | TELMU G-6, PDF 240 |
| Battery 3 disconnected 139:16 after 394 Ah, contributing less than 1 A | Battery-specific history is an additional validation target | TELMU G-6, PDF 240 |
| 189.6 Ah usable at LM jettison, 141:30 | Usable reserve, a different metric from total remaining capacity | TELMU G-3, PDF 237 |

The [contemporaneous late-flight PAO transcript](https://apollojournals.org/afj/ap13fj/25day6-thelastcoursecorrection.html)
adds reactivation start at **133:29**. It reports 34–35 A near 133:35,
45–50 A at 133:55, and roughly 40 A at 134:42 and 135:52. The retrospective
70 A peak has **no established duration**. It is retained as a peak observation;
no rectangular 70 A load interval is invented.

## Checklist and switching evidence

The local LM-7 Contingency Checklist PDF pages 81–84 are printed **PWR-5
through PWR-8**. They are the emergency rescue-orbit baseline. The
[in-flight read-up and execution](https://apollojournals.org/afj/ap13fj/13day4-leaving-moon.html)
amended that baseline. PGNS remained available for PTC setup, then the crew
executed final powerdown starting 82:16:37; the subsequent TELMU summary places
the achieved low-power state around 82:30. IMU standby heating remained powered
while LGC/DSKY and IMU operate were removed. RCS heater breakers and heater
switches also had distinct roles. The artifact records the specific amendments
without treating the unmodified checklist as a flown preset.

For late communications, the [radio transcript](https://apollojournals.org/afj/ap13fj/25day6-thelastcoursecorrection.html)
commands the amplifier breaker closed at **132:30:30**, with crew confirmation
at **132:31:02**. Fifteen minutes was the requested ranging period; an actual
end time is not established by that request. No 132:58 amplifier-off event was
found on the reviewed page.

## Battery 2 transient and alarm

Figure 14-16 preserves individual descent battery current and CDR/LMP bus
voltage samples around GET 97:13:53. Selected plotted points put the CDR bus
near 29 V and the LMP bus near 27.6 V. Battery 2 has two off-scale points.
The detailed anomaly report gives a Battery 2 surge magnitude of at least
60 A and says the instrument could not indicate current direction. The
section 6.2 summary reports a surge greater than 100 A without assigning it
to an individual channel. The detailed report found no automatic battery
disconnection, reverse-current indication, or balance-load cross-tie trip.
The catalog records the plot reading allowance separately from instrument
uncertainty. The nominal one-sample-per-second cadence and the staggered,
clipped points leave the intervening waveform and charge integral unknown.
[Mission Report, §§6.2 and 14.2.2](https://www.apollojournals.org/alsj/a13/A13_MissionReport.pdf)
[NASA EPS Experience Report, pp. 13–14](https://ntrs.nasa.gov/api/citations/19720025198/downloads/19720025198.pdf)

Lovell first reported a Battery 2 warning at 99:49:52 and confirmed the
master alarm at 99:50:26. The catalog retains the later times in TELMU
and both Mission Report sections. The crew manually removed Battery 2
at 99:53:42, restored it at 101:02:47, and immediately reported the alarm
and battery light again. The audit records both balance-load cross-tie
operations around the manual disconnect and reconnect. The Mission Report
ruled out actual overcurrent, reverse current and overtemperature for the
later alarm and documented the indication circuit in Figure 14-18.
[Air-to-ground transcript](https://apollojournals.org/afj/ap13fj/17day5-thumpandsnowflakes.html)
[Mission Report, §14.2.3](https://www.apollojournals.org/alsj/a13/A13_MissionReport.pdf)

## CM charger and export chronology

The transfer procedure connects the two CM panel 5 LM Power breakers to
Main B. Main B supplies the charger’s DC input and feeds Inverter 2, which
supplies the charger through AC Bus 2. CapCom specified a 15 A protection
limit for the umbilical feed. The procedure establishes the route for a
future circuit model. The current accounting implementation models export
as a source demand. EECOM explains that CM Battery B briefly supplied the
LM control relays before power flow reversed. It also distinguishes the
earlier 102 GET CM telemetry check on Battery B from the 123 GET check on
LM power.
[Charging transcript](https://apollojournals.org/afj/ap13fj/21day5-batterycharge.html)
[CSM News Reference, pp. 113–114](https://apollojournals.org/alsj/CSM_News_Reference_H_Missions.pdf)
[Mission Operations Report, EECOM p. E-9](https://apollojournals.org/alsj/a13/A13_MissionOpReport.pdf)

| GET | CM operation | Evidence |
|---|---|---|
| 112:05 | Main B connected to LM power | TELMU G-6, then crew reports power-up complete at 112:06:11 |
| 112:06:28–112:11:57 | Battery A began charging | Go to first meter reading. PAO rounds the start to 112:12. |
| 122:46:47–122:51:33 | Battery A charging paused | Crew departs to stop charge, then reports it secured. The LM powers a CM telemetry check during the pause. |
| 123:18:11–123:21:32 | Battery A charge resumed | From crew report of restart in progress to confirmation of charging |
| 125:57:51–126:02:41 | Changed over to Battery B charge | From crew starting the procedure to the first Battery B reading |
| 127:11:09–128:02:47 | Battery B charging ended within this window | A positive meter reading and subsequent confirmation that the switch was already off |
| 140:10:32–140:11:20 | Returned to CM internal power | From crew call at the LM power breakers to follow-up for Mission Control |

The artifact contains ten CM charger readouts, including 34.3 V and 2.5 A
on Battery A near startup, and 39.4 V and 1.25 A ahead of the pause. It
preserves each voltage and current as a point observation. These are charger
output measurements. The about 8 A reported by TELMU is LM input during
charging, and the reported 129 Ah of export also includes other CM loads.
The readings are insufficient to integrate output or estimate charger
efficiency. The Mission Report separately records a net increase of 19 Ah
in available CM entry battery reserve, from 99 Ah at shutdown to 118 Ah
after charging. EECOM independently records its calculated reserves at
128 GET as 40.0 Ah each for A and B and 38.8 Ah for uncharged Battery C, a
total of 118.8 Ah. Both endpoints are available for a future CM battery model.
The EECOM entry timeline also assigns Ring 2 preheat, caution and warning,
and lighting to LM-fed Main B. Its actual CM load plot begins after the
switch to internal CM power, leaving the earlier export waveform unknown.
[Charging transcript](https://apollojournals.org/afj/ap13fj/21day5-batterycharge.html)
[Telemetry pause transcript](https://apollojournals.org/afj/ap13fj/22day6-packingup.html)
[Changeover transcript](https://apollojournals.org/afj/ap13fj/23day6-thereactivationchecklist.html)
[Mission Report, §7.1.6](https://www.apollojournals.org/alsj/a13/A13_MissionReport.pdf)
[Mission Operations Report, EECOM pp. E-9, E-12 and E-21](https://apollojournals.org/alsj/a13/A13_MissionOpReport.pdf)

## Why the reported ampere-hours do not yet reconcile

Mission Report section 6.2 (small PDF 45 / high-resolution PDF 37, printed 6-1)
reports descent delivery 1434.7 Ah and ascent delivery 200 Ah. Section 7.2.5
(small PDF 62–64 / high-resolution PDF 54–56, printed 7-6–7-8, including the
inspected replacement leaves) reports 2179 Ah available at power-up, approximately
129 Ah transferred to the CM, and 410 Ah total remaining at undocking.

Those values do not define one explicit accounting boundary. The stage figures
sum to 1634.7 Ah; the total-capacity change is 1769 Ah. Removing another 129 Ah
leaves only a 5.3 Ah difference, but the source never explicitly says the stage
delivery excludes export. **That numerical agreement does not resolve the
definition.** Neither a second subtraction nor an implicit correction is
accepted as flight validation.

The [charging transcript](https://apollojournals.org/afj/ap13fj/21day5-batterycharge.html)
also distinguishes LM input charge cost from charge restored to the CM battery.
The input/output boundary and charger losses matter; Ah are not transferred
one for one between batteries at different voltages. The implemented source
ledger separates known LM equipment and export input, debiting the LM source
once. Restored CM charge remains unmodeled. Total and usable reserve remain
separate metrics.

## Reviewable scenarios and the next gate

The separate [component-validation runner](ELECTRICAL-VALIDATION.md) now evaluates
eight switch configurations and three conditional battery histories. Its 31
optional LM-8 design-power entries preserve cross-vehicle assumptions and explicit
thermal-demand sensitivity. Recorded currents and reserve endpoints occur only
in comparison records. The [generated results](../output/electrical-flight-summary.md)
show substantial unresolved demand and initial-state errors; no current-accuracy
or whole-flight acceptance is claimed. The aggregate scenarios below remain
separate historical illustrations.

The artifact keeps the old 92.52 Ah residual only as a superseded comparison.
Moving its late transition to 133:29 gives a 20.29 Ah residual. A different,
clearly assumed 30 A / 12.5 A / 40 A illustration using the TELMU transition
times gives −52.96 Ah. The difference demonstrates sensitivity to missing
chronology and waveform detail; it does not select a fitted winner.

`profile-audit` also evaluates the unchanged TELMU illustration against three
pre-export observations that did not set its current segments. Its 12.5 A
coast segment is 0.7 A above the Flight Director's 11.8 A hourly report at
96 GET. It undershoots the approximately 25 A manual course-correction
load by 12.5 A, then exceeds the reported 10–12 A after post-burn powerdown
by 0.5 A. These are differences against reported values with no acceptance
tolerance. Missing flight initial conditions, duty cycles and equipment loads
still prevent equivalent current predictions from the circuit model.
[Mission Operations Report, p. III-32](https://apollojournals.org/alsj/a13/A13_MissionOpReport.pdf)
[Manual course correction transcript, PAO 106:03 GET](https://apollojournals.org/afj/ap13fj/19day5-themanualcoursecorrection.html)

The remaining acceptance work is concrete:

1. Extend the implemented 13-event [guided power-down replay](ELECTRICAL-POWERDOWN.md)
   beyond its 93 explicit commands and partial source-backed equipment draws.
   Historical GET is a label, not an assumed dwell interval or complete state.
2. Use the implemented separate source ledgers for CM export and known LM
   equipment. Resolve the historical stage-delivery/usable-capacity definitions
   before comparing endpoint budgets as equivalent quantities. Charger output
   charge and circuit-level export routing remain unmodeled.
3. Predict held-out current and battery-history anchors. Do not call observations
   used to set an aggregate load independent validation of that load. The audit
   now lists candidate targets with the model behavior needed for each one.
4. Set comparison tolerances from instrument resolution, calibration and
   timing/graph uncertainty before assessing agreement. No NASA 50 Ah acceptance
   band was found. Keep charge conservation tests separate from historical fit.

The source audit supplies the replay chronology. The guide uses a sandbox
equipment checkout seed and never imposes a 12.5 A target or complete flown
preset. Further headset testing remains deferred by user request; this work
uses source review and automated checks.
