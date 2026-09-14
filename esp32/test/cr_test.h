// cr_test.h — a test harness small enough to read in one sitting.
//
// Test names mirror the Swift ones ("SessionEngineTests.testPulseFound…")
// because spec_coverage.sh cross-checks them against
// CodeCore/Tests/CodeCoreTests.swift: a rule that exists there has to exist
// here or be listed in deferred_swift_tests.txt with a reason. Tests that
// only make sense on this board are named "Port.…".

#ifndef CR_TEST_H
#define CR_TEST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef void (*cr_test_fn)(void);

typedef struct {
    const char *name;
    cr_test_fn fn;
} cr_test_case_t;

typedef struct {
    const char *label;
    const cr_test_case_t *cases;
    size_t count;
} cr_test_group_t;

void cr_check(bool ok, const char *file, int line, const char *expr);
void cr_check_i64(int64_t got, int64_t want, const char *file, int line, const char *expr);
void cr_check_near(double got, double want, double eps, const char *file, int line, const char *expr);
void cr_check_str(const char *got, const char *want, const char *file, int line, const char *expr);
void cr_check_contains(const char *haystack, const char *needle, const char *file, int line, const char *expr);

#define CHECK(cond)              cr_check((cond), __FILE__, __LINE__, #cond)
#define CHECK_I(got, want)       cr_check_i64((int64_t)(got), (int64_t)(want), __FILE__, __LINE__, #got)
#define CHECK_NEAR(got, want, e) cr_check_near((got), (want), (e), __FILE__, __LINE__, #got)
#define CHECK_STR(got, want)     cr_check_str((got), (want), __FILE__, __LINE__, #got)
#define CHECK_HAS(hay, needle)   cr_check_contains((hay), (needle), __FILE__, __LINE__, #needle)

// Every group in the suite.
extern const cr_test_case_t cr_dose_tests[];
extern const size_t cr_dose_test_count;
extern const cr_test_case_t cr_weight_tests[];
extern const size_t cr_weight_test_count;
extern const cr_test_case_t cr_engine_tests[];
extern const size_t cr_engine_test_count;
extern const cr_test_case_t cr_undo_tests[];
extern const size_t cr_undo_test_count;
extern const cr_test_case_t cr_settings_tests[];
extern const size_t cr_settings_test_count;
extern const cr_test_case_t cr_snapshot_tests[];
extern const size_t cr_snapshot_test_count;
extern const cr_test_case_t cr_port_tests[];
extern const size_t cr_port_test_count;

#endif
