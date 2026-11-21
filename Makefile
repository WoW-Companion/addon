LUA ?= luajit
.PHONY: verify package clean

verify:
	$(LUA) tests/guard.lua WoWCompanion
	$(LUA) tests/guard.lua WoWCompanion_Digest
	$(LUA) tests/guard.lua WoWCompanion_Answers
	$(LUA) tests/slotcheck.lua WoWCompanion_Digest/Digest.lua tests/fixtures/digest_*.lua
	$(LUA) tests/slotcheck.lua WoWCompanion_Answers/Answers.lua tests/fixtures/answers_*.lua
	$(LUA) tests/layout.lua
	$(LUA) tests/run.lua WoWCompanion

package:
	scripts/package.sh

clean:
	rm -rf dist
