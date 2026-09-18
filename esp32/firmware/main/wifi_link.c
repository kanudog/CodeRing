#include "wifi_link.h"

#include <string.h>

#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"

#include "cr_snapshot.h"

static const char *TAG = "wifi";

/// The network the trauma-bay display joins. Fixed rather than configurable:
/// the display is set up once and must find the watch without anyone typing
/// anything in a resus bay.
#define AP_SSID      "codering-tv"
#define AP_PASS      "codering2026"      // WPA2 needs 8+ characters
#define AP_CHANNEL   6
#define AP_MAX_CONN  4

/// The page, linked straight into the binary from esp32/tv/index.html — the
/// same bytes `make preview` serves, so there is one file, not a copy that
/// drifts.
extern const uint8_t tv_html_start[] asm("_binary_index_html_start");
extern const uint8_t tv_html_end[]   asm("_binary_index_html_end");

static cr_engine_t *engine;
static cr_ms_t (*clock_ms)(void);
static httpd_handle_t server;
static bool running;
static int clients;

/// A snapshot is a few kB with a full log. Static rather than on the stack:
/// httpd's task does not have room for this, and a stack overflow inside a
/// web server is a reboot in the middle of a code.
static char snapshot_buf[24 * 1024];

static esp_err_t page_handler(httpd_req_t *req)
{
    httpd_resp_set_type(req, "text/html; charset=utf-8");
    // No caching: the page is tiny and served over a link with nothing else on
    // it, and a stale display during a code is the failure this must not have.
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, (const char *)tv_html_start,
                           (ssize_t)(tv_html_end - tv_html_start));
}

static esp_err_t snapshot_handler(httpd_req_t *req)
{
    const size_t need = cr_snapshot_json(engine, clock_ms(), 0,
                                         snapshot_buf, sizeof snapshot_buf);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    if (need >= sizeof snapshot_buf) {
        // Truncated JSON is not JSON. Say so with a status rather than sending
        // bytes the page would choke on.
        ESP_LOGE(TAG, "snapshot needs %u bytes", (unsigned)need);
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "snapshot too large");
        return ESP_FAIL;
    }
    return httpd_resp_send(req, snapshot_buf, (ssize_t)need);
}

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void)arg; (void)base; (void)data;
    if (id == WIFI_EVENT_AP_STACONNECTED) {
        clients++;
        ESP_LOGI(TAG, "a display joined (%d connected)", clients);
    } else if (id == WIFI_EVENT_AP_STADISCONNECTED) {
        if (clients > 0) clients--;
        ESP_LOGI(TAG, "a display left (%d connected)", clients);
    }
}

esp_err_t wifi_link_start(cr_engine_t *e, cr_ms_t (*clock)(void))
{
    if (running) return ESP_OK;
    engine = e;
    clock_ms = clock;

    // NOT ESP_ERROR_CHECK, anywhere in here. That aborts, and an abort is a
    // reboot: turning the TV link on must never be able to end a running code.
    // Every step below either succeeds, is already done, or leaves the AP off
    // with the rest of the device untouched.
    esp_err_t err = esp_netif_init();
    if (err != ESP_OK) { ESP_LOGE(TAG, "netif: %s", esp_err_to_name(err)); return err; }

    // ESP_ERR_INVALID_STATE here means someone else already created the loop,
    // which is fine — it is a shared, process-wide thing.
    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "event loop: %s", esp_err_to_name(err));
        return err;
    }
    static esp_netif_t *ap_netif;
    if (ap_netif == NULL) ap_netif = esp_netif_create_default_wifi_ap();

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    err = esp_wifi_init(&init);
    if (err != ESP_OK && err != ESP_ERR_WIFI_INIT_STATE) {
        ESP_LOGE(TAG, "wifi init: %s", esp_err_to_name(err));
        return err;
    }
    err = esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                              on_wifi_event, NULL, NULL);
    if (err != ESP_OK) ESP_LOGW(TAG, "event handler: %s", esp_err_to_name(err));

    wifi_config_t ap = { 0 };
    memcpy(ap.ap.ssid, AP_SSID, strlen(AP_SSID));
    ap.ap.ssid_len = strlen(AP_SSID);
    memcpy(ap.ap.password, AP_PASS, strlen(AP_PASS));
    ap.ap.channel = AP_CHANNEL;
    ap.ap.max_connection = AP_MAX_CONN;
    ap.ap.authmode = WIFI_AUTH_WPA2_PSK;

    if ((err = esp_wifi_set_mode(WIFI_MODE_AP)) != ESP_OK ||
        (err = esp_wifi_set_config(WIFI_IF_AP, &ap)) != ESP_OK ||
        (err = esp_wifi_start()) != ESP_OK) {
        ESP_LOGE(TAG, "AP would not start: %s", esp_err_to_name(err));
        esp_wifi_stop();
        return err;
    }
    // The radio costs battery on a wrist device, so it runs at the lowest
    // power that still reaches a TV across a room rather than at maximum.
    esp_wifi_set_max_tx_power(52);      // 13 dBm

    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.stack_size = 6144;
    config.lru_purge_enable = true;
    if (httpd_start(&server, &config) != ESP_OK) {
        ESP_LOGE(TAG, "http server would not start");
        esp_wifi_stop();
        return ESP_FAIL;
    }
    const httpd_uri_t page = { .uri = "/", .method = HTTP_GET, .handler = page_handler };
    const httpd_uri_t snap = { .uri = "/api/snapshot", .method = HTTP_GET,
                               .handler = snapshot_handler };
    httpd_register_uri_handler(server, &page);
    httpd_register_uri_handler(server, &snap);

    running = true;
    ESP_LOGI(TAG, "up — SSID \"%s\", the display opens http://192.168.4.1/", AP_SSID);
    return ESP_OK;
}

void wifi_link_stop(void)
{
    if (!running) return;
    if (server != NULL) { httpd_stop(server); server = NULL; }
    esp_wifi_stop();
    running = false;
    clients = 0;
    ESP_LOGI(TAG, "down");
}

bool wifi_link_running(void) { return running; }
int wifi_link_clients(void) { return clients; }
