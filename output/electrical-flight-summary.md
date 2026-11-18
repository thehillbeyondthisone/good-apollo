# Electrical current and battery-history comparison

Full electrical flight validation remains OPEN. The figures below are component-model outputs with explicit LM-8 transfer, initial-state and thermal-duty assumptions. No unknown load or duty fraction was fitted to a recorded current or reserve.

| Configuration | Predicted source A | Recorded A | Difference from reported midpoint A | Status |
|---|---:|---:|---:|---|
| coast_thermal_open | 10.136 | 11.800 | -1.664 | NOT_ASSESSED_NO_TOLERANCE |
| manual_mcc_thermal_open | 17.639 | 25.000 | -7.361 | NOT_ASSESSED_NO_TOLERANCE |
| post_mcc_thermal_open | 10.136 | 10.000-12.000 | -0.864 | NOT_ASSESSED_NO_TOLERANCE |
| coast_thermal_demand | 13.769 | 11.800 | 1.969 | NOT_ASSESSED_NO_TOLERANCE |
| manual_mcc_thermal_demand | 42.439 | 25.000 | 17.439 | NOT_ASSESSED_NO_TOLERANCE |
| post_mcc_thermal_demand | 13.769 | 10.000-12.000 | 2.769 | NOT_ASSESSED_NO_TOLERANCE |

The thermal-open and continuous-demand cases are sensitivity experiments, not a confidence interval. Values between the extremes are not automatically valid predictions. Source table resolution does not establish an acceptance tolerance.

| Battery replay | Source delivered Ah | Remaining total Ah | CM-export input Ah | Conservation error Ah |
|---|---:|---:|---:|---:|
| conditional_mission_thermal_open | 1223.775 | 955.225 | 114.616 | 0.00e+0 |
| conditional_mission_thermal_demand | 2179.000 | 0.000 | 103.942 | -4.55e-13 |
| incremental_coast_to_midcourse | 356.057 | 1822.943 | 0.000 | -4.55e-13 |

The conditional mission histories use a hypothetical proportional distribution of the reported 2179 Ah at 57:44. The late-start history is an incremental sandbox replay, not an absolute flight checkpoint. Continuous-demand cases can exhaust sources; zero remaining capacity does not reproduce the flown history.

| History and target | GET | Model value | Recorded interval | Phase |
|---|---|---:|---:|---|
| conditional_mission_thermal_open: coast_96h (sourceCurrentA) | 096:00:00 | 10.136 | 11.800 | after_events |
| conditional_mission_thermal_open: midcourse (sourceCurrentA) | 105:18:28 | 17.639 | 25.000 | after_events |
| conditional_mission_thermal_open: post_midcourse (sourceCurrentA) | 106:03:00 | 10.136 | 10.000-12.000 | after_events |
| conditional_mission_thermal_open: charging (sourceCurrentA) | 114:00:00 | 18.136 | 19.200 | after_events |
| conditional_mission_thermal_open: battery3_delivered_before_removal (batteryConsumedAh) | 139:16:00 | 271.886 | 394.000 | before_events |
| conditional_mission_thermal_open: battery3_current_before_removal (batteryCurrentA) | 139:16:00 | 2.966 | 0.000-1.000 | before_events |
| conditional_mission_thermal_open: total_at_jettison (totalRemainingAh) | 141:30:00 | 955.225 | 410.000 | after_events |
| conditional_mission_thermal_demand: coast_96h (sourceCurrentA) | 096:00:00 | 13.769 | 11.800 | after_events |
| conditional_mission_thermal_demand: midcourse (sourceCurrentA) | 105:18:28 | 0.000 | 25.000 | after_events |
| conditional_mission_thermal_demand: post_midcourse (sourceCurrentA) | 106:03:00 | 0.000 | 10.000-12.000 | after_events |
| conditional_mission_thermal_demand: charging (sourceCurrentA) | 114:00:00 | 21.769 | 19.200 | after_events |
| conditional_mission_thermal_demand: battery3_delivered_before_removal (batteryConsumedAh) | 139:16:00 | 397.628 | 394.000 | before_events |
| conditional_mission_thermal_demand: battery3_current_before_removal (batteryCurrentA) | 139:16:00 | 0.000 | 0.000-1.000 | before_events |
| conditional_mission_thermal_demand: total_at_jettison (totalRemainingAh) | 141:30:00 | 0.000 | 410.000 | after_events |
| incremental_coast_to_midcourse: incremental_midcourse (sourceCurrentA) | 105:18:28 | 42.439 | 25.000 | after_events |
| incremental_coast_to_midcourse: incremental_post_midcourse (sourceCurrentA) | 106:03:00 | 13.769 | 10.000-12.000 | after_events |

Battery 3 is sampled before its commanded removal. Its delivered charge is cumulative only within the assumed history. The final 410 Ah total reserve is kept separate from the reported 189.6 Ah usable reserve.

Inputs: `reference/electrical-flight-configurations.json` and `reference/electrical-flight-loads.json`. Full per-load contributions, skipped unmodeled commands, source receipts, qualification text and exact fingerprints are in `output/electrical-flight-validation.json`.

Hourly and target-time per-battery model outputs are exported to `output/electrical-battery-history.csv`. They are predictions, not a telemetry tape.
