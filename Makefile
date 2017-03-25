
SHELL := /bin/bash
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables

export PATH := ./node_modules/.bin/:$(PATH)
INSTALLDIR := $(HOME)/public_html/fripan
HOSTNAME := $(shell hostname -f)

CP:=cp -f
MKDIR:=mkdir

.PHONY: help compile install
.DEFAULT: help

help:
	@echo "### Options ###"
	@echo "make compile                            # just compile the JavaScript code"
	@echo "make install                            # install in INSTALLDIR [$(INSTALLDIR)]"
	@echo "make install INSTALLDIR=/my/web/folder  # install in custom location"
	
compile:
	@echo "### Compiling src/*.coffee to build.js ###"
	browserify -t coffeeify src/main.coffee -o build.js

debug:
	@echo "### Compiling src/*.coffee to build.js [DEBUG] ###"
	watchify -v --debug -t coffeeify src/main.coffee -o build.js
	
install: compile
	@echo "### Installing to $(INSTALLDIR) ###"
	$(MKDIR) -p $(INSTALLDIR)
	$(CP) build.js pan.css pan.html pan.index index.html test.{proteinortho,strains,descriptions} $(INSTALLDIR)
	@echo "### URL ###"
	@echo "http://$(HOSTNAME)/~$(USER)/fripan/pan.html?test"
