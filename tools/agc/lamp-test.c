/* SPDX-License-Identifier: GPL-2.0-or-later
 * Deterministic DSKY peripheral harness for the unmodified Virtual AGC CPU.
 * This is a test fixture, not a spacecraft/environment model or flown padload.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "yaAGC.h"
#include "agc_engine.h"

static agc_t cpu;
static FILE *trace;
static int rows[16];
static int test_active, saw_lamp_frame;
static int hardware_alarms;
static unsigned long long lamp_cycle;
static int lamp_rows[16], lamp_ch11, lamp_ch13, lamp_ch163;

FILE *rfopen(const char *name, const char *mode) { return fopen(name, mode); }
void BacktraceAdd(agc_t *state, int cause) { (void)state; (void)cause; }
int ChannelInput(agc_t *state) { (void)state; return 0; }
void ChannelRoutine(agc_t *state) { (void)state; }
void ShiftToDeda(agc_t *state, int data) { (void)state; (void)data; }
void RequestRadarData(agc_t *state) { (void)state; }

static int all_eights(void) {
    int row;
    for (row = 1; row <= 11; row++) {
        if (row == 8) { if ((rows[row] & 037) != 035) return 0; }
        else if ((rows[row] & 01777) != 01675) return 0;
    }
    return 1;
}

void ChannelOutput(agc_t *state, int channel, int value) {
    /* SocketAPI.c handles the superbank latch outside the CPU core.
     * An embedded peripheral adapter must preserve this hardware behavior. */
    if (channel == 7) {
        state->InputChannel[7] = state->OutputChannel7 = value & 0160;
        return;
    }
    if (channel == 077 && value) hardware_alarms++;
    if (channel == 010) rows[(value >> 11) & 017] = value;
    if (trace && (channel == 010 || channel == 011 || channel == 013 || channel == 0163 || channel == 077))
        fprintf(trace, "%llu,%03o,%05o\n", state->CycleCounter, channel, value);
    if (test_active && !saw_lamp_frame && all_eights()
            && (state->InputChannel[013] & 01000)
            && ((state->InputChannel[011] & 0175) == 0175)) {
        saw_lamp_frame = 1;
        lamp_cycle = state->CycleCounter;
        memcpy(lamp_rows, rows, sizeof(rows));
        lamp_ch11 = state->InputChannel[011];
        lamp_ch13 = state->InputChannel[013];
        lamp_ch163 = state->DskyChannel163;
    }
}

static void step(double seconds) {
    uint64_t end = cpu.CycleCounter + (uint64_t)(seconds * AGC_PER_SECOND);
    while (cpu.CycleCounter < end) agc_engine(&cpu);
}

static void key(int code) {
    WriteIO(&cpu, 015, code);
    cpu.InterruptRequests[5] = 1;
    step(0.25);
}

static void print_rows(int *data) {
    int row;
    printf("[");
    for (row = 0; row < 16; row++) printf("%s%d", row ? "," : "", data[row]);
    printf("]");
}

int main(int argc, char **argv) {
    int result, completed;
    if (argc != 3) { fprintf(stderr, "Usage: lamp-test.exe rope.bin trace.csv\n"); return 2; }
    trace = fopen(argv[2], "w");
    if (!trace) { perror("trace"); return 2; }
    fprintf(trace, "cycle,channel_octal,value_octal\n");
    result = agc_engine_init(&cpu, argv[1], NULL, 0);
    if (result) { fprintf(stderr, "agc_engine_init failed: %d\n", result); fclose(trace); return 2; }
    /* agc_engine_init supplies default channels and zero erasable RAM.
     * No unverified mission padload or hand-entered erasable data is applied. */
    step(3.0);
    /* Select P00 with V37 ENTR 00 ENTR through the actual keyboard interrupt. */
    key(17); key(3); key(7); key(28); key(16); key(16); key(28);
    step(1.0);
    test_active = 1;
    key(17); key(3); key(5); key(28); /* V35 ENTR */
    step(7.0);
    completed = saw_lamp_frame && !(cpu.InputChannel[013] & 01000);
    fclose(trace);
    printf("{\"passed\":%s,\"sawAllEightDigits\":%s,\"testAlarmCleared\":%s,",
        completed ? "true" : "false", saw_lamp_frame ? "true" : "false",
        !(cpu.InputChannel[013] & 01000) ? "true" : "false");
    printf("\"lampFrameCycle\":%llu,\"lampChannel11\":%d,\"lampChannel13\":%d,\"lampChannel163\":%d,\"lampRows\":",
        lamp_cycle, lamp_ch11, lamp_ch13, lamp_ch163);
    print_rows(lamp_rows);
    printf(",\"finalRows\":"); print_rows(rows);
    printf(",\"finalChannel11\":%d,\"finalChannel13\":%d,\"finalChannel163\":%d,\"cycles\":%llu,\"parityFail\":%d,\"hardwareAlarms\":%d}\n",
        cpu.InputChannel[011], cpu.InputChannel[013], cpu.DskyChannel163, cpu.CycleCounter, cpu.ParityFail, hardware_alarms);
    return completed ? 0 : 1;
}
