LUA ?= luajit
VERSION := $(shell sed -n 's/^\#\# Version: *//p' WoWCompanion/WoWCompanion.toc)

.PHONY: verify package clean

verify:
	$(LUA) tests/guard.lua WoWCompanion
	$(LUA) tests/run.lua WoWCompanion

package:
	mkdir -p dist
	rm -f dist/WoWCompanion-$(VERSION).zip
	zip -r dist/WoWCompanion-$(VERSION).zip WoWCompanion

clean:
	rm -rf dist
