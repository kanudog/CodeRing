#include "cr_test.h"

#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures_in_test;
static int total_failures;
static int total_checks;

static void report(const char *file, int line, const char *expr, const char *detail)
{
    const char *base = strrchr(file, '/');
    printf("      %s:%d  %s\n            %s\n", base ? base + 1 : file, line, expr, detail);
    failures_in_test++;
    total_failures++;
}

void cr_check(bool ok, const char *file, int line, const char *expr)
{
    total_checks++;
    if (!ok) report(file, line, expr, "expected true");
}

void cr_check_i64(int64_t got, int64_t want, const char *file, int line, const char *expr)
{
    total_checks++;
    if (got == want) return;
    char detail[128];
    snprintf(detail, sizeof detail, "got %" PRId64 ", want %" PRId64, got, want);
    report(file, line, expr, detail);
}

void cr_check_near(double got, double want, double eps, const char *file, int line, const char *expr)
{
    total_checks++;
    if (fabs(got - want) <= eps) return;
    char detail[128];
    snprintf(detail, sizeof detail, "got %g, want %g (±%g)", got, want, eps);
    report(file, line, expr, detail);
}

void cr_check_str(const char *got, const char *want, const char *file, int line, const char *expr)
{
    total_checks++;
    if (got != NULL && want != NULL && strcmp(got, want) == 0) return;
    char detail[256];
    snprintf(detail, sizeof detail, "got \"%s\", want \"%s\"", got ? got : "(null)", want ? want : "(null)");
    report(file, line, expr, detail);
}

void cr_check_contains(const char *haystack, const char *needle, const char *file, int line, const char *expr)
{
    total_checks++;
    if (haystack != NULL && needle != NULL && strstr(haystack, needle) != NULL) return;
    char detail[256];
    snprintf(detail, sizeof detail, "\"%.160s\" does not contain \"%s\"",
             haystack ? haystack : "(null)", needle ? needle : "(null)");
    report(file, line, expr, detail);
}

int main(int argc, char **argv)
{
    const cr_test_group_t groups[] = {
        { "dose",     cr_dose_tests,     cr_dose_test_count },
        { "weight",   cr_weight_tests,   cr_weight_test_count },
        { "engine",   cr_engine_tests,   cr_engine_test_count },
        { "undo",     cr_undo_tests,     cr_undo_test_count },
        { "settings", cr_settings_tests, cr_settings_test_count },
        { "snapshot", cr_snapshot_tests, cr_snapshot_test_count },
        { "layout",   cr_layout_tests,   cr_layout_test_count },
        { "clock",    cr_clock_tests,    cr_clock_test_count },
        { "menu",     cr_menu_tests,     cr_menu_test_count },
        { "port",     cr_port_tests,     cr_port_test_count },
    };
    // `make test NAME=rosc` runs just the tests whose name contains "rosc".
    const char *filter = (argc > 1) ? argv[1] : NULL;

    int ran = 0, failed_tests = 0;
    for (size_t g = 0; g < sizeof groups / sizeof groups[0]; g++) {
        for (size_t i = 0; i < groups[g].count; i++) {
            const cr_test_case_t *test = &groups[g].cases[i];
            if (filter != NULL && strstr(test->name, filter) == NULL) continue;
            failures_in_test = 0;
            ran++;
            printf("  %-62s", test->name);
            fflush(stdout);
            test->fn();
            if (failures_in_test == 0) {
                printf("ok\n");
            } else {
                printf("FAIL\n");
                failed_tests++;
            }
        }
    }

    printf("\n%d tests, %d checks, %d failures\n", ran, total_checks, total_failures);
    if (ran == 0) {
        printf("no tests matched — check the filter\n");
        return 1;
    }
    return failed_tests == 0 ? 0 : 1;
}
