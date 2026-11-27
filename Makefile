LUA ?= luajit
.PHONY: verify package clean release-prep

verify:
	$(LUA) tests/guard.lua WoWCompanion
	$(LUA) tests/guard.lua WoWCompanion_Digest
	$(LUA) tests/glyphs.lua WoWCompanion WoWCompanion_Digest
	$(LUA) tests/slotcheck.lua WoWCompanion_Digest/Digest.lua tests/fixtures/digest_*.lua
	$(LUA) tests/globals.lua WoWCompanion WoWCompanion_Digest
	$(LUA) tests/coldstart.lua WoWCompanion
	$(LUA) tests/layout.lua
	scripts/package.sh | xargs $(LUA) tests/layout.lua
	scripts/check-changes.sh
	sh tests/checkchanges.sh
	sh tests/releaseprep.sh
	$(LUA) tests/run.lua WoWCompanion

package:
	scripts/package.sh

clean:
	rm -rf dist

# Folds changes/*.md into one release: bumps the TOC version (BUMP=minor for a minor), writes the What's new.
release-prep:
	scripts/release-prep.sh
