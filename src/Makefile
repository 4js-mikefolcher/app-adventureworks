# =============================================================================
# src/Makefile - compile the AdventureWorks Sales app modules and forms into the
# bin/ output directory (BINDIR, passed in by the top-level Makefile).
#
# The leaf helpers and lookups (DialogHelper, SqlHelper and the *Lookup modules) are
# compiled FIRST: the domain modules import them
# and fglcomp must find the .42m (via FGLLDPATH, set by the parent Makefile) to
# resolve each import. A model is compiled before its controller, then the menu
# (MainMenuController, which imports every feature controller), and the entry point
# (MainController) last.
# There is no link step: modules are resolved through IMPORT FGL alone.
# FGLDBPATH must point at the directory holding adventureworks.sch so the SCHEMA
# references resolve.
# =============================================================================

FGLCOMP   ?= fglcomp
FGLFORM   ?= fglform
# Every warning fails the build. -Werror makes fglcomp stop on any -Wall warning
# and write no .42m. fglform has no such switch and still writes the .42f when it
# only warns, so the .42f rule below checks its output and removes a form that
# warned, which keeps the next make from treating it as up to date.
WARNFLAGS ?= -Wall -Werror
BINDIR    ?= $(CURDIR)/../bin
FGLDBPATH ?= ..
FGLLDPATH ?= $(BINDIR)
export FGLDBPATH FGLLDPATH

# Order matters: libraries first, domain modules next, main last.
# LIBS are leaf libraries (no inter-dependencies) that the domain modules import.
LIBS    = DialogHelper.4gl SqlHelper.4gl \
          TerritoriesLookup.4gl SalesPersonsLookup.4gl ProductsLookup.4gl SpecialOffersLookup.4gl
MODULES = TerritoriesModel.4gl TerritoriesController.4gl \
          SpecialOffersModel.4gl SpecialOffersController.4gl \
          SalesPersonsModel.4gl SalesPersonsController.4gl \
          CustomersModel.4gl CustomersController.4gl \
          SalesOrdersModel.4gl SalesOrdersController.4gl \
          MainMenuController.4gl
MAINMOD = MainController.4gl

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
	$(FGLCOMP) -M $(WARNFLAGS) -o $(BINDIR) $<

# Every domain/main module depends on all library objects (import resolution).
$(filter-out $(LIB42),$(M42)): $(BINDIR)/%.42m: %.4gl $(LIB42) | $(BINDIR)
	$(FGLCOMP) -M $(WARNFLAGS) -o $(BINDIR) $<

# A controller imports its model, so the model is compiled first.
$(BINDIR)/TerritoriesController.42m: $(BINDIR)/TerritoriesModel.42m
$(BINDIR)/SpecialOffersController.42m: $(BINDIR)/SpecialOffersModel.42m
$(BINDIR)/SalesPersonsController.42m: $(BINDIR)/SalesPersonsModel.42m
$(BINDIR)/CustomersController.42m: $(BINDIR)/CustomersModel.42m
$(BINDIR)/SalesOrdersController.42m: $(BINDIR)/SalesOrdersModel.42m
# The menu imports every feature controller, and the entry point imports the menu.
$(BINDIR)/MainMenuController.42m: $(BINDIR)/CustomersController.42m $(BINDIR)/SalesOrdersController.42m \
   $(BINDIR)/SalesPersonsController.42m $(BINDIR)/SpecialOffersController.42m $(BINDIR)/TerritoriesController.42m
$(BINDIR)/MainController.42m: $(BINDIR)/MainMenuController.42m

# Forms: -W all, and any output at all (a warning or an error) fails the build.
$(BINDIR)/%.42f: %.per | $(BINDIR)
	@echo "$(FGLFORM) -M -W all -o $(BINDIR) $<"
	@out=$$($(FGLFORM) -M -W all -o $(BINDIR) $< 2>&1); status=$$?; \
	if [ $$status -ne 0 ] || [ -n "$$out" ]; then \
		echo "$$out"; $(RM) $@; \
		echo "$<: warnings are treated as errors"; exit 1; \
	fi

clean:
	$(RM) $(BINDIR)/*.42m $(BINDIR)/*.42f
