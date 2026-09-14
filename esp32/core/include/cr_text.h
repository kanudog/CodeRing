// cr_text.h — the small formatters every timer surface shares
// (crClock / crClockSigned / crOffset / crChipAbbreviation /
// DoseCalculator.trim in Swift).
//
// All of them write into caller buffers and always NUL-terminate. Nothing
// here allocates, so a code can run for hours without heap churn.

#ifndef CR_TEXT_H
#define CR_TEXT_H

#include <stddef.h>
#include <stdint.h>

#include "cr_time.h"

/// Copies at most cap-1 bytes without splitting a UTF-8 sequence, so a
/// truncated "CaCl₂" never ends in half a subscript. NULL src copies "".
/// Returns the number of bytes copied.
size_t cr_copy_utf8(char *dst, size_t cap, const char *src);

/// "m:ss", floored; negatives clamp to "0:00" (crClock).
void cr_format_clock(char *buf, size_t cap, cr_ms_t interval);

/// "-m:ss" once overdue, truncated toward zero (crClockSigned), so a timer
/// can count up past its deadline instead of sticking at zero.
void cr_format_clock_signed(char *buf, size_t cap, cr_ms_t interval);

/// "+m:ss" event-log stamp (crOffset).
void cr_format_offset(char *buf, size_t cap, int32_t seconds);

/// 0.80 → "0.8", 16.0 → "16", 0.08 → "0.08" (DoseCalculator.trim).
void cr_format_trim(char *buf, size_t cap, double value);

/// Gutter-chip shorthand: known clinical abbreviations first ("EPI"), then
/// short first words said whole ("BLOOD"), else the first three letters.
/// Swift's unused `key:` parameter is dropped. Case-folding is ASCII-only,
/// which covers every built-in name.
void cr_chip_abbreviation(char *buf, size_t cap, const char *title);

#endif
