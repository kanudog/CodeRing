# CodeRing firmware for the Waveshare ESP32-S3-Touch-AMOLED-2.06.
#
#   . ~/esp/esp-idf/export.sh
#   cd esp32/firmware && idf.py build flash monitor
#
# The clinical engine lives in ../core and is pulled in as a component, so
# the SAME sources the host test suite runs are the ones that ship.
cmake_minimum_required(VERSION 3.16)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(codering)
