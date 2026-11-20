LUA ?= luajit
VERSION := $(shell sed -n 's/^\#\# Version: *//p' WoWCompanion/WoWCompanion.toc)

.PHONY: verify package clean

verify:
	$(LUA) tests/guard.lua WoWCompanion
	$(LUA) tests/guard.lua WoWCompanion_Digest
	$(LUA) tests/slotcheck.lua WoWCompanion_Digest/Digest.lua tests/fixtures/*.lua
	$(LUA) tests/run.lua WoWCompanion

package:
	mkdir -p dist
	rm -f dist/WoWCompanion-$(VERSION).zip
	zip -r dist/WoWCompanion-$(VERSION).zip WoWCompanion WoWCompanion_Digest

clean:
	rm -rf dist
