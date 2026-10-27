################################################################################
# salespersons.4gl - browse and maintain sales people (salesperson).
#
# A salesperson row corresponds to an existing employee (businessentityid is
# both PK and FK), so adding one is outside the Sales scope and not offered.
# Editable attributes: territory, quota, bonus, commission. The YTD figure is a
# system-maintained aggregate, shown read-only. Names resolve via person.
#
# Public entry: salespersons_run()
################################################################################

IMPORT FGL lib_aw

TYPE t_sp RECORD
    businessentityid INTEGER,
    spname           VARCHAR(120),
    territoryid      INTEGER,
    salesquota       DECIMAL(20,4),
    bonus            DECIMAL(20,4),
    commissionpct    DECIMAL(10,4),
    salesytd         DECIMAL(20,4)
END RECORD

PRIVATE DEFINE m_sp DYNAMIC ARRAY OF t_sp

#-------------------------------------------------------------------------------
#+ Open the sales-persons window and run the browse/maintain dialog.
#-------------------------------------------------------------------------------
FUNCTION salespersons_run()
    OPEN WINDOW w_sp WITH FORM "salespersons"
        ATTRIBUTES(TEXT = "Sales Persons", STYLE = "dialog")
    CALL aw_fill_combobox("c_terr", "SELECT territoryid, name FROM salesterritory ORDER BY name")
    CALL sp_load()
    CALL sp_browse()
    CLOSE WINDOW w_sp
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load all sales people with their resolved names, ordered by name.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION sp_load()
    DEFINE r t_sp
    DEFINE l_sql STRING
    LET l_sql =
        "SELECT salesperson.businessentityid,"
        || " TRIM(person.lastname) || ', ' || TRIM(person.firstname),"
        || " salesperson.territoryid, salesperson.salesquota, salesperson.bonus,"
        || " salesperson.commissionpct, salesperson.salesytd"
        || " FROM salesperson"
        || " LEFT JOIN person ON person.businessentityid = salesperson.businessentityid"
        || " ORDER BY 2"
    CALL m_sp.clear()
    DECLARE c_sp CURSOR FROM l_sql
    FOREACH c_sp INTO r.*
        LET m_sp[m_sp.getLength() + 1] = r
    END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse dialog: inline edit of territory / quota / bonus / commission; delete.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION sp_browse()
    DEFINE rec t_sp
    DISPLAY ARRAY m_sp TO sr_sp.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

        ON UPDATE
            LET rec = m_sp[arr_curr()]
            IF sp_input(scr_line(), rec) THEN
                IF sp_save(rec) THEN
                    LET m_sp[arr_curr()] = rec
                END IF
            END IF

        ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
            IF m_sp.getLength() > 0 THEN
                IF aw_confirm("Delete sales person",
                              SFMT("Delete sales person %1?", m_sp[arr_curr()].spname)) THEN
                    IF sp_delete(m_sp[arr_curr()].businessentityid) THEN
                        CALL m_sp.deleteElement(arr_curr())
                    END IF
                END IF
            END IF

    END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of the editable salesperson columns, with non-negative checks.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION sp_input(p_line INTEGER, rec t_sp INOUT) RETURNS BOOLEAN
    LET int_flag = FALSE
    INPUT rec.territoryid, rec.salesquota, rec.bonus, rec.commissionpct
        FROM sr_sp[p_line].c_terr, sr_sp[p_line].c_quota,
             sr_sp[p_line].c_bonus, sr_sp[p_line].c_comm
        ATTRIBUTES(WITHOUT DEFAULTS)
        AFTER INPUT
            IF NOT int_flag THEN
                IF rec.bonus < 0 OR rec.commissionpct < 0
                   OR (rec.salesquota IS NOT NULL AND rec.salesquota < 0) THEN
                    ERROR "Quota, bonus and commission must not be negative."
                    NEXT FIELD c_bonus
                END IF
            END IF
    END INPUT
    RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist the editable salesperson attributes.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION sp_save(rec t_sp INOUT) RETURNS BOOLEAN
    DEFINE l_now DATETIME YEAR TO SECOND
    LET l_now = CURRENT YEAR TO SECOND
    BEGIN WORK
    TRY
        UPDATE salesperson
           SET territoryid = rec.territoryid, salesquota = rec.salesquota,
               bonus = rec.bonus, commissionpct = rec.commissionpct,
               modifieddate = l_now
         WHERE businessentityid = rec.businessentityid
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        CALL aw_sql_error("Saving sales person")
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a salesperson. Usually blocked by orders / history references.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION sp_delete(p_id INTEGER) RETURNS BOOLEAN
    BEGIN WORK
    TRY
        DELETE FROM salesperson WHERE businessentityid = p_id
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
            ERROR "Cannot delete: this sales person is referenced by orders or history."
        ELSE
            CALL aw_sql_error("Deleting sales person")
        END IF
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION
