################################################################################
# CustomersModel.4gl - data model for customers (customer).
#
# A customer is either an individual (joined to person via personid) or a store
# (joined to store via storeid); the base table holds only ids. The only editable
# attribute is the territory assignment. Add is not offered: a customer must
# reference an existing person or store, which is outside the Sales scope. Owns the
# database record and the data changes (update, delete), each in its own transaction.
# No UI: results go back to the controller as return values.
################################################################################

IMPORT FGL SqlHelper

SCHEMA adventureworks

#+ The database record: one row of customer, as the model reads and writes it.
PUBLIC TYPE tCustomer RECORD LIKE customer.*

#-------------------------------------------------------------------------------
#+ Update a customer's territory assignment (NULL clears it). The statement names its
#+ columns, so the rest of the record is never written.
#+
#+ @param rec the customer to update, identified by its customer id
#+ @return TRUE, or FALSE with the error text
#-------------------------------------------------------------------------------
PUBLIC FUNCTION updateCustomer(rec tCustomer) RETURNS (BOOLEAN, STRING)
   VAR messageText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND
   BEGIN WORK
   TRY
      UPDATE customer
         SET territoryid = rec.territoryid, modifieddate = modifiedAt
         WHERE customer.customerid = rec.customerid
      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Updating customer territory")
      ROLLBACK WORK
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a customer. One that orders still reference cannot be removed; that comes
#+ back as a friendly message, any other SQL error as the error text.
#+
#+ @param customerId the customer to delete
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION deleteCustomer(customerId INTEGER) RETURNS (BOOLEAN, STRING)
   VAR errorCode INTEGER
   VAR messageText STRING
   BEGIN WORK
   TRY
      DELETE FROM customer WHERE customer.customerid = customerId
      COMMIT WORK
   CATCH
      LET errorCode = sqlca.sqlcode
      LET messageText = SqlHelper.errorText("Deleting customer")
      ROLLBACK WORK
      IF errorCode = -692 OR errorCode = -691 THEN
         RETURN FALSE, "Cannot delete: this customer still has orders or other references."
      END IF
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION
