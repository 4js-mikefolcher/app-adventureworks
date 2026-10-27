# =============================================================================
# Top-level Makefile - AdventureWorks Sales management application (Genero BDL).
#
# This app is a USER-FACING front end for the Sales domain of the AdventureWorks
# database. It does NOT create or load the database - that is the job of the
# separate fgl-adventureworks builder. The database "adventureworks" must already
# exist and be populated before running this app.
#
#   make build   compile all modules and forms into bin/  (*.42m, *.42f)
#   make run     build + launch the app (GDC/desktop, needs the DB up)
#   make run-tui build + launch in terminal mode (headless smoke test)
#   make clean   remove the bin/ output directory
#
# All compiled artifacts land in bin/. The schema file adventureworks.sch lives
# in this directory; FGLDBPATH points here so SCHEMA references in modules and
# forms resolve at compile time. FGLLDPATH/FGLRESOURCEPATH point at bin/ so the
# runtime finds the imported modules and the forms.
# =============================================================================

DBSRC    ?= adventureworks
FGLCOMP  ?= fglcomp
FGLRUN   ?= fglrun
PROFILE  ?= $(CURDIR)/res/fglprofile.pgs
BIN      := $(CURDIR)/bin

export FGLDBPATH := $(CURDIR)
export FGLLDPATH := $(BIN)
export FGLRESOURCEPATH := $(BIN):$(CURDIR)/res

# For the test suites, prepend the installed fglpkg packages (fglunit) to
# FGLLDPATH via `fglpkg env`, on top of bin/ (the app's compiled libraries).
TESTENV = eval "$$(fglpkg env)" && export FGLLDPATH="$(BIN):$$FGLLDPATH"

.PHONY: all build run run-tui test clean help

all: build

help:
	@echo "Targets: build | run | run-tui | test | clean"
	@echo "  build   compile src/*.4gl and src/*.per into bin/"
	@echo "  run     launch the app (desktop client - requires DB '$(DBSRC)')"
	@echo "  run-tui launch headless in terminal mode (smoke test)"
	@echo "  test    compile and run the fglunit suites (JUnit XML in bin/)"

build:
	@mkdir -p $(BIN)
	$(MAKE) -C src BINDIR=$(BIN)

# Desktop (GDC) run. The same compiled program also serves GBC via GAS.
run: build
	FGLPROFILE=$(PROFILE) $(FGLRUN) $(BIN)/main.42m

# Headless terminal-mode run - useful to confirm DB connect + startup without a
# front-end. Still requires the live database.
run-tui: build
	FGLGUI=0 TERM=xterm FGLPROFILE=$(PROFILE) $(FGLRUN) $(BIN)/main.42m

# Unit tests. Compiles the suites against the app's compiled libraries in bin/
# and the installed fglunit package, then runs each suite (writing JUnit XML).
# The pure suite needs no database; the data suite uses FGLPROFILE and skips its
# tests gracefully if the database is not reachable. `make` stops on the first
# suite that reports a failure or error.
test: build
	$(TESTENV) && $(FGLCOMP) -M -Wall -o $(BIN) tests/test_aw_calc.4gl
	$(TESTENV) && $(FGLCOMP) -M -Wall -o $(BIN) tests/test_data.4gl
	@echo "== test_aw_calc =="
	$(TESTENV) && $(FGLRUN) $(BIN)/test_aw_calc.42m --junit $(BIN)/junit-aw_calc.xml
	@echo "== test_data =="
	$(TESTENV) && FGLPROFILE=$(PROFILE) $(FGLRUN) $(BIN)/test_data.42m --junit $(BIN)/junit-data.xml

clean:
	$(RM) -r $(BIN)
