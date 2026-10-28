################################################################################
# TestAwCalc.4gl - fglunit suite for the pure calculation module AwCalc.
#
# No database, no UI - deterministic functions only.
#
# Build & run (see the top-level Makefile 'test' target):
#   fglcomp -M -o bin tests/TestAwCalc.4gl    (FGLLDPATH = bin:<fglunit pkg>)
#   fglrun bin/TestAwCalc.42m
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL AwCalc

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("AwCalc")

   CALL FglUnit.register("testLineTotalBasic",       FUNCTION testLineTotalBasic)
   CALL FglUnit.register("testLineTotalDiscount",    FUNCTION testLineTotalDiscount)
   CALL FglUnit.register("testLineTotalZeroQty",     FUNCTION testLineTotalZeroQty)
   CALL FglUnit.register("testLineTotalNulls",       FUNCTION testLineTotalNulls)

   CALL FglUnit.register("testOrderTotalBasic",      FUNCTION testOrderTotalBasic)
   CALL FglUnit.register("testOrderTotalNulls",      FUNCTION testOrderTotalNulls)

   CALL FglUnit.register("testStatusLabelKnown",     FUNCTION testStatusLabelKnown)
   CALL FglUnit.register("testStatusLabelBounds",    FUNCTION testStatusLabelBounds)
   CALL FglUnit.register("testStatusLabelUnknown",   FUNCTION testStatusLabelUnknown)

   CALL FglUnit.register("testOrderNumber",          FUNCTION testOrderNumber)
   CALL FglUnit.register("testOrderNumberNull",      FUNCTION testOrderNumberNull)

   EXIT PROGRAM FglUnit.run()
END MAIN

#--- awLineTotal ---------------------------------------------------------------

PUBLIC FUNCTION testLineTotalBasic() RETURNS ()
   # 2 * 10.00 * (1 - 0) = 20.00
   CALL Assertions.assertEqualsDec(20.0, AwCalc.awLineTotal(2, 10.00, 0), 0.0001,
      "2 @ 10.00, no discount")
END FUNCTION

PUBLIC FUNCTION testLineTotalDiscount() RETURNS ()
   # 3 * 100.00 * (1 - 0.10) = 270.00
   CALL Assertions.assertEqualsDec(270.0, AwCalc.awLineTotal(3, 100.00, 0.10), 0.0001,
      "3 @ 100.00, 10% discount")
END FUNCTION

PUBLIC FUNCTION testLineTotalZeroQty() RETURNS ()
   CALL Assertions.assertEqualsDec(0.0, AwCalc.awLineTotal(0, 99.99, 0.25), 0.0001,
      "zero quantity gives zero total")
END FUNCTION

PUBLIC FUNCTION testLineTotalNulls() RETURNS ()
   CALL Assertions.assertEqualsDec(0.0, AwCalc.awLineTotal(NULL, NULL, NULL), 0.0001,
      "NULL inputs are treated as zero")
END FUNCTION

#--- awOrderTotal --------------------------------------------------------------

PUBLIC FUNCTION testOrderTotalBasic() RETURNS ()
   # 100.00 + 8.00 + 5.00 = 113.00
   CALL Assertions.assertEqualsDec(113.0, AwCalc.awOrderTotal(100.00, 8.00, 5.00), 0.0001,
      "subtotal + tax + freight")
END FUNCTION

PUBLIC FUNCTION testOrderTotalNulls() RETURNS ()
   CALL Assertions.assertEqualsDec(50.0, AwCalc.awOrderTotal(50.00, NULL, NULL), 0.0001,
      "NULL tax/freight treated as zero")
END FUNCTION

#--- awStatusLabel -------------------------------------------------------------

PUBLIC FUNCTION testStatusLabelKnown() RETURNS ()
   CALL Assertions.assertEquals("In process", AwCalc.awStatusLabel(1), "status 1")
   CALL Assertions.assertEquals("Shipped",    AwCalc.awStatusLabel(5), "status 5")
END FUNCTION

PUBLIC FUNCTION testStatusLabelBounds() RETURNS ()
   CALL Assertions.assertEquals("Approved",  AwCalc.awStatusLabel(2), "status 2")
   CALL Assertions.assertEquals("Cancelled", AwCalc.awStatusLabel(6), "status 6")
END FUNCTION

PUBLIC FUNCTION testStatusLabelUnknown() RETURNS ()
   # Unknown codes fall through to a "Status N" label.
   CALL Assertions.assertContains(AwCalc.awStatusLabel(99), "99",
      "unknown status code echoes the number")
END FUNCTION

#--- awOrderNumber -------------------------------------------------------------

PUBLIC FUNCTION testOrderNumber() RETURNS ()
   CALL Assertions.assertEquals("SO43659", AwCalc.awOrderNumber(43659), "order number format")
END FUNCTION

PUBLIC FUNCTION testOrderNumberNull() RETURNS ()
   CALL Assertions.assertNull(AwCalc.awOrderNumber(NULL), "NULL id gives NULL order number")
END FUNCTION
