################################################################################
# test_aw_calc.4gl - fglunit suite for the pure calculation module aw_calc.
#
# No database, no UI - deterministic functions only.
#
# Build & run (see the top-level Makefile 'test' target):
#   fglcomp -M -o bin tests/test_aw_calc.4gl    (FGLLDPATH = bin:<fglunit pkg>)
#   fglrun bin/test_aw_calc.42m
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL aw_calc

MAIN
    CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
    CALL FglUnit.suite("aw_calc")

    CALL FglUnit.register("test_line_total_basic",        FUNCTION test_line_total_basic)
    CALL FglUnit.register("test_line_total_discount",     FUNCTION test_line_total_discount)
    CALL FglUnit.register("test_line_total_zero_qty",     FUNCTION test_line_total_zero_qty)
    CALL FglUnit.register("test_line_total_nulls",        FUNCTION test_line_total_nulls)

    CALL FglUnit.register("test_order_total_basic",       FUNCTION test_order_total_basic)
    CALL FglUnit.register("test_order_total_nulls",       FUNCTION test_order_total_nulls)

    CALL FglUnit.register("test_status_label_known",      FUNCTION test_status_label_known)
    CALL FglUnit.register("test_status_label_bounds",     FUNCTION test_status_label_bounds)
    CALL FglUnit.register("test_status_label_unknown",    FUNCTION test_status_label_unknown)

    CALL FglUnit.register("test_order_number",            FUNCTION test_order_number)
    CALL FglUnit.register("test_order_number_null",       FUNCTION test_order_number_null)

    CALL FglUnit.register("test_date_range_after",        FUNCTION test_date_range_after)
    CALL FglUnit.register("test_date_range_equal",        FUNCTION test_date_range_equal)
    CALL FglUnit.register("test_date_range_before",       FUNCTION test_date_range_before)
    CALL FglUnit.register("test_date_range_open_end",     FUNCTION test_date_range_open_end)
    CALL FglUnit.register("test_date_range_null_start",   FUNCTION test_date_range_null_start)

    EXIT PROGRAM FglUnit.run()
END MAIN

#--- aw_line_total -------------------------------------------------------------

PUBLIC FUNCTION test_line_total_basic()
    # 2 * 10.00 * (1 - 0) = 20.00
    CALL Assertions.assertEqualsDec(20.0, aw_calc.aw_line_total(2, 10.00, 0), 0.0001,
        "2 @ 10.00, no discount")
END FUNCTION

PUBLIC FUNCTION test_line_total_discount()
    # 3 * 100.00 * (1 - 0.10) = 270.00
    CALL Assertions.assertEqualsDec(270.0, aw_calc.aw_line_total(3, 100.00, 0.10), 0.0001,
        "3 @ 100.00, 10% discount")
END FUNCTION

PUBLIC FUNCTION test_line_total_zero_qty()
    CALL Assertions.assertEqualsDec(0.0, aw_calc.aw_line_total(0, 99.99, 0.25), 0.0001,
        "zero quantity gives zero total")
END FUNCTION

PUBLIC FUNCTION test_line_total_nulls()
    CALL Assertions.assertEqualsDec(0.0, aw_calc.aw_line_total(NULL, NULL, NULL), 0.0001,
        "NULL inputs are treated as zero")
END FUNCTION

#--- aw_order_total ------------------------------------------------------------

PUBLIC FUNCTION test_order_total_basic()
    # 100.00 + 8.00 + 5.00 = 113.00
    CALL Assertions.assertEqualsDec(113.0, aw_calc.aw_order_total(100.00, 8.00, 5.00), 0.0001,
        "subtotal + tax + freight")
END FUNCTION

PUBLIC FUNCTION test_order_total_nulls()
    CALL Assertions.assertEqualsDec(50.0, aw_calc.aw_order_total(50.00, NULL, NULL), 0.0001,
        "NULL tax/freight treated as zero")
END FUNCTION

#--- aw_status_label -----------------------------------------------------------

PUBLIC FUNCTION test_status_label_known()
    CALL Assertions.assertEquals("In process", aw_calc.aw_status_label(1), "status 1")
    CALL Assertions.assertEquals("Shipped",    aw_calc.aw_status_label(5), "status 5")
END FUNCTION

PUBLIC FUNCTION test_status_label_bounds()
    CALL Assertions.assertEquals("Approved",  aw_calc.aw_status_label(2), "status 2")
    CALL Assertions.assertEquals("Cancelled", aw_calc.aw_status_label(6), "status 6")
END FUNCTION

PUBLIC FUNCTION test_status_label_unknown()
    # Unknown codes fall through to a "Status N" label.
    CALL Assertions.assertContains(aw_calc.aw_status_label(99), "99",
        "unknown status code echoes the number")
END FUNCTION

#--- aw_order_number -----------------------------------------------------------

PUBLIC FUNCTION test_order_number()
    CALL Assertions.assertEquals("SO43659", aw_calc.aw_order_number(43659), "order number format")
END FUNCTION

PUBLIC FUNCTION test_order_number_null()
    CALL Assertions.assertNull(aw_calc.aw_order_number(NULL), "NULL id gives NULL order number")
END FUNCTION

#--- aw_valid_date_range -------------------------------------------------------

PUBLIC FUNCTION test_date_range_after()
    CALL Assertions.assertTrue(aw_calc.aw_valid_date_range(MDY(1,1,2024), MDY(12,31,2024)),
        "end after start is valid")
END FUNCTION

PUBLIC FUNCTION test_date_range_equal()
    CALL Assertions.assertTrue(aw_calc.aw_valid_date_range(MDY(6,15,2024), MDY(6,15,2024)),
        "end equal to start is valid")
END FUNCTION

PUBLIC FUNCTION test_date_range_before()
    CALL Assertions.assertFalse(aw_calc.aw_valid_date_range(MDY(12,31,2024), MDY(1,1,2024)),
        "end before start is invalid")
END FUNCTION

PUBLIC FUNCTION test_date_range_open_end()
    CALL Assertions.assertTrue(aw_calc.aw_valid_date_range(MDY(1,1,2024), NULL),
        "open (NULL) end is valid")
END FUNCTION

PUBLIC FUNCTION test_date_range_null_start()
    CALL Assertions.assertFalse(aw_calc.aw_valid_date_range(NULL, MDY(1,1,2024)),
        "NULL start with a real end is invalid")
END FUNCTION
