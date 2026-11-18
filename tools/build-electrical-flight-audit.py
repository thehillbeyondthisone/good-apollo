"""Build a source-qualified Apollo 13 electrical chronology and accounting audit.

This records observations and explicitly assumed scenario intervals. It does not
fit component loads to a reserve total or treat an aggregate replay as independent
flight validation. The CLI reads the two computed report sections of this file.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def hours(get):
    h, m, s = (float(x) for x in get.split(':'))
    return h + m / 60 + s / 3600


def receipt(path):
    p = Path(path)
    if not p.exists():
        return dict(path=path, available=False)
    return dict(path=path, available=True, bytes=p.stat().st_size,
                sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                hashMeaning='Local download integrity receipt, not a publisher checksum')


def preferred_receipt(stable_path, cache_path):
    result=receipt(stable_path if Path(stable_path).exists() else cache_path)
    result['preferredStablePath']=stable_path
    result['cachePath']=cache_path
    return result


sources = {
    'mission_report': dict(title='Apollo 13 Mission Report, MSC-02680',
        url='https://ntrs.nasa.gov/citations/19710003598',
        copies=[receipt('D:/apollo-ref/a13-mission-data/a13-mission-report-197007.pdf'),
                receipt('D:/apollo-ref/a13-mission-data/43-a13-mission-report.pdf')],
        reviewedPages=[dict(copy='small',pdfPages=[45,62,63,64,6,7],printedPages=['6-1','7-6','7-7','7-8']),
                       dict(copy='high_resolution',pdfPages=[37,54,55,56],printedPages=['6-1','7-6','7-7','7-8'])],
        anomalyReview=dict(sections=['14.2.2','14.2.3'],smallCopyPdfPages=[136,137,138,140,141],
                           printedPages=['14-27','14-28','14-29','14-31','14-32']),
        chargeReserveLocator='Section 7.1.6, printed 7-4 and Figure 7.1-1',
        review='Complete rendered leaves visually read; main-body and replacement 7-7/7-8 compared, and Figure 14-16 read from the original scan.',
        qualification='No corrected replacement for 6-1 found in the inspected Change 1 front matter.'),
    'mission_ops_telmu': dict(title='Mission Operations Report, Apollo 13, 28 April 1970, Appendix G TELMU Post Mission Report',
        url='https://apollojournals.org/afj/ap13fj/pdf-hr/a13-mission-ops-report.pdf',
        copy=preferred_receipt('D:/apollo-ref/a13-mission-data/a13-mission-ops-report.pdf',
                               str(ROOT/'tmp/pdfs/electrical/a13-mission-ops-report.pdf')),
        reviewedPdfPages=[235,236,237,238,239,240],printedPages=['G-1','G-2','G-3','G-4','G-5','G-6'],
        review='Full rendered pages visually read; original NASA Flight Control Division report, not later commentary.'),
    'mission_ops_electrical': dict(title='Mission Operations Report, Apollo 13, 28 April 1970, mission narrative and Appendix E EECOM',
        url='https://apollojournals.org/alsj/a13/A13_MissionOpReport.pdf',
        printedNarrativePages=['III-32','III-36'],
        reviewedHighResolutionPdfPages=[159,162,173,175],printedAppendixPages=['E-9','E-12','E-20','E-21'],
        qualification='EECOM calculated CM entry battery reserves and described the LM export configuration. The plotted actual CM loads in Figure 5 start after the final changeover and supply no direct samples of LM export.'),
    'contingency': dict(title='Apollo XIII LM-7 Contingency Checklist, revised 31 March 1970',
        copy=receipt('D:/apollo-ref/a13-procedures/78-a13-contingency-checklist.pdf'),
        reviewedPdfPages=[81,82,83,84],printedPages=['PWR-5','PWR-6','PWR-7','PWR-8'],
        review='Full-page visual review; printed baseline differs from in-flight voice amendments.'),
    'fd_profile': dict(title='Flight Director LM current-profile planning sheet',
        copy=receipt('D:/apollo-ref/a13-procedures/09-a13-fdlog-lm-current-profile.pdf'),
        reviewedPdfPages=[1,3],review='Upright full-sheet visual review',
        qualification='Planning/available profile; not measured telemetry. Solid LM and dashed CM lines are separately labeled. Do not combine lines without establishing accounting boundary.'),
    'fj_pc2': dict(title='Apollo 13 Flight Journal, Day 4 part 2, Leaving the Moon',
        url='https://apollojournals.org/afj/ap13fj/13day4-leaving-moon.html',
        sourceType='Contemporaneous air-to-ground and PAO transcript as presented in the journal',
        locators=['079:32:05','079:42:51','079:49:52','081:47','082:01-082:28'],
        webLineRangesAtReview=[[536,568],[603,658],[1602,1808]]),
    'fj_manual_mcc': dict(title='Apollo 13 Flight Journal, Day 5 part 3, Manual Course Correction Burn',
        url='https://apollojournals.org/afj/ap13fj/19day5-themanualcoursecorrection.html',
        locators=['105:43:48','105:43:59','105:52:28','105:52:40','PAO 106:03'],sourceType='Contemporaneous air-to-ground and PAO transcript'),
    'fj_battery_anomaly': dict(title='Apollo 13 Flight Journal, Day 5 part 1, A Thump and Snowflakes in Space',
        url='https://apollojournals.org/afj/ap13fj/17day5-thumpandsnowflakes.html',
        locators=['099:49:52–099:55:08','101:01:48–101:05:49']),
    'fj_charge': dict(title='Apollo 13 Flight Journal, Day 5 part 5, Starting the Battery Charge',
        url='https://apollojournals.org/afj/ap13fj/21day5-batterycharge.html',
        locators=['110:57:23','111:06:54–111:15:49','111:20:03–111:20:45','111:38:15–111:38:36',
                  '112:06:11','112:11:57','PAO 112:18','112:35:36','112:48:33','115:44:17','PAO 119:44']),
    'fj_packing': dict(title='Apollo 13 Flight Journal, Day 6 part 1, Packing Up',
        url='https://apollojournals.org/afj/ap13fj/22day6-packingup.html',
        locators=['120:01:06','120:59:16','PAO 122:24','122:46:12–122:51:33','123:06:21',
                  '123:11:41–123:12:07','123:21:32–123:22:17']),
    'fj_reactivation': dict(title='Apollo 13 Flight Journal, Day 6 part 2, The Reactivation Checklist',
        url='https://apollojournals.org/afj/ap13fj/23day6-thereactivationchecklist.html',
        locators=['125:53:31','125:54:19','125:57:51','126:02:41','127:11:09','128:02:47','128:15:50']),
    'fj_rest': dict(title='Apollo 13 Flight Journal, Day 6 part 3, Worn Out Crew',
        url='https://apollojournals.org/afj/ap13fj/24day6-wornoutcrew.html',
        locators=['PAO 130:39'],webLineRangesAtReview=[[804,806]]),
    'fj_final_powerup': dict(title='Apollo 13 Flight Journal, Day 6 part 4, Last Course Correction',
        url='https://apollojournals.org/afj/ap13fj/25day6-thelastcoursecorrection.html',
        locators=['132:30:30','132:31:02','133:30:43','133:31:32','PAO 133:35','PAO 133:55','PAO 134:42','PAO 135:52'],
        webLineRangesAtReview=[[49,54],[245,258],[314,315],[456,458],[694,706]],
        sourceType='Contemporaneous crew/CapCom and PAO reports; retrospective peak report gives no peak duration.'),
    'fj_cm_powerup': dict(title='Apollo 13 Flight Journal, Day 6 part 6, Odyssey Resurrected',
        url='https://apollojournals.org/afj/ap13fj/27day6-odysseyresurrected.html',
        locators=['140:09:52–140:11:34']),
    'eps_experience': dict(title='Apollo Experience Report: Lunar Module Electrical Power Subsystem, NASA TN D-6977',
        url='https://ntrs.nasa.gov/api/citations/19720025198/downloads/19720025198.pdf',
        printedPages=['13','14'],qualification='EPS telemetry normally sampled once per second; the report cites the Apollo 13 transient as a case where sampling was too slow.'),
    'csm_news_reference': dict(title='Apollo Spacecraft News Reference, North American Rockwell and NASA',
        url='https://apollojournals.org/alsj/CSM_News_Reference_H_Missions.pdf',
        printedPages=['113','114'],qualification='Design description for the shared DC input and three-phase AC boost of the CM battery charger.'),
    'review_board': dict(title='Apollo 13 Review Board, Appendix B, section B6',
        url='https://ntrs.nasa.gov/api/citations/19700078726/downloads/19700078726.pdf',
        copy=receipt(str(ROOT/'tmp/pdfs/electrical/review-board-appendix-b.pdf')),
        textReviewedPdfPages=[116,118],printedPages=['B-102','B-104'],
        review='Native text reviewed; not treated as an independently sampled telemetry series.',
        qualification='Predicted post-burn 17 A versus achieved 12 A reinforces that planning and actual loads differ.'),
}

anchors = [
    dict(id='internal_power',get='057:44:00',kind='configuration',source='mission_ops_telmu',pdfPage=235,printedPage='G-1',
         event='LM on internal power by this approximate time; telemetry received 057:57.'),
    dict(id='activation_load',getWindow=['057:44:00','060:40:00'],kind='observed_range',currentA=[45,50],source='mission_ops_telmu',pdfPage=235,printedPage='G-1',
         qualification='Eventual initial activation load; exact start/end of this range are not given.'),
    dict(id='initial_reduction',get='060:40:00',kind='observed_range',currentA=[35,40],source='mission_ops_telmu',pdfPage=236,printedPage='G-2'),
    dict(id='pc2_shutdown',get='079:32:05',kind='event',source='fj_pc2',event='Crew calls engine shutdown; full electrical powerdown is later.'),
    dict(id='remaining_81h',get='081:47:00',kind='reported_capacity_estimate',remainingAh=1498,metric='LM remaining; exact reserve convention not specified in call',source='fj_pc2'),
    dict(id='deep_powerdown',get='082:30:00',kind='observed_average',currentA=12.5,source='mission_ops_telmu',pdfPage=239,printedPage='G-5',
         qualification='Approximately this transition time; initial 28-50 A levels preceded it. No continuous 12.5 A telemetry trace is supplied.'),
    dict(id='coast_hourly_summary',get='096:00:00',kind='observed_aggregate',currentA=11.8,usableRemainingAh=1312,
         source='mission_ops_electrical',printedPage='III-32',qualification='Flight Director hourly summary of present draw and usable reserve before LM-to-CM transfer.'),
    dict(id='descent_battery_current_surge_summary',get='097:13:56',kind='reported_peak',currentGreaterThanA=100,durationSeconds=None,
         source='mission_report',pdfPage=45,printedPage='6-1',qualification='The section 6.2 summary does not identify an individual battery as the 100 A channel. Peak duration and signed current are not established.'),
    dict(id='battery2_warning',get='099:49:52',kind='first_crew_report',source='fj_battery_anomaly',
         alternateReportGets=[dict(get='099:51:00',source='mission_ops_telmu',printedPage='G-5'),
                              dict(get='099:51:09',source='mission_report',printedPage='14-29'),
                              dict(get='099:54:00',source='mission_report',printedPage='6-1')],
         event='Lovell reports a Battery 2 warning and confirms the master alarm at 099:50:26.',
         qualification='The first crew call establishes that a warning had already occurred, not its exact onset. The later indication was diagnosed as erroneous.'),
    dict(id='manual_mcc_load',get='105:18:28',kind='observed_approximate_during_event',currentA=25,source='fj_manual_mcc',
         qualification='PAO at106:03 describes approximately25 A during the manual course-correction burn; amplitude is approximate, duration not established here.'),
    dict(id='post_manual_mcc',get='106:03:00',kind='observed_range',currentA=[10,12],source='fj_manual_mcc'),
    dict(id='battery6_online',get='111:57:00',kind='configuration',batteryId='bat6',source='mission_ops_telmu',pdfPage=240,printedPage='G-6'),
    dict(id='cm_link_connected',get='112:05:00',kind='configuration',exportCurrentA=8,source='mission_ops_telmu',pdfPage=240,printedPage='G-6',
         qualification='Approximate charge draw; physical connection remained until140:00 but current was intermittent.'),
    dict(id='cm_charge_started',get='112:12:00',kind='reported_event',source='fj_charge',
         qualification='PAO at112:18 identifies charging start; link connection and charger start are different events.'),
    dict(id='cm_charge_capacity_plan',get='111:15:49',kind='planning_estimate',lmChargeCostAh=120,cmChargeRestoredAh=20,source='fj_charge',
         qualification='Charger input cost and restored CM charge have different boundaries; do not model a 1:1 Ah transfer.'),
    dict(id='charge_hourly_summary',get='114:00:00',kind='observed_aggregate',currentA=19.2,usableRemainingAh=1084.7,
         source='mission_ops_electrical',printedPage='III-36',qualification='Flight Director hourly summary during the first Battery A charge interval.'),
    dict(id='charge_period_current',get='119:44:00',kind='observed_aggregate',currentA=17.9,usableRemainingAh=974,source='fj_charge',
         qualification='PAO electrical consumables/current report during charging; do not add another CM load to a measured whole-source total.'),
    dict(id='late_charge_period_current',get='122:24:00',kind='observed_approximate',currentA=19,source='fj_packing',
         qualification='PAO reports current load about 19 A while Battery A charge was in progress, before the telemetry interruption.'),
    dict(id='late_coast_low',get='130:39:00',kind='observed_range',currentA=[10,12],source='fj_rest'),
    dict(id='final_powerup_start',get='133:29:00',kind='reported_event',source='fj_final_powerup',
         qualification='Start time reported retrospectively at134:42; earlier than the planning sheet, not136:00.'),
    dict(id='battery5_online',get='133:30:00',kind='configuration',batteryId='bat5',source='mission_ops_telmu',pdfPage=240,printedPage='G-6'),
    dict(id='final_powerup_early',get='133:35:00',kind='observed_range',currentA=[34,35],source='fj_final_powerup',
         qualification='PAO statement between133:35:11 and133:35:41; time rounded to minute.'),
    dict(id='final_powerup_45_50',get='133:55:00',kind='observed_range',currentA=[45,50],source='fj_final_powerup'),
    dict(id='final_powerup_peak',getWindow=['133:29:00','134:42:00'],kind='retrospective_peak',currentA=70,source='fj_final_powerup',
         durationSeconds=None,qualification='Peak occurred before the134:42 report; neither duration nor exact timestamp established. Never integrate70 A over an invented duration.'),
    dict(id='final_plateau',get='134:42:00',kind='observed_approximate',currentA=40,source='fj_final_powerup'),
    dict(id='final_plateau_confirmed',get='135:52:00',kind='observed_approximate',currentA=40,source='fj_final_powerup'),
    dict(id='battery3_removed',get='139:16:00',kind='configuration_and_consumption',batteryId='bat3',deliveredAh=394,currentLessThanA=1,source='mission_ops_telmu',pdfPage=240,printedPage='G-6'),
    dict(id='cm_internal_power',getWindow=['140:10:32','140:11:20'],kind='reported_configuration_window',source='fj_cm_powerup',
         qualification='Crew calls the LM power breakers at the first time and tells Houston to check at the second. TELMU G-6 gives a rounded 140:00 switchover.'),
    dict(id='jettison_usable',get='141:30:00',kind='reported_usable_capacity',usableRemainingAh=189.6,source='mission_ops_telmu',pdfPage=237,printedPage='G-3',
         qualification='Usable reserve, not the Mission Report total remaining410 Ah.'),
]
for a in anchors:
    if 'get' in a:
        a['getHours']=hours(a['get'])
        a['getSeconds']=round(hours(a['get'])*3600)
    if 'getWindow' in a: a['getWindowHours']=[hours(t) for t in a['getWindow']]
anchors.sort(key=lambda a: hours(a['get'] if 'get' in a else a['getWindow'][0]))

switch_events = [
    dict(get='079:49:52',source='fj_pc2',event='Primary S-band power-amplifier breaker OPEN; selector retained PRIMARY.',
         evidenceType='command and readback at079:50:10',endGet=None),
    dict(get='082:03:04',source='fj_pc2',event='ATCA PGNS breaker OPEN.',evidenceType='crew confirms082:03:11'),
    dict(get='082:06:30',source='fj_pc2',event='IMU STBY remains closed; LGC/DSKY and IMU OPR open.',evidenceType='readback'),
    dict(get='082:13:51',source='fj_pc2',event='RCS A/B-2 quad-heater breakers stay closed; panel3 heater switches OFF.',evidenceType='amended control path, not all heater breakers open'),
    dict(get='082:16:37',source='fj_pc2',event='Crew begins executing final powerdown.',evidenceType='procedure transmission completed at082:16:28'),
    dict(get='082:25:03',source='fj_pc2',event='TRACK and FLOOD breakers OPEN.',evidenceType='crew confirmation after permission'),
    dict(get='099:52:13',source='fj_battery_anomaly',event='Panel 16 BAL LOAD cross-tie breaker OPEN.',evidenceType='crew confirms'),
    dict(get='099:53:42',source='fj_battery_anomaly',event='Descent battery 2 taken offline on ground request.',evidenceType='crew reports operation'),
    dict(get='099:55:08',source='fj_battery_anomaly',event='Panel 16 BAL LOAD cross-tie breaker CLOSED.',evidenceType='crew confirms'),
    dict(get='101:02:47',source='fj_battery_anomaly',event='Panel 16 BAL LOAD cross-tie breaker OPEN, then battery 2 back online. Master alarm and battery light return.',
         evidenceType='crew reports operation and immediate indication'),
    dict(get='101:05:49',source='fj_battery_anomaly',event='Panel 16 BAL LOAD cross-tie breaker CLOSED.',evidenceType='crew confirms'),
    dict(get='105:43:59',source='fj_manual_mcc',event='Crew proceeds with post-MCC powerdown after PTC assessment.',evidenceType='crew readback, followed by audible operations and checklist calls'),
    dict(get='105:52:28',source='fj_manual_mcc',event='Primary S-band power-amplifier breaker OPEN and low bit rate, with selector retained PRIMARY.',
         evidenceType='command and crew intent at 105:52:40'),
    dict(get='132:30:30',source='fj_final_powerup',event='Power-amplifier breaker CLOSE and normal voice requested for ranging.',
         confirmedGet='132:31:02',plannedDurationSeconds=900,actualEndGet=None,
         qualification='15 minutes is requested duration, not measured stop time; no132:58 OFF event found on reviewed page.'),
    dict(get='133:31:32',source='fj_final_powerup',event='Use checklist RCS heater steps for now; panel 11 heater breakers will be restored later in the breaker configuration.',
         evidenceType='instruction in response to crew report that panel 11 breakers were out; later closure times unknown'),
]
for event in switch_events:
    event['getHours']=hours(event['get'])
    event['getSeconds']=round(hours(event['get'])*3600)


transient = dict(source='mission_report',figure='14-16',printedPage='14-28',smallCopyPdfPage=137,
    figureWindowGet=['097:13:52','097:13:58'],reportedStartGet='097:13:53',reportedDurationApproxSeconds=2,
    cadenceSource='eps_experience',nominalTelemetrySamplesPerSecond=1,
    graphReadingAllowance=dict(seconds=0.1,volts=0.5,amperes=2,
        qualification='Allowance for visually reading plotted markers and the grid. It excludes instrumentation and sampling uncertainty.'),
    selectedSamples=[
        dict(get='097:13:54.0',channel='bat1',currentMagnitudeA=37),
        dict(get='097:13:54.1',channel='bat2',plotOffScaleHigh=True,plotUpperLimitA=40),
        dict(get='097:13:54.8',channel='bat3',currentMagnitudeA=37),
        dict(get='097:13:54.8',channel='bat4',currentMagnitudeA=30),
        dict(get='097:13:55.0',channel='bat2',plotOffScaleHigh=True,plotUpperLimitA=40),
        dict(get='097:13:55.1',channel='cdr_dc',voltageV=29),
        dict(get='097:13:55.1',channel='lmp_dc',voltageV=27.6),
    ],
    section14Report=dict(bat2CurrentMagnitudeAtLeastA=60,signedCurrentKnown=False,
        balanceLoadTrip=False,reverseCurrentIndication=False,batteryOvercurrentDisconnect=False,
        normalSharingReturnedWithinMinutes=10),
    integratedChargeAh=None,
    qualification='Only plotted markers are sampled evidence. Channels are staggered and Battery 2 clips; the printed connecting lines do not supply intermediate values or an integrated charge.')


def charge_reading(get, battery, volts, amps, source):
    return dict(get=get,getSeconds=round(hours(get)*3600),cmBattery=battery,
                batteryVoltageV=volts,chargerOutputCurrentA=amps,indicatedBatteryTerminalPowerW=round(volts*amps,2),source=source)


cm_transfer = dict(
    routing=dict(source='fj_charge',readupGet=['110:57:23','111:06:54','111:12:42','111:38:36'],
        connectedDestination='CM Main B through the two CM panel 5 LM Power breakers',
        reversalSetup=dict(source='mission_ops_electrical',printedPage='E-9',
            configuration='CM Battery B first supplied the LM control relays through Main B. Once the relays were set, the LM supplied CM Main B.'),
        chargerInputs=['CM Main B DC','CM Inverter 2 supplied by Main B, via CM AC Bus 2'],
        designSource='csm_news_reference',currentLimitA=15,
        currentLimitLocator='CapCom 110:59:39, before execution',
        transferPathModelImplemented=False,
        qualification='Flight procedure establishes the route and protection limit. The limit supplies neither a modeled trip curve nor a measured current.'),
    transitions=[
        dict(id='main_b_connected',source='mission_ops_telmu',get='112:05:00',evidence='TELMU time. Crew reports power-up complete and requests charge Go at 112:06:11.'),
        dict(id='charge_a_start',source='fj_charge',getWindow=['112:06:28','112:11:57'],evidence='From Go to first positive charger reading. PAO rounds the start to 112:12.'),
        dict(id='charge_a_pause',source='fj_packing',getWindow=['122:46:47','122:51:33'],evidence='Crew departs to stop charging, then reports it secured.'),
        dict(id='cm_telemetry_acquired',source='fj_packing',get='123:06:21',evidence='Houston confirms CM telemetry during the charging pause. Main B was supplied by the LM.'),
        dict(id='charge_a_restart',source='fj_packing',getWindow=['123:18:11','123:21:32'],evidence='Crew reports restart in progress, then confirms Battery A charging.'),
        dict(id='charge_b_start',source='fj_reactivation',getWindow=['125:57:51','126:02:41'],evidence='Crew begins the changeover, then reports Battery B on charge.'),
        dict(id='charge_b_stop',source='fj_reactivation',getWindow=['127:11:09','128:02:47'],evidence='Last positive reading included here to CapCom confirmation that the charge switch was already OFF. Exact stop time unresolved.'),
        dict(id='main_b_disconnected',source='fj_cm_powerup',getWindow=['140:10:32','140:11:20'],evidence='Crew callout at the LM power breakers and subsequent transfer verification. TELMU G-6 gives rounded 140:00.'),
    ],
    chargerReadings=[
        charge_reading('112:11:57','A',34.3,2.5,'fj_charge'),
        charge_reading('112:35:36','A',35.0,2.4,'fj_charge'),
        charge_reading('112:48:33','A',37.8,2.3,'fj_charge'),
        charge_reading('115:44:17','A',39.2,1.4,'fj_charge'),
        charge_reading('120:01:06','A',39.4,1.27,'fj_packing'),
        charge_reading('120:59:16','A',39.5,1.25,'fj_packing'),
        charge_reading('122:46:12','A',39.4,1.25,'fj_packing'),
        charge_reading('123:22:17','A',39.4,1.4,'fj_packing'),
        charge_reading('126:02:41','B',39.6,1.1,'fj_reactivation'),
        charge_reading('127:11:09','B',39.4,1.25,'fj_reactivation'),
    ],
    cmNetCapacityChange=dict(source='mission_report',printedSection='7.1.6',cmEntryBatteriesAvailableAtShutdownAh=99,
        cmEntryBatteriesAvailableAfterChargeAh=118,netCmCapacityIncreaseAh=19,
        qualification='Net change in reported available CM reserve. Integrated charger output and instantaneous efficiency are separate quantities.'),
    cmEECOMCrossCheck=dict(source='mission_ops_electrical',printedPages=['E-9','E-12','E-21'],
        earlyTelemetry=dict(get='102:00:00',supply='CM Battery B',durationLessThanMinutes=10),
        laterTelemetry=dict(get='123:00:00',supply='LM via CM Main B',durationApproxMinutes=7),
        postChargeReserve=dict(get='128:00:00',byBatteryAh=dict(A=40.0,B=40.0,C=38.8),totalAh=118.8,
            qualification='EECOM calculated reserves. Battery C was not charged. The Mission Report separately reports 118 Ah.'),
        preentryLoads=dict(lmSuppliedMainB=['CM RCS Ring 2 preheat','caution and warning','lighting'],
            batteryCSuppliedMainA=['CM RCS Ring 1 preheat'],
            qualification='Time labels EI–6:30 to EI–2:30 are the EECOM summary. The actual load overlay in Figure 5 begins after the final LM disconnect. It is not an LM export waveform.')),
    qualification='The reported 8 A charge draw is approximate LM input. Crew readouts are CM charger output. Neither these sparse readings nor the connected interval establish total charger output, charger efficiency, or a continuous export load.')


def scenario(id, segments, note, cm=129):
    cooked=[]
    for start,end,amps,basis in segments:
        if hours(end)<=hours(start): raise ValueError(id)
        cooked.append(dict(startGet=start,endGet=end,startGetHours=hours(start),endGetHours=hours(end),
                           currentA=amps,useAh=round((hours(end)-hours(start))*amps,6),basis=basis))
    used=sum(x['useAh'] for x in cooked)
    return dict(id=id,segments=cooked,lmScenarioUseAh=round(used,6),cmTransferAh=cm,
        transferBoundary='CM export added once to a scenario explicitly interpreting segment currents as LM housekeeping only; this interpretation is conditional.',
        predictedRemainingAh=round(2179-used-cm,6),reportedTotalRemainingAh=410,
        residualAh=round(2179-used-cm-410,6),
        independentValidationPassed=False,note=note)


legacy=scenario('legacy_coarse_superseded',[
    ('058:00:00','079:32:06',30,'Mission Report aggregate approximated as constant; original audit endpoint79.535h'),
    ('079:32:06','136:00:00',12,'Superseded transition assumptions'),
    ('136:00:00','141:30:00',40.7,'Flight Director planning amplitude, not measured')],
    'Reproduces the old92.52Ah residual for comparison only; known timing omissions invalidate it as a flown schedule.')
early=scenario('late_boundary_sensitivity',[
    ('058:00:00','079:32:06',30,'Legacy initial assumption retained to isolate one change'),
    ('079:32:06','133:29:00',12,'Legacy low current, with actual final powerup start'),
    ('133:29:00','141:30:00',40.7,'Planning amplitude retained as sensitivity, not observed constant')],
    'Only final boundary moved to133:29. Nearer reserve agreement is not an independent pass; early powerdown transition and ramp remain wrong/incomplete.')
telmu=scenario('telmu_chronology_illustrative',[
    ('058:00:00','082:30:00',30,'Simplified30A average inside reported28-50A initial range'),
    ('082:30:00','133:29:00',12.5,'TELMU powered-down average extended across unmeasured changes; assumption'),
    ('133:29:00','141:30:00',40,'Observed later plateau applied as an illustrative constant; excludes unknown warmup shape')],
    'Chronology improved but not a reconstructed waveform. Aggregate anchors calibrate this scenario and therefore cannot independently validate it.')


def compare_held_out_current(scenario, anchor):
    segment = next(s for s in scenario['segments']
                   if s['startGetHours'] <= anchor['getHours'] < s['endGetHours'])
    predicted = segment['currentA']
    reference = anchor['currentA']
    comparison = dict(anchorId=anchor['id'],get=anchor['get'],source=anchor['source'],
                      referenceCurrentA=reference,predictedCurrentA=predicted)
    if isinstance(reference, list):
        low, high = reference
        comparison['outsideReportedRangeA'] = round(max(low - predicted, predicted - high, 0), 2)
    else:
        comparison['predictedMinusReportedA'] = round(predicted - reference, 2)
    return comparison


anchors_by_id = {a['id']: a for a in anchors}
spot_checks = dict(scenarioId=telmu['id'],
    qualification='These pre-export PAO references were not used to choose the illustrative scenario segments. The comparison checks the assumed aggregate against unused observations. The magnitude or stated range of each observation is approximate, and no acceptance tolerance or component-model pass is claimed.',
    acceptanceTolerance=None,
    comparisons=[compare_held_out_current(telmu, anchors_by_id[anchor_id])
                 for anchor_id in ('coast_hourly_summary', 'manual_mcc_load', 'post_manual_mcc')])


stage=1434.7+200
budget=dict(purpose='Reported-total boundary hypotheses; not transient-model validation',
    artifact='reference/electrical-flight-audit.json',
    reportedDescentDeliveredAh=1434.7,reportedAscentDeliveredAh=200,
    reportedStageDeliveredAh=stage,reportedCmTransferAh=129,
    reportedPowerupAvailableAh=2179,ratedCapacityAh=2192,reportedRemainingAh=410,
    ratedCapacityMinusPowerupAh=13,
    reportedUsableRemainingAh=189.6,
    totalDepletionFromPowerupAh=2179-410,stageDeliveredDifferenceAh=round(2179-410-stage,6),
    remainingIfDeliveredIncludesCmAndUsesPowerupEpochAh=round(2179-stage,6),
    remainingIfDeliveredExcludesCmAndUsesPowerupEpochAh=round(2179-stage-129,6),
    remainingIfDeliveredIncludesCmAndUsesRatedEpochAh=round(2192-stage,6),
    remainingIfDeliveredExcludesCmAndUsesRatedEpochAh=round(2192-stage-129,6),
    residualIfCmSubtractedAgainAh=round(2179-stage-129-410,6),
    transferAccountingResolved=False,independentValidationPassed=False,
    note='No reviewed source explicitly defines whether section6.2 delivered totals exclude129Ah export. Near agreement after another subtraction is not proof. A model integrating complete source currents includes export once. Usable189.6Ah and total410Ah are different metrics.')

profile=dict(purpose='Source-qualified chronology scenarios and uncertainty; not full flown-profile reproduction',
    artifact='reference/electrical-flight-audit.json',initialAh=2179,reportedRemainingAh=410,
    validationPassed=False,independentValidationPassed=False,
    supersededLegacy=legacy,scenarios=[early,telmu],heldOutSpotChecks=spot_checks,
    timingSensitivityAh=round(legacy['predictedRemainingAh']-early['predictedRemainingAh'],6),
    warmupPeak=dict(peakA=70,durationSeconds=None,integratedChargeAh=None,
                   reason='Only a peak is reported; duration is unknown. No70A rectangular interval is invented.'),
    nasaPublishedAcceptanceTolerance=None,
    acceptancePolicy='No pass/fail tolerance is inferred from reserve agreement of an aggregate-calibrated scenario.',
    limitations=['Sparse aggregate observations are not a sampled current history.',
                 '58:00 is a rounded scenario starting epoch; internal power was present by57:44, and the exact2179Ah capacity epoch/per-battery allocation is not established.',
                 'CM export must not be added to a measured whole-source current that already includes it.',
                 'Initial unequal bus sharing, individual battery history and unusable reserve are not reproduced.',
                 'Heater cycles, course-correction peaks, comm changes and final ramp durations remain incomplete.'])

audit=dict(schemaVersion=1,reviewDate='2026-11-17',status='SOURCE CHRONOLOGY IMPROVED; INDEPENDENT FLIGHT VALIDATION OPEN',
    sourcePolicy='GET and printed leaf are stable locators. Web line ranges are only the rendering retrieved during this review. Source text and figures were not modified.',
    sources=sources,currentAnchors=anchors,switchEvents=switch_events,
    batteryTransient=transient,cmPowerTransfer=cm_transfer,
    configurationIntervals=[
        dict(startGet='060:34:00',endGet='063:40:00',state='cross-ties open',source='mission_ops_telmu',pdfPage=239,printedPage='G-5'),
        dict(startGet='078:16:00',endGet='080:00:00',state='cross-ties open',source='mission_ops_telmu',pdfPage=239,printedPage='G-5'),
        dict(endGet='082:30:00',cdrToLmpBusPowerRatio=4,qualification='Ratio described until82:30; not necessarily invariant through every transient.',source='mission_ops_telmu',pdfPage=239,printedPage='G-5'),
        dict(startGet='099:53:42',endGet='101:02:47',state='Descent battery 2 manually disconnected',source='fj_battery_anomaly',
             qualification='Crew event reports. TELMU rounds the interval to about one hour.'),
        dict(startGet='112:05:00',endGet='140:00:00',state='LM connected to CM Main B; current intermittent',source='mission_ops_telmu',pdfPage=240,printedPage='G-6',
             qualification='Rounded summary interval; see cmPowerTransfer transitions for actual crew callouts.')],
    planningProfile=dict(source='fd_profile',pdfPage=1,status='PLANNING_ONLY_NOT_TELEMETRY',
        solidLineApproximateIntervals=[
            dict(startGetHours=120,endGetHours=126.5,currentA=11.9),
            dict(startGetHours=126.5,endGetHours=136,currentA=14.7),
            dict(startGetHours=136,endGetHours=142.6,currentA=40.7)],
        intervalQualification='Horizontal boundaries read approximately from plotted grid, not timestamped commands; late planned end is not actual LM jettison time.',
        reserveAnnotationsAh=dict(profilePad=296,unusable=209,usablePad=87),
        accountingCaution='Dashed CM and solid LM lines are separately labeled. Do not integrate both as source current or add export without a declared boundary.'),
    checklistReconciliation=dict(baselineSource='contingency',pdfPages=[81,82,83,84],printedPages=['PWR-5','PWR-6','PWR-7','PWR-8'],
        inFlightAmendmentSource='fj_pc2',
        conclusion='The stock rescue-orbit emergency checklist is a baseline, not the flown final configuration. Apply time-tagged voice amendments and distinguish read-up from execution.',
        unambiguousDifferences=['VHF removed from remaining functions; only one audio station retained.',
                               'PGNS was retained for PTC setup then removed at final deep powerdown.',
                               'IMU standby heater retained despite PGNS operate/DSKY off.',
                               'RCS A/B-2 heater breakers closed with panel3 switches off; do not infer heater state from breaker alone.',
                               'TRACK/FLOOD eventually opened after an initial instruction to leave lighting breakers closed.']),
    accountingResolution=dict(status='UNRESOLVED_SOURCE_BOUNDARY',
        established=['129Ah is reported LM-to-CM export across loads that include charging and pre-entry equipment. The reported CM battery reserve rose by 19Ah.',
                     'Section6.2 stage-delivery figures and section7.2.5 total-capacity figures do not close under one explicitly defined boundary.',
                     'TELMU189.6Ah usable reserve is distinct from Mission Report410Ah total remaining.'],
        requiredEvidence='Original per-battery integrated-current ledger or explicit author definition of stage-delivered charge, plus usable-capacity/reserve convention.',
        implementationRule='Track LM housekeeping and CM export separately, debit both exactly once at the source, and compare only identically defined metrics/epochs.'),
    validationCriteria=[
        dict(id='chronology',criterion='Represent final deep-powerdown execution near82:30 and final powerup start133:29; do not keep12A until136.',status='SOURCE BASIS ESTABLISHED'),
        dict(id='observation_vs_plan',criterion='Tag30/12/12.5A summaries, individual current samples, planning40.7A and70A peak distinctly; never turn a peak into a duration.',status='REQUIRED'),
        dict(id='boundary',criterion='Declare source-current, LM-housekeeping, CM-export, delivered and usable-reserve boundaries; no duplicate export subtraction.',status='OPEN'),
        dict(id='independence',criterion='Use equipment-derived loads and actual switch history to predict held-out current/capacity anchors; observations used to choose aggregate load cannot count as independent validation.',status='TARGETS RECORDED; MODEL COMPARISON OPEN'),
        dict(id='tolerance',criterion='Set tolerances before comparison from telemetry resolution, calibration, time uncertainty and documented graph-reading uncertainty. No NASA50Ah acceptance band has been found.',status='OPEN'),
        dict(id='battery_sharing',criterion='Account for recorded unequal early bus sharing, battery5/6 connection times and battery3 withdrawal; equal sharing is not the flown history.',status='OPEN'),
        dict(id='conservation',criterion='Retain exact deterministic Ah/Wh conservation and source exhaustion software tests separately from historical accuracy.',status='SOFTWARE GATE SEPARATE')],
    heldOutTargets=dict(status='AVAILABLE FOR INDEPENDENT COMPARISON; NO MODEL PASS CLAIMED',
        qualification='Use only targets excluded from calibration of the model being evaluated. The existing aggregate scenarios already use some TELMU and PAO anchors.',
        componentModelEvaluated=True,
        componentModelScope='Optional source-constrained LM-8 design-power proxy comparisons and conditional battery replay; not a complete LM-7 flight-current prediction.',
        componentModelReport='output/electrical-flight-validation.json',
        componentModelManifest='reference/electrical-flight-configurations.json',
        fullVehicleComponentModelValidated=False,
        componentModelBlocker='Component subtotals are now evaluated separately from aggregate scenarios. LM-8 transfer uncertainty, historical starting battery allocations, omitted equipment, switching, thermal duties, unequal sharing and acceptance tolerances remain unresolved. Charger output, battery transient waveforms and usable reserves are not predicted.',
        targets=[
            dict(id='charging_source_draw',references=['charge_hourly_summary','charge_period_current','late_charge_period_current'],
                 modelRequirement='Complete LM loads and simultaneous CM export input at the source.'),
            dict(id='charger_output',references=['cmPowerTransfer.chargerReadings','cmPowerTransfer.cmNetCapacityChange'],
                 modelRequirement='CM input path, charger and entry battery state model.'),
            dict(id='battery_transient',references=['batteryTransient.selectedSamples','batteryTransient.section14Report'],
                 modelRequirement='Per-battery and bus transient dynamics, protection state and the observation cadence.'),
            dict(id='battery3_withdrawal',references=['battery3_removed'],
                 modelRequirement='Unequal source sharing dependent on tap, delivered charge and terminal voltage.'),
            dict(id='reserve',references=['jettison_usable','reportedBudget'],
                 modelRequirement='Documented usable versus total charge and consistent source accounting boundary.'),
        ]),
    nextGateRecommendation='Use the new component-current and battery-history report to isolate missing demand and thermal sensitivity. Establish LM-7 applicability, thermostat/jet duty and missing full-mission switch history before assessing the held-out anchors with predeclared uncertainty. Resolve unequal battery sharing, initial history and export accounting before accepting reserve predictions. Full-flight validation remains OPEN.',
    profileAudit=profile,reportedBudget=budget)

assert len({a['id'] for a in anchors})==len(anchors)
assert all(a['source'] in sources for a in anchors + switch_events + cm_transfer['transitions'] + cm_transfer['chargerReadings'])
assert all(hours(t['getWindow'][0])<hours(t['getWindow'][1]) for t in cm_transfer['transitions'] if 'getWindow' in t)
assert all(not (s.get('plotOffScaleHigh') and 'currentMagnitudeA' in s) for s in transient['selectedSamples'])
assert spot_checks['comparisons'][1]['predictedMinusReportedA'] == -12.5
assert spot_checks['comparisons'][2]['outsideReportedRangeA'] == 0.5
assert abs(legacy['predictedRemainingAh']-502.52)<1e-6
assert budget['residualIfCmSubtractedAgainAh']==5.3
output=ROOT/'reference/electrical-flight-audit.json'
output.write_text(json.dumps(audit,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(anchors=len(anchors),switchEvents=len(switch_events),scenarios=len(profile['scenarios']),
    cmTransferTransitions=len(cm_transfer['transitions']),chargerReadings=len(cm_transfer['chargerReadings']),
    transientSamples=len(transient['selectedSamples']),heldOutTargetGroups=len(audit['heldOutTargets']['targets']),
    transferAccountingResolved=False,independentValidationPassed=False,
    legacyResidualAh=legacy['residualAh'],chronologyOnlyResidualAh=early['residualAh'],telmuIllustrativeResidualAh=telmu['residualAh'])))
