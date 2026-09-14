# Wraps esp32/core as an ESP-IDF component. One copy of the engine: the
# host tests and the firmware compile the very same .c files, so a rule can
# never be green on the laptop and different on the wrist.
set(CORE_DIR ${CMAKE_CURRENT_LIST_DIR}/../../../core)
file(GLOB CORE_SRCS ${CORE_DIR}/src/*.c)

idf_component_register(
    SRCS ${CORE_SRCS}
    INCLUDE_DIRS ${CORE_DIR}/include
    PRIV_INCLUDE_DIRS ${CORE_DIR}/src
)
