# =============================================================================
# src/Makefile - compile the AdventureWorks Sales app modules and forms into the
# bin/ output directory (BINDIR, passed in by the top-level Makefile).
#
# LibAw is compiled FIRST: every domain module does IMPORT FGL LibAw and
# fglcomp must find bin/LibAw.42m (via FGLLDPATH, set by the parent Makefile) to
# resolve the import. Main is compiled last (it imports every domain module).
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
LIBS    = LibAw.4gl AwCalc.4gl AwRepo.4gl
MODULES = Territories.4gl SpecialOffers.4gl Customers.4gl SalesPersons.4gl SalesOrders.4gl
MAINMOD = Main.4gl

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
