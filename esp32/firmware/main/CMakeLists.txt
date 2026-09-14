# The wall clock needs a starting point. There is no RTC wired up yet (M5),
# so the build stamps in the Mac's local time and the device counts up from
# there — right to the second when flashed, and never drifting afterwards
# because esp_timer is the same clock the engine uses.
execute_process(COMMAND date +%s OUTPUT_VARIABLE BUILD_EPOCH OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND date +%z OUTPUT_VARIABLE BUILD_TZ OUTPUT_STRIP_TRAILING_WHITESPACE)
string(SUBSTRING "${BUILD_TZ}" 0 1 TZ_SIGN)
string(SUBSTRING "${BUILD_TZ}" 1 2 TZ_HOURS)
string(SUBSTRING "${BUILD_TZ}" 3 2 TZ_MINUTES)
math(EXPR TZ_SECONDS "${TZ_HOURS} * 3600 + ${TZ_MINUTES} * 60")
if(TZ_SIGN STREQUAL "-")
    math(EXPR TZ_SECONDS "0 - ${TZ_SECONDS}")
endif()
math(EXPR BUILD_LOCAL_EPOCH "${BUILD_EPOCH} + ${TZ_SECONDS}")

# The icon set is generated (tools/make_icons.sh) — one .c per icon, plus
# the name → image lookup in cr_icons.c.
file(GLOB ICON_SRCS ${CMAKE_CURRENT_LIST_DIR}/icons/*.c)

idf_component_register(
    SRCS "main.c" "ui_probe.c" "ui_screen.c" "ui_flow.c"
         "fonts/cr_font_16.c" "fonts/cr_font_28.c" "fonts/cr_font_48.c"
         ${ICON_SRCS}
    INCLUDE_DIRS "." "fonts" "icons"
    REQUIRES codering_core
    PRIV_REQUIRES esp_timer esp_driver_gpio
)

target_compile_definitions(${COMPONENT_LIB} PRIVATE CR_BUILD_LOCAL_EPOCH=${BUILD_LOCAL_EPOCH})
