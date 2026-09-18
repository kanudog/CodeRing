#include "cr_audio.h"

#include <math.h>
#include <string.h>

#include "bsp/esp32_s3_touch_amoled_2_06.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

static const char *TAG = "audio";

#define SAMPLE_RATE   22050
#define MAX_TONE_MS   400
#define MAX_SAMPLES   (SAMPLE_RATE * MAX_TONE_MS / 1000)
/// Short: a backlog of ticks is worse than a dropped one, because the beat
/// they belonged to has already passed.
#define QUEUE_DEPTH   4

/// A queued sound: either a bare tone, or a rhythm the task expands. Expanding
/// it there rather than at the call site is what keeps the gaps accurate —
/// the caller is usually the UI task and must not sit in a delay loop.
typedef struct {
    double hz;
    int ms;
    int repeats;        // 1 for a plain tone
    int gap_ms;
} tone_t;

static esp_codec_dev_handle_t speaker;
static QueueHandle_t queue;
static volatile bool muted;

/// The tone, rendered once per request. In PSRAM: 17 kB of internal RAM for a
/// scratch buffer is 17 kB the display cannot use to flush, and this is
/// written by the CPU and handed to I2S, never DMA'd from directly.
EXT_RAM_BSS_ATTR static int16_t samples[MAX_SAMPLES];

/// A tick, not a beep. A square edge at the start and end of a tone is a
/// click, and a metronome that clicks is an irritation rather than a beat, so
/// the amplitude ramps up and back down.
static size_t render(double hz, int ms, int16_t *out, size_t cap)
{
    if (ms > MAX_TONE_MS) ms = MAX_TONE_MS;
    size_t n = (size_t)((int64_t)SAMPLE_RATE * ms / 1000);
    if (n > cap) n = cap;

    const size_t attack = n / 12;                 // ~8% rise
    const double step = 2.0 * M_PI * hz / SAMPLE_RATE;
    for (size_t i = 0; i < n; i++) {
        double env;
        if (i < attack) {
            env = (double)i / (double)attack;
        } else {
            // Decay across the remainder, squared so it fades like something
            // struck rather than switched off.
            const double t = (double)(i - attack) / (double)(n - attack);
            env = (1.0 - t) * (1.0 - t);
        }
        out[i] = (int16_t)(sin(step * (double)i) * env * 12000.0);
    }
    return n;
}

static void audio_task(void *arg)
{
    (void)arg;
    tone_t tone;
    for (;;) {
        if (xQueueReceive(queue, &tone, portMAX_DELAY) != pdTRUE) continue;
        if (muted || speaker == NULL) continue;

        const size_t n = render(tone.hz, tone.ms, samples, MAX_SAMPLES);
        for (int r = 0; r < tone.repeats; r++) {
            if (muted) break;
            // Blocks for the length of the sound — which is exactly why this
            // is not the UI task.
            esp_codec_dev_write(speaker, samples, (int)(n * sizeof samples[0]));
            if (r + 1 < tone.repeats && tone.gap_ms > 0) {
                vTaskDelay(pdMS_TO_TICKS(tone.gap_ms));
            }
        }
    }
}

esp_err_t cr_audio_init(void)
{
    if (speaker != NULL) return ESP_OK;

    speaker = bsp_audio_codec_speaker_init();
    if (speaker == NULL) {
        ESP_LOGE(TAG, "no codec — the board will run silent");
        return ESP_FAIL;
    }
    esp_codec_dev_sample_info_t fs = {
        .sample_rate = SAMPLE_RATE,
        .channel = 1,
        .bits_per_sample = 16,
    };
    // Opened once and left open. Opening per tick pops audibly, and a
    // metronome that pops on every beat is worse than no metronome.
    esp_err_t err = esp_codec_dev_open(speaker, &fs);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "codec open: %d", (int)err);
        speaker = NULL;
        return ESP_FAIL;
    }
    esp_codec_dev_set_out_vol(speaker, 70);

    queue = xQueueCreate(QUEUE_DEPTH, sizeof(tone_t));
    if (queue == NULL) { ESP_LOGE(TAG, "no queue"); return ESP_FAIL; }
    // Priority 4: above idle work, below the display. Pinned to core 1 so it
    // cannot compete with LVGL, which the BSP runs on core 0.
    if (xTaskCreatePinnedToCore(audio_task, "cr_audio", 4096, NULL, 4, NULL, 1) != pdPASS) {
        ESP_LOGE(TAG, "no task");
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "up — ES8311, %d Hz mono", SAMPLE_RATE);
    return ESP_OK;
}

bool cr_audio_ready(void) { return speaker != NULL && queue != NULL; }

void cr_audio_cue(cr_cue_pattern_t pattern, double hz)
{
    if (!cr_audio_ready() || muted) return;
    // Short and quick for the counted rhythms so three ticks still read as one
    // alert rather than three; LONG is a single held note, which is the most
    // different thing a single voice can say.
    tone_t tone = { hz, 90, 1, 0 };
    switch (pattern) {
    case CR_CUE_SINGLE: break;
    case CR_CUE_DOUBLE: tone.ms = 70; tone.repeats = 2; tone.gap_ms = 90;  break;
    case CR_CUE_TRIPLE: tone.ms = 60; tone.repeats = 3; tone.gap_ms = 80;  break;
    case CR_CUE_LONG:   tone.ms = 320; break;
    }
    xQueueSend(queue, &tone, 0);
}

void cr_audio_tone(double hz, int ms)
{
    if (!cr_audio_ready() || muted) return;
    const tone_t tone = { hz, ms, 1, 0 };
    // Never blocks: a full queue means ticks are arriving faster than they can
    // be played, and the right answer is to drop this one.
    xQueueSend(queue, &tone, 0);
}

void cr_audio_set_muted(bool m) { muted = m; }
bool cr_audio_muted(void) { return muted; }
