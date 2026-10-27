# =============================================================================
# src/Makefile - compile the AdventureWorks Sales app modules and forms into the
# bin/ output directory (BINDIR, passed in by the top-level Makefile).
#
# lib_aw is compiled FIRST: every domain module does IMPORT FGL lib_aw and
# fglcomp must find bin/lib_aw.42m (via FGLLDPATH, set by the parent Makefile) to
# resolve the import. main is compiled last (it imports every domain module).
# FGLDBPATH must point at the directory holding adventureworks.sch so the SCHEMA
# references resolve.
# =============================================================================

FGLCOMP   ?= fglcomp
FGLFORM   ?= fglform
BINDIR    ?= $(CURDIR)/../bin
FGLDBPATH ?= ..
FGLLDPATH ?= $(BINDIR)
export FGLDBPATH FGLLDPATH

# Order matters: libraries first, domain modules next, main last.
# LIBS are leaf libraries (no inter-dependencies) that the domain modules import.
LIBS    = lib_aw.4gl aw_calc.4gl aw_repo.4gl
MODULES = territories.4gl specialoffers.4gl customers.4gl salespersons.4gl salesorders.4gl
MAINMOD = main.4gl

SRC     = $(LIBS) $(MODULES) $(MAINMOD)
FORMS   = $(wildcard *.per)

LIB42   = $(addprefix $(BINDIR)/,$(LIBS:.4gl=.42m))
M42     = $(addprefix $(BINDIR)/,$(SRC:.4gl=.42m))
F42     = $(addprefix $(BINDIR)/,$(FORMS:.per=.42f))

.PHONY: all clean
all: $(M42) $(F42)

$(BINDIR):
	mkdir -p $(BINDIR)

# Leaf library objects - built before any importer.
$(LIB42): $(BINDIR)/%.42m: %.4gl | $(BINDIR)
	$(FGLCOMP) -M -Wall -o $(BINDIR) $<

# Every domain/main module depends on all library objects (import resolution).
$(filter-out $(LIB42),$(M42)): $(BINDIR)/%.42m: %.4gl $(LIB42) | $(BINDIR)
	$(FGLCOMP) -M -Wall -o $(BINDIR) $<

$(BINDIR)/%.42f: %.per | $(BINDIR)
	$(FGLFORM) -M -o $(BINDIR) $<

clean:
	$(RM) $(BINDIR)/*.42m $(BINDIR)/*.42f
