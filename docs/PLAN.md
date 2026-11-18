# Aquarius: Apollo 13 Lunar Module VR simulator — research and plan

Researched 2026-11-16. Every URL in [reference/manifest.json](../reference/manifest.json) was checked live that day (77 of 77 returned 200).

2026-11-17 update: foundations and the declared620-entry cabin/source review
are verified. Phase4 now includes20 source-valued equipment loads, working
CWEA lamp/tone checkout and deterministic persistence alongside the unchanged
LM131R1 CPU. Full historical electrical validation remains open.
An offline component-comparison runner now adds optional LM-8 power proxies,
held-out current comparisons and conditional per-battery histories with explicit
thermal sensitivity; it has not closed the electrical accuracy gate. The user has
explicitly deferred physical headset testing while authorizing further offline
development. See [build status](BUILD-STATUS.md).

## 1. What we are building

A PC VR simulator of LM-7 "Aquarius" as flown on Apollo 13. The player stands in the cabin, every control on every panel works, the real flight software runs in the real computers, and the mission clock follows the actual timeline from the Apollo 13 Flight Journal.

The playable window is the time the LM was the lifeboat: power-up at roughly 57:30 GET through jettison at 141:30 GET, about 84 hours. It can be played in real time, or by jumping to the next event.

Target hardware, as found on this machine: Meta Quest over Link or SteamVR, RTX 4060, Ryzen 5 5600X, 32 GB RAM. Blender 5.2.2 is installed and reachable through MCP.

## 2. What "100% accurate" can and cannot mean

The source material is far better than expected, but five gaps are real. Each has a defined fallback, and the game should label them rather than hide them.

| Area | What exists | Gap | Fallback |
|---|---|---|---|
| LGC software | LM131 rev 1, the exact revision flown, plus the Apollo 13 padload | None | Run it unmodified in yaAGC |
| AGS software | Flight Programs 6 and 8 | Apollo 13 flew FP7, which has not been recovered | Run FP6 (Apollo 11/12) and say so |
| Cockpit layout and systems | AOH Vol 1 "LM 7 and Subsequent" at 300 ppi | No LM-7 Systems Handbook | LM-8 handbook plus LM-5 to LM-9 excerpts |
| Cockpit appearance | Handbook drawings, Apollo 13 onboard photos, photos of surviving LMs | No 3D scan of any LM interior exists; LM-7 burned up | Model from drawings, cross-check against photos |
| Trajectory | Mission Report state vectors, operational trajectory, burn data | Apollo 13 is not in JPL Horizons | Rebuild by integrating between known state vectors and burns |
| Telemetry | Mission Report plots, flight controller logs, LM current profile | No complete telemetry tape set is public | Sim output validated against published plots |

Scale is the other honest point. NASSP, the open-source Apollo add-on for Orbiter, has been modelling these same LM systems with a volunteer team for about twenty years and is still active (last push 2026-10-27). This plan is staged so that each phase ends in something playable, and so that "every switch works" is a number we can measure rather than a claim.

## 3. Source library

Full list with URLs, priorities and sizes: [reference/manifest.json](../reference/manifest.json). Highlights by purpose:

**Cockpit and systems (what every switch does)**
- Apollo Operations Handbook, LM 7 and Subsequent, Vol 1 Subsystems Data, 640 MB at 300 ppi. This is the Aquarius-specific handbook and the primary authority for the control inventory.
- LM-8 Systems Handbook (140 MB) and LM-5 to LM-9 excerpts: the wiring-level schematics.
- AOH Vol 2 Operational Procedures (LM 11 and subsequent), CSM/LM Operational Data Book Vol 3 (mass properties), TN D-6722 (display and control subsystem), LM structures study guide.
- Virtual AGC document library: 2,086 PDFs, including Grumman interface control documents and Level III drawings for LM-4 through LM-15.

**What the crew actually did**
- Apollo 13 flown documents: LM Activation Checklist, LM Contingency Checklist, LM Data Card Book, LM-7 G&N Dictionary, LM Timeline Book, revised flight plan (54 h to splashdown), mission rules.
- Flight Director logs, including the LM power profile and the LM entry procedures read up to the crew.
- Apollo 13 Flight Journal: 33 timestamped chapter pages, plus the technical air-to-ground transcript (TEC), the onboard voice transcript and two Flight Director loop transcripts.

**Flight software**
- `virtualagc/virtualagc` on GitHub: `LM131R1` (flown LGC code), `Manche72R3` (flown CMC code), `FP6`, `yaAGC`, `yaAGS`, `yaDEDA`, `yaYUL`.
- Apollo 13 LGC padloads: "H-2 Prelaunch Erasable Load (LUM131A REV 1)", "Pad loads for LM-7", and the final prelaunch erasable load for the 11 April 1970 launch.
- GSOP R-567 for Luminary 1C, program notes for mission H-2, and the Apollo 13 AGC postflight report.

**Mission physics**
- Apollo 13 Mission Report (MSC-02680) and Supplement 1 (GN&C performance), lunar trajectory notes, Spacecraft Operational Trajectory for mission H-2, AS-508 postflight trajectory, technical crew debriefing.
- JPL DE440 ephemeris for Sun, Earth and Moon positions in April 1970.
- NASA SVS CGI Moon Kit and Deep Star Maps for the view out of the windows.

**Reference implementation**
- `orbiternassp/NASSP`: `Orbitersdk/samples/ProjectApollo/src_lm/` holds C++ models of the LM EPS, ECS, RCS, DPS, APS, CWEA, AGS, radars and telecom, and `Config/ProjectApollo/RTCC/` has Apollo 13 constants.

**Not yet secured**
- Mission audio. Apollo in Real Time (apolloinrealtime.org/13) has the restored air-to-ground and 50 Mission Control channels, and its index files include utterance, telemetry and orbit data, but the site is copyright Ben Feist. The underlying NASA recordings are public domain; I have not yet found a clean bulk source. This needs either a located NASA/archive.org source or permission.
- Interior photo sets of LM-2 (NASM), LM-9 (KSC) and LM-13 (Cradle of Aviation) for surface detail.

One finding worth knowing: NASA has taken the journals off nasa.gov. Old `history.nasa.gov/afj` and `nasa.gov/history/alsj` links now redirect to a landing page or return 404. Everything lives at `apollojournals.org`.

## 4. Architecture

Four layers, each testable without the one above it.

**Layer 1 — Control inventory (single source of truth).** One data file listing every control and indicator: ID, panel, position, type (toggle, lever-lock, guarded, rotary, thumbwheel, circuit breaker, pushbutton, talkback, meter, tape, light), positions, default state and the handbook page it came from. It is extracted from AOH Vol 1 and drives three things: Blender generates the panel geometry from it, the simulation wires its inputs from it, and a test asserts that every entry is modelled, bound and reachable in VR. "Every switch flippable" becomes a coverage percentage.

**Layer 2 — Simulation core.** A headless library with no engine dependency, fixed time step, deterministic and saveable.
- Electrical: descent and ascent batteries, ECAs, buses, every circuit breaker, loads per component. Battery amp-hours are the central resource of the mission.
- Environmental: oxygen, cabin pressure, water and sublimator cooling, glycol loops, CO2 partial pressure with LiOH cartridge depletion (including the CM-canister adapter), cabin temperature.
- Propulsion: DPS with throttle and helium pressurisation, RCS with all 16 jets and propellant feed, APS present but unused.
- Guidance: IMU, AOT, rate gyros, ATCA, hand controllers, FDAI drive, DAP interface.
- Caution and warning, instrumentation, communications (S-band, VHF, antenna pointing and signal strength), lighting, explosive devices.
- Rigid-body dynamics of the docked CSM/LM stack with real mass properties, and n-body trajectory propagation.

**Layer 3 — Flight computers.** yaAGC running LM131R1 with the Apollo 13 padload, wired to the DSKY, IMU, hand controllers and engines through its I/O channels. yaAGS running FP6 with the DEDA. Both are stepped by the simulation clock so time acceleration and save states stay consistent.

**Layer 4 — VR presentation.** Cabin model, hand interaction, panel lighting (electroluminescent, integral, flood), instrument rendering, windows with Earth, Moon, Sun and stars, audio, and the mission director that plays the timeline, capcom calls and checklists.

## 5. Technology choices

- **Engine: Godot 4 with OpenXR (recommended).** Scenes and resources are text, so the whole project can be generated, diffed and reviewed from scripts, which suits building it with Claude and Blender MCP. It is MIT licensed, runs on Quest Link and SteamVR, and Meta funds its XR work. Unity has more mature VR interaction toolkits but relies on editor-driven workflows. Unreal looks best but is heavy for 90 Hz on an RTX 4060 and keeps logic in binary assets.
- **Simulation core in C#** as a plain .NET library with unit tests and a command-line runner (.NET is already installed), used by the Godot .NET build. yaAGC and yaAGS are compiled from C as native DLLs.
- **Asset pipeline:** inventory file → Blender Python (through MCP) → glTF → Godot import script that binds node names to control IDs. Panel legends are rendered as distance-field text, not baked textures, so they stay sharp at arm's length in a headset.
- **Licensing:** the flight software itself is public domain. yaAGC, yaAGS and NASSP are GPL v2 (NASSP adds its own licence file). Linking yaAGC makes the game GPL, which is fine for an open project. A closed commercial release would need the emulators run as separate processes and no NASSP-derived code. NASSP is used here as a reference to check behaviour against, with our models written from the handbooks.

## 6. Phases

Each phase has an exit test. Physical headset acceptance remains deferred by the user; offline electrical development proceeds under that explicit direction. Software milestones and full fidelity gates are tracked separately.

**Phase 0 — Foundations.** Install git, Godot 4 (.NET) and a C toolchain. Download the priority-0 reference set (1.5 GB of documents, plus about 2.3 GB for the two repos) to a data folder outside OneDrive. Build yaAGC and boot LM131R1 to a DSKY prompt on the desktop. *Exit: Verb 35 lamp test runs on an emulated DSKY.*

**Phase 1 — Control inventory.** Extract every control and indicator on panels 1, 2, 3, 4, 5, 6, 8, 11, 12, 14 and 16, plus the AOT, ORDEAL, hand controllers, DSKY, DEDA, ECS valves and overhead and side controls, from AOH Vol 1 LM 7. Record the source page for each. *Exit: inventory reviewed panel by panel against the handbook figures, with a count per panel.*

**Phase 2 — Cabin in Blender.** Pressure shell, panels generated from the inventory, windows, hatches, and one mesh family per control type. Greybox first, then materials and lighting. *Exit: glTF loads in Godot at scale, with every inventory ID present as a node.*

**Phase 3 — VR interaction slice.** Stand in the cabin and operate all control types with motion controllers; states persist; panel lighting works. No systems behind them yet. *Exit: every inventory control can be actuated in the headset at a stable 72 Hz or better.*

**Phase 4 — Electrical and caution/warning.** Batteries, buses, breakers, loads and CWEA. *Exit: running the flown power-down produces a bus current within tolerance of the Flight Director's LM current profile.*

**Phase 5 — Guidance.** yaAGC and yaAGS embedded, DSKY and DEDA in VR, IMU, FDAI, hand controllers, DAP. *Exit: IMU alignment from the CM platform angles and a docked attitude hold, following the flown checklist.*

**Phase 6 — Propulsion and dynamics.** DPS, RCS, docked-stack mass properties, trajectory propagation with DE440. *Exit: the four flown burns reproduce the Mission Report delta-v and the resulting trajectory reaches entry interface within stated tolerance.*

**Phase 7 — Environmental control.** Oxygen, water, cooling, CO2 and cabin temperature. *Exit: CO2 rise, the cartridge swap and water usage match the Mission Report consumables curves.*

**Phase 8 — Communications and mission director.** S-band and antenna management, the timestamped event timeline, transcript-driven capcom, checklists as in-cabin books. *Exit: play from 57:30 to 141:30 GET with every flown procedure completable.*

**Phase 9 — World and polish.** Earth, Moon and star field through the windows, sunlight entering the cabin, cabin sounds, crewmates, pre-accident LM visit, CM power-up and jettison bookends.

## 7. Mission anchors for the timeline

The listed event anchors, except the approximate LM power-up window, were visually verified against Mission Report Table 3-I (printed page 3-2, PDF page 23). Machine-readable times and source evidence are in `reference/mission-events.json`. Table times are rounded to one second. Range zero was 19:13:00 UTC; lift-off followed 0.65 seconds later. Event selection does not yet restore flown trajectory, attitude or AGC erasable state.

| GET | Event |
|---|---|
| 000:00:00 | Range zero, 11 April 1970, 19:13:00 UTC; lift-off at 19:13:00.65 UTC |
| 055:54:53 | Oxygen tank 2 failure |
| ~057:30 | LM power-up, guidance platform transferred from CM |
| 061:29:43 | DPS burn to free-return, 34 s |
| 079:27:39 | PC+2 DPS burn, 4 min 24 s |
| 105:18:28 | Manual DPS midcourse burn, 14 s, flown on the Earth terminator |
| 137:39:52 | Final midcourse burn on LM RCS |
| 138:01:48 | Service module jettison |
| 141:30:00 | LM jettison |
| 142:40:46 | Entry interface |
| 142:54:41 | Splashdown |

## 8. Risks and open decisions

1. **Repo location.** This folder is inside OneDrive on C:, which has 35 GB free. Godot's cache and large binary assets sync badly. Recommendation: reference data on D: (1.86 TB free), and move the project to D: before Phase 2.
2. **Mission audio rights** (see section 3). The game works with text capcom until this is settled.
3. **AGS FP7** is unrecoverable for now. If it ever surfaces in the Virtual AGC project it drops in.
4. **Readability in VR.** A Quest headset at Link bitrate may not resolve the smallest panel legends. Mitigations are distance-field text and a lean-in zoom; this is tested in Phase 3 before the art is finished.
5. **Time scale.** Eighty-four real hours needs save states and time acceleration that keep both computers in step. Designed in from Phase 2 of the sim core, tested in Phase 5.
6. **Scope.** Phases 0 to 3 give a cockpit you can stand in and operate. Phases 4 to 8 are the long part; each adds one subsystem and its exit test.
