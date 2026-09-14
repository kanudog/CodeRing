idf_component_register(
    SRCS "main.c" "ui_probe.c"
         "fonts/cr_font_16.c" "fonts/cr_font_28.c" "fonts/cr_font_48.c"
    INCLUDE_DIRS "." "fonts"
    REQUIRES codering_core
    PRIV_REQUIRES esp_timer esp_driver_gpio
)
