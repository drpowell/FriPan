
INSTALLDIR:=$(HOME)/public_html/fripan

CP:=cp -f
MKDIR:=mkdir

HOSTNAME:=$(shell hostname -f)

.PHONY: help compile demo install

help:
	@echo "### Options ###"
	@echo "make compile    - just compile the JavaScript code"
	@echo "make demo       - will compile & set up the example data set"
	@echo "make install    - will install demo to INSTALLDIR [$(INSTALLDIR)]"
	
compile:
	@echo "### Compiling .coffee to .js ###"
	coffee -c .
	
demo: compile
	@echo "### Copying .example files ###"
	$(CP) pan.descriptions.example pan.descriptions
	$(CP) pan.proteinortho.example pan.proteinortho

install: demo
	@echo "### Installing to $(INSTALLDIR) ###"
	$(MKDIR) -p $(INSTALLDIR)
	$(CP) -r lib/ *.js pan.* $(INSTALLDIR)
	@echo "### URL ###"
	@echo "http://$(HOSTNAME)/~$(USER)/fripan/pan.html"
	
	
	