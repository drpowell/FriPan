
CP:=cp -f

.PHONY: all compile demo

all:
	@echo "### Options ###"
	@echo "make compile    - just compile the JavaScript code"
	@echo "make demo       - will compile & set up the example data set"
	
compile:
	@echo "### Compiling .coffee to .js ###"
	coffee -c .
	
demo: compile
	@echo "### Copying .example files ###"
	$(CP) pan.descriptions.example pan.descriptions
	$(CP) pan.proteinortho.example pan.proteinortho
