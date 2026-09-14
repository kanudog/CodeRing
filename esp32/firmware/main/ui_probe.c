#include "ui_probe.h"

#include <math.h>
#include <stdio.h>

#include "esp_log.h"

static const char *TAG = "probe";

/// Intent, recorded next to the object it belongs to. Small and fixed: the
/// live screen has ~30 controls and a fan adds 8 more.
#define MAX_EXPECTED 64
static struct { const lv_obj_t *obj; float x, y; } expected[MAX_EXPECTED];
static size_t expected_count;
static int drifted;

void cr_probe_expect(lv_obj_t *obj, float x, float y)
{
    if (expected_count >= MAX_EXPECTED) return;
    expected[expected_count].obj = obj;
    expected[expected_count].x = x;
    expected[expected_count].y = y;
    expected_count++;
}

static bool expectation_for(const lv_obj_t *obj, float *x, float *y)
{
    for (size_t i = 0; i < expected_count; i++) {
        if (expected[i].obj != obj) continue;
        *x = expected[i].x;
        *y = expected[i].y;
        return true;
    }
    return false;
}

void cr_probe_name(lv_obj_t *obj, const char *name)
{
    lv_obj_set_user_data(obj, (void *)name);
}

static void dump_obj(lv_obj_t *obj, int depth)
{
    lv_area_t area;
    lv_obj_get_coords(obj, &area);
    const char *name = lv_obj_get_user_data(obj);
    int32_t w = lv_area_get_width(&area);
    int32_t h = lv_area_get_height(&area);
    const float cx = (float)area.x1 + (float)w / 2.0f;
    const float cy = (float)area.y1 + (float)h / 2.0f;

    float want_x = 0, want_y = 0;
    char drift[48] = "";
    if (expectation_for(obj, &want_x, &want_y)) {
        const float dx = cx - want_x, dy = cy - want_y;
        const bool off = fabsf(dx) > 1.0f || fabsf(dy) > 1.0f;
        snprintf(drift, sizeof drift, "  want=(%.1f,%.1f) d=(%+.1f,%+.1f)%s",
                 (double)want_x, (double)want_y, (double)dx, (double)dy, off ? "  DRIFT" : "");
        if (off) drifted++;
    }
    // Centres, because the layout table is written as centres — that is how
    // a radial layout is authored and how it has to be checked.
    ESP_LOGI(TAG, "%*s%-16s x=%4d y=%4d w=%4d h=%4d  centre=(%4d,%4d)%s",
             depth * 2, "", name ? name : "(obj)",
             (int)area.x1, (int)area.y1, (int)w, (int)h, (int)cx, (int)cy, drift);

    uint32_t count = lv_obj_get_child_count(obj);
    for (uint32_t i = 0; i < count; i++) {
        dump_obj(lv_obj_get_child(obj, i), depth + 1);
    }
}

int cr_probe_dump(lv_obj_t *root, const char *title)
{
    drifted = 0;
    // LVGL defers layout to the next refresh, so without this every object
    // reports 0×0 at (0,0) — a measurement tool that lies is worse than none.
    lv_obj_update_layout(root);
    lv_display_t *disp = lv_obj_get_display(root);
    ESP_LOGI(TAG, "==== %s — panel %dx%d ====", title,
             (int)lv_display_get_horizontal_resolution(disp),
             (int)lv_display_get_vertical_resolution(disp));
    dump_obj(root, 0);
    if (drifted == 0) {
        ESP_LOGI(TAG, "==== %d controls, every one within a pixel of the table ====",
                 (int)expected_count);
    } else {
        ESP_LOGE(TAG, "==== %d of %d controls DRIFTED from the layout table ====",
                 drifted, (int)expected_count);
    }
    return drifted;
}

static void touch_timer_cb(lv_timer_t *timer)
{
    lv_indev_t *indev = lv_timer_get_user_data(timer);
    static bool was_pressed;
    lv_point_t point;
    lv_indev_get_point(indev, &point);
    bool pressed = lv_indev_get_state(indev) == LV_INDEV_STATE_PRESSED;

    if (pressed && !was_pressed) {
        ESP_LOGI(TAG, "touch  DOWN at (%d, %d)", (int)point.x, (int)point.y);
    } else if (!pressed && was_pressed) {
        ESP_LOGI(TAG, "touch  UP   at (%d, %d)", (int)point.x, (int)point.y);
    }
    was_pressed = pressed;
}

void cr_probe_watch_touches(lv_indev_t *indev)
{
    if (indev == NULL) {
        ESP_LOGW(TAG, "no input device — touch is not initialised");
        return;
    }
    // Polled rather than event-based on purpose: an event callback only
    // fires where a widget accepts the touch, and the whole point is to see
    // raw coordinates anywhere on the panel, including dead space.
    lv_timer_create(touch_timer_cb, 20, indev);
}
