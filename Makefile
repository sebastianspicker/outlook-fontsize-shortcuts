# Dev tooling for a Hammerspoon (Lua 5.4) project. Tools live in a project-local
# LuaRocks tree; override LUAROCKS to point at a luarocks configured for Lua 5.4.
LUAROCKS_TREE ?= ./.luarocks
LUA ?= lua
LUA_VERSION ?= 5.4
LUAROCKS ?= luarocks
ROCKS := $(LUAROCKS) --tree $(LUAROCKS_TREE) --lua-version $(LUA_VERSION)

LUACHECK := $(LUAROCKS_TREE)/bin/luacheck

TOOLS_LUACHECK_VERSION ?= 1.2.0-1

.PHONY: tools lint fmt fmt-check test check clean

tools:
	@command -v $(LUAROCKS) >/dev/null || (echo "Missing '$(LUAROCKS)' (try: brew install luarocks)" && exit 1)
	@mkdir -p $(LUAROCKS_TREE)
	@$(ROCKS) install luacheck $(TOOLS_LUACHECK_VERSION)

lint: $(LUACHECK)
	@$(LUACHECK) .

fmt:
	@command -v stylua >/dev/null || (echo "Missing 'stylua' (try: brew install stylua)" && exit 1)
	@stylua .

fmt-check:
	@command -v stylua >/dev/null || (echo "Missing 'stylua' (try: brew install stylua)" && exit 1)
	@stylua --check .

test:
	@$(LUA) test/attempt_test.lua

check: fmt-check lint test

clean:
	@echo "Removing ./.luarocks"
	@rm -rf ./.luarocks
