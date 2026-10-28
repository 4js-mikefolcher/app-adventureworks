################################################################################
# TestSpecialOffers.4gl - fglunit suite for the special-offers feature: the
# view-to-database conversion in SpecialOffersController (the JSON bridge, standards
# rule 13) and the business-rule validation in SpecialOffersModel.
#
# The bridge fails silently: a member that does not match, or a DATE going into a
# DATETIME, becomes NULL without an error. So every member that crosses is populated
# and asserted not NULL. No database is needed.
#
# Build & run (see the top-level Makefile 'test' target):
#   fglcomp -M -Wall -Werror -o bin tests/TestSpecialOffers.4gl
#   fglrun bin/TestSpecialOffers.42m
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL SpecialOffersController
IMPORT FGL SpecialOffersModel

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("SpecialOffers")

   CALL FglUnit.register("testToDbOfferCrossesEveryMember", FUNCTION testToDbOfferCrossesEveryMember)
   CALL FglUnit.register("testToDbOfferMapsType",           FUNCTION testToDbOfferMapsType)
   CALL FglUnit.register("testToDbOfferDatesBecomeDatetimes",
      FUNCTION testToDbOfferDatesBecomeDatetimes)
   CALL FglUnit.register("testToDbOfferKeepsNullMaxQty",    FUNCTION testToDbOfferKeepsNullMaxQty)
   CALL FglUnit.register("testToDbOfferNullsOtherColumns",  FUNCTION testToDbOfferNullsOtherColumns)

   CALL FglUnit.register("testDatesAfter",       FUNCTION testDatesAfter)
   CALL FglUnit.register("testDatesEqual",       FUNCTION testDatesEqual)
   CALL FglUnit.register("testDatesBefore",      FUNCTION testDatesBefore)
   CALL FglUnit.register("testDatesOpenEnd",     FUNCTION testDatesOpenEnd)
   CALL FglUnit.register("testDatesNullStart",   FUNCTION testDatesNullStart)

   CALL FglUnit.register("testQuantitiesInRange",   FUNCTION testQuantitiesInRange)
   CALL FglUnit.register("testQuantitiesEqual",     FUNCTION testQuantitiesEqual)
   CALL FglUnit.register("testQuantitiesMaxBelowMin", FUNCTION testQuantitiesMaxBelowMin)
   CALL FglUnit.register("testQuantitiesOpenMax",   FUNCTION testQuantitiesOpenMax)

   EXIT PROGRAM FglUnit.run()
END MAIN

#+ A view record with every member populated.
PRIVATE FUNCTION fullViewRecord() RETURNS SpecialOffersController.tOfferView
   VAR viewRec SpecialOffersController.tOfferView
   LET viewRec.specialOfferId = 5
   LET viewRec.description = "Spring Promo"
   LET viewRec.discountPct = 0.15
   LET viewRec.offerType = "Seasonal Discount"
   LET viewRec.category = "Reseller"
   LET viewRec.startDate = MDY(3, 1, 2024)
   LET viewRec.endDate = MDY(5, 31, 2024)
   LET viewRec.minQty = 11
   LET viewRec.maxQty = 40
   RETURN viewRec
END FUNCTION

#+ A database record holding only the two dates.
PRIVATE FUNCTION offerWithDates(startDate DATE, endDate DATE) RETURNS SpecialOffersModel.tOffer
   VAR rec SpecialOffersModel.tOffer
   LET rec.startdate = startDate
   LET rec.enddate = endDate
   RETURN rec
END FUNCTION

#+ A database record holding only the two quantities.
PRIVATE FUNCTION offerWithQuantities(minQty INTEGER, maxQty INTEGER) RETURNS SpecialOffersModel.tOffer
   VAR rec SpecialOffersModel.tOffer
   LET rec.minqty = minQty
   LET rec.maxqty = maxQty
   RETURN rec
END FUNCTION

#+ TRUE when the model accepts the date range.
PRIVATE FUNCTION datesValid(startDate DATE, endDate DATE) RETURNS BOOLEAN
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SpecialOffersModel.validateOfferDates(offerWithDates(startDate, endDate))
      RETURNING valid, messageText
   RETURN valid
END FUNCTION

#+ TRUE when the model accepts the quantity range.
PRIVATE FUNCTION quantitiesValid(minQty INTEGER, maxQty INTEGER) RETURNS BOOLEAN
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SpecialOffersModel.validateOfferQuantities(offerWithQuantities(minQty, maxQty))
      RETURNING valid, messageText
   RETURN valid
END FUNCTION

#--- toDbOffer -----------------------------------------------------------------

PUBLIC FUNCTION testToDbOfferCrossesEveryMember() RETURNS ()
   VAR dbRec SpecialOffersModel.tOffer
   LET dbRec = SpecialOffersController.toDbOffer(fullViewRecord())
   CALL Assertions.assertNotNull(dbRec.specialofferid, "specialOfferId crosses")
   CALL Assertions.assertNotNull(dbRec.description, "description crosses")
   CALL Assertions.assertNotNull(dbRec.discountpct, "discountPct crosses")
   CALL Assertions.assertNotNull(dbRec.type, "offerType crosses")
   CALL Assertions.assertNotNull(dbRec.category, "category crosses")
   CALL Assertions.assertNotNull(dbRec.startdate, "startDate crosses")
   CALL Assertions.assertNotNull(dbRec.enddate, "endDate crosses")
   CALL Assertions.assertNotNull(dbRec.minqty, "minQty crosses")
   CALL Assertions.assertNotNull(dbRec.maxqty, "maxQty crosses")
   CALL Assertions.assertEqualsInt(5, dbRec.specialofferid, "specialOfferId value")
   CALL Assertions.assertEquals("Spring Promo", dbRec.description, "description value")
   CALL Assertions.assertEqualsDec(0.15, dbRec.discountpct, 0.0001, "discountPct value")
   CALL Assertions.assertEquals("Reseller", dbRec.category, "category value")
   CALL Assertions.assertEqualsInt(11, dbRec.minqty, "minQty value")
   CALL Assertions.assertEqualsInt(40, dbRec.maxqty, "maxQty value")
END FUNCTION

PUBLIC FUNCTION testToDbOfferMapsType() RETURNS ()
   # The view member offerType fills the column "type" through its json_name.
   VAR dbRec SpecialOffersModel.tOffer
   LET dbRec = SpecialOffersController.toDbOffer(fullViewRecord())
   CALL Assertions.assertEquals("Seasonal Discount", dbRec.type, "offerType fills the type column")
END FUNCTION

PUBLIC FUNCTION testToDbOfferDatesBecomeDatetimes() RETURNS ()
   # The bridge turns DATE into DATETIME as NULL, so toDbOffer assigns the dates itself.
   VAR dbRec SpecialOffersModel.tOffer
   VAR expectedStart DATETIME YEAR TO SECOND = MDY(3, 1, 2024)
   VAR expectedEnd DATETIME YEAR TO SECOND = MDY(5, 31, 2024)
   LET dbRec = SpecialOffersController.toDbOffer(fullViewRecord())
   # A NULL date would make the comparisons below NULL, which assertTrue does not fail on.
   CALL Assertions.assertNotNull(dbRec.startdate, "startDate is not lost in the conversion")
   CALL Assertions.assertNotNull(dbRec.enddate, "endDate is not lost in the conversion")
   CALL Assertions.assertTrue(dbRec.startdate = expectedStart, "startDate becomes midnight of the day")
   CALL Assertions.assertTrue(dbRec.enddate = expectedEnd, "endDate becomes midnight of the day")
END FUNCTION

PUBLIC FUNCTION testToDbOfferKeepsNullMaxQty() RETURNS ()
   # An open max quantity (NULL) stays NULL, it is not turned into a value.
   VAR viewRec SpecialOffersController.tOfferView
   VAR dbRec SpecialOffersModel.tOffer
   LET viewRec = fullViewRecord()
   LET viewRec.maxQty = NULL
   LET dbRec = SpecialOffersController.toDbOffer(viewRec)
   CALL Assertions.assertNull(dbRec.maxqty, "NULL maxQty stays NULL")
   CALL Assertions.assertEqualsInt(11, dbRec.minqty, "minQty is unaffected")
END FUNCTION

PUBLIC FUNCTION testToDbOfferNullsOtherColumns() RETURNS ()
   # The bridge replaces the whole target: columns the view does not carry are NULL,
   # which is why the model's INSERT and UPDATE name the columns they write.
   VAR dbRec SpecialOffersModel.tOffer
   LET dbRec = SpecialOffersController.toDbOffer(fullViewRecord())
   CALL Assertions.assertNull(dbRec.rowguid, "rowGuid is not carried by the view")
   CALL Assertions.assertNull(dbRec.modifieddate, "modifiedDate is not carried by the view")
END FUNCTION

#--- validateOfferDates --------------------------------------------------------

PUBLIC FUNCTION testDatesAfter() RETURNS ()
   CALL Assertions.assertTrue(datesValid(MDY(1, 1, 2024), MDY(12, 31, 2024)),
      "end after start is valid")
END FUNCTION

PUBLIC FUNCTION testDatesEqual() RETURNS ()
   CALL Assertions.assertTrue(datesValid(MDY(6, 15, 2024), MDY(6, 15, 2024)),
      "end equal to start is valid")
END FUNCTION

PUBLIC FUNCTION testDatesBefore() RETURNS ()
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SpecialOffersModel.validateOfferDates(offerWithDates(MDY(12, 31, 2024), MDY(1, 1, 2024)))
      RETURNING valid, messageText
   CALL Assertions.assertFalse(valid, "end before start is invalid")
   CALL Assertions.assertContains(messageText, "End date", "the message names the end date")
END FUNCTION

PUBLIC FUNCTION testDatesOpenEnd() RETURNS ()
   CALL Assertions.assertTrue(datesValid(MDY(1, 1, 2024), NULL), "open (NULL) end is valid")
END FUNCTION

PUBLIC FUNCTION testDatesNullStart() RETURNS ()
   CALL Assertions.assertFalse(datesValid(NULL, MDY(1, 1, 2024)),
      "NULL start with a real end is invalid")
END FUNCTION

#--- validateOfferQuantities ---------------------------------------------------

PUBLIC FUNCTION testQuantitiesInRange() RETURNS ()
   CALL Assertions.assertTrue(quantitiesValid(1, 10), "max above min is valid")
END FUNCTION

PUBLIC FUNCTION testQuantitiesEqual() RETURNS ()
   CALL Assertions.assertTrue(quantitiesValid(5, 5), "max equal to min is valid")
END FUNCTION

PUBLIC FUNCTION testQuantitiesMaxBelowMin() RETURNS ()
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SpecialOffersModel.validateOfferQuantities(offerWithQuantities(10, 5))
      RETURNING valid, messageText
   CALL Assertions.assertFalse(valid, "max below min is invalid")
   CALL Assertions.assertContains(messageText, "Max quantity", "the message names the max quantity")
END FUNCTION

PUBLIC FUNCTION testQuantitiesOpenMax() RETURNS ()
   CALL Assertions.assertTrue(quantitiesValid(3, NULL), "open (NULL) max is valid")
END FUNCTION
