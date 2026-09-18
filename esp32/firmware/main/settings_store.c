#include "settings_store.h"

#include <string.h>

#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "settings";

#define NAMESPACE  "codering"
#define KEY        "settings"
/// Generous: the whole settings object is a few hundred bytes today, and a
/// key that grows later should still fit without a migration.
#define JSON_MAX   1024

esp_err_t settings_store_init(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        // A partition from another firmware, or one that filled up. Settings
        // are re-creatable; being unable to store them is not worth carrying.
        ESP_LOGW(TAG, "NVS needs erasing (%s) — doing it", esp_err_to_name(err));
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    if (err != ESP_OK) ESP_LOGE(TAG, "NVS init: %s", esp_err_to_name(err));
    return err;
}

cr_settings_t settings_store_load(void)
{
    cr_settings_t settings = cr_settings_default();

    nvs_handle_t handle;
    if (nvs_open(NAMESPACE, NVS_READONLY, &handle) != ESP_OK) {
        ESP_LOGI(TAG, "nothing saved yet — defaults");
        return settings;
    }
    char json[JSON_MAX];
    size_t len = sizeof json;
    const esp_err_t err = nvs_get_str(handle, KEY, json, &len);
    nvs_close(handle);
    if (err != ESP_OK) {
        ESP_LOGI(TAG, "no settings key — defaults");
        return settings;
    }
    // cr_settings_from_json writes defaults for anything missing and reports
    // false only when the whole thing is malformed, which is the same
    // fall-back-whole behaviour CodeStore has on the phone.
    if (!cr_settings_from_json(json, &settings)) {
        ESP_LOGW(TAG, "stored settings did not parse — defaults");
        return cr_settings_default();
    }
    return settings;
}

bool settings_store_save(const cr_settings_t *settings)
{
    if (settings == NULL) return false;
    char json[JSON_MAX];
    const size_t need = cr_settings_to_json(settings, json, sizeof json);
    if (need >= sizeof json) {
        ESP_LOGE(TAG, "settings JSON needs %u bytes", (unsigned)need);
        return false;
    }

    nvs_handle_t handle;
    if (nvs_open(NAMESPACE, NVS_READWRITE, &handle) != ESP_OK) return false;
    esp_err_t err = nvs_set_str(handle, KEY, json);
    if (err == ESP_OK) err = nvs_commit(handle);
    nvs_close(handle);
    if (err != ESP_OK) { ESP_LOGE(TAG, "save: %s", esp_err_to_name(err)); return false; }
    ESP_LOGI(TAG, "saved (%u bytes)", (unsigned)need);
    return true;
}
