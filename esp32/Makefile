# CodeRing ESP32 port — host build of the portable core.
#
#   make test          build and run the suite (this is the one you want)
#   make test NAME=pulse   run only tests whose name contains "pulse"
#   make target-check  compile the same sources for the ESP32-S3 itself
#   make clean
#
# The core has no ESP-IDF dependency on purpose: it builds with nothing but
# a C compiler, so the clinical rules can be tested on the laptop in
# milliseconds without a board attached.

CC      ?= cc
BUILD   := build
NAME    ?=

WARN := -std=c99 -Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes \
        -Wmissing-prototypes -Wvla -Werror
# Address/UB sanitizers on the host: a fixed-capacity C engine is exactly
# where an off-by-one hides, and these turn one into a loud failure.
SAN  := -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
INC  := -Icore/include -Icore/src -Itest

CORE_SRC := $(wildcard core/src/*.c)
TEST_SRC := $(wildcard test/*.c)
HEADERS  := $(wildcard core/include/*.h) $(wildcard core/src/*.h) $(wildcard test/*.h)

.PHONY: test tests spec-coverage parity target-check clean

test: tests spec-coverage
	@./$(BUILD)/cr_tests $(NAME)

tests: $(BUILD)/cr_tests

$(BUILD)/cr_tests: $(CORE_SRC) $(TEST_SRC) $(HEADERS) | $(BUILD)
	$(CC) $(WARN) $(SAN) -g -O1 $(INC) $(CORE_SRC) $(TEST_SRC) -lm -o $@

spec-coverage:
	@sh test/spec_coverage.sh

# Runs one scenario through BOTH engines and diffs the traces — the real
# proof that the behaviour ported. Needs Swift; not part of `make test`.
parity:
	@sh test/parity/run_parity.sh

$(BUILD):
	@mkdir -p $(BUILD)

# Compiles the core with the real cross-compiler: 32-bit ints, different
# size_t, no host libc quirks. Needs ESP-IDF on PATH:
#   . ~/esp/esp-idf/export.sh
XTENSA_CC ?= xtensa-esp32s3-elf-gcc
target-check:
	@command -v $(XTENSA_CC) >/dev/null 2>&1 || { \
	    echo "$(XTENSA_CC) not found — run: . ~/esp/esp-idf/export.sh"; exit 1; }
	@mkdir -p $(BUILD)/xtensa
	@for f in $(CORE_SRC); do \
	    echo "  CC(esp32s3) $$f"; \
	    $(XTENSA_CC) $(WARN) -Os -mlongcalls $(INC) -c $$f \
	        -o $(BUILD)/xtensa/`basename $$f .c`.o || exit 1; \
	done
	@echo "core compiles clean for the ESP32-S3:"
	@xtensa-esp32s3-elf-size -t $(BUILD)/xtensa/*.o | tail -1

clean:
	@rm -rf $(BUILD)
