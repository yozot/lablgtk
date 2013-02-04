# Toplevel makefile for LablGtk2

all opt doc install uninstall byte world old-install old-uninstall: config.make
all opt doc install uninstall byte clean depend world old-install old-uninstall:
	$(MAKE) -C src3 $@
	$(MAKE) -C src $@

tools:
	cd tools && $(MAKE)

arch-clean:
	@rm -f config.status config.make config.cache config.log
	@rm -f \#*\# *~ aclocal.m4
	@rm -rf autom4te*.cache

configure: configure.in
	aclocal
	autoconf

config.make: config.make.in
	@echo config.make is not up to date. Execute ./configure first.
	@exit 2

.PHONY: all opt doc install byte world clean depend arch-clean headers tools

headers:
	find examples -name "*.ml" -exec headache -h header_examples {} \;
	find applications -name "*.ml" -exec headache -h header_apps {} \;
	find applications -name "*.mli" -exec headache -h header_apps {} \;
	find src -name "*.ml" -exec headache -h header {} \;
	find src -name "*.mli" -exec headache -h header {} \;
	find src -name "*.c" -exec headache -h header {} \;
	find src -name "*.h" -exec headache -h header {} \;
	find src3 -name "*.ml" -exec headache -h header {} \;
	find src3 -name "*.mli" -exec headache -h header {} \;
	find src3 -name "*.c" -exec headache -h header {} \;
	find src3 -name "*.h" -exec headache -h header {} \;
	find tools -name "*.ml" -exec headache -h header {} \;
