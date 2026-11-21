LUA ?= luajit
VERSION := $(shell sed -n 's/^\#\# Version: *//p' WoWCompanion/WoWCompanion.toc)

.PHONY: verify package clean

verify:
	$(LUA) tests/guard.lua WoWCompanion
	$(LUA) tests/guard.lua WoWCompanion_Digest
	$(LUA) tests/guard.lua WoWCompanion_Answers
	$(LUA) tests/slotcheck.lua WoWCompanion_Digest/Digest.lua tests/fixtures/digest_*.lua
	$(LUA) tests/slotcheck.lua WoWCompanion_Answers/Answers.lua tests/fixtures/answers_*.lua
	$(LUA) tests/run.lua WoWCompanion

package:
	mkdir -p dist
	rm -f dist/WoWCompanion-$(VERSION).zip
	zip -r dist/WoWCompanion-$(VERSION).zip WoWCompanion WoWCompanion_Digest WoWCompanion_Answers

clean:
	rm -rf dist
