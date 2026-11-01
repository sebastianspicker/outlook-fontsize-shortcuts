-- ~/.hammerspoon/init.lua
--
-- outlook-fontsize-shortcuts
--
-- Copy this file (along with outlook-font.lua and the outlook_font/ directory)
-- into ~/.hammerspoon/ and reload Hammerspoon.
--
-- If you already have an init.lua, merge the sections below into yours.
-- Each section is numbered and independent -- you can reorder or adjust them.

--------------------------------------------------------------------------------
-- 1) Allow hs.application.find() to use Spotlight
--    (Needed so Hammerspoon can locate "Outlook" / "Microsoft Outlook" by name)
--------------------------------------------------------------------------------
hs.application.enableSpotlightForNameSearches(true)

--------------------------------------------------------------------------------
-- 2) Import the Outlook-Font module
--------------------------------------------------------------------------------
local of = require("outlook-font")

--------------------------------------------------------------------------------
-- 3) Load config and bind hotkeys
--    Default shortcuts (override in outlook-font.json next to this file):
--      Ctrl+Alt+Cmd+G  ->  Increase text size
--      Ctrl+Alt+Cmd+K  ->  Decrease text size
--      Ctrl+Alt+Cmd+T  ->  Toggle (alternates increase/decrease)
--    `report` shows a notification after a successful change (hotkeys and menu).
--------------------------------------------------------------------------------
local messages = { increase = "Text size increased", decrease = "Text size decreased" }
local function report(ok, direction)
    if not ok then
        return
    end
    if direction == "toggle" then
        direction = of.toggleState and "increase" or "decrease"
    end
    of.notify("Outlook Font", messages[direction])
end

of.loadConfig()
local hotkeyMapping = {
    increase = of.cfg.hotkeys.increase,
    decrease = of.cfg.hotkeys.decrease,
    toggle = of.cfg.hotkeys.toggle,
}
hotkeyMapping.onComplete = report
of.bindHotkeys(hotkeyMapping)

--------------------------------------------------------------------------------
-- 4) Build the menubar dropdown
--    Shortcut hints are shown next to each item for discoverability.
--------------------------------------------------------------------------------
local function shortcutLabel(binding)
    if not binding or not binding.mods or not binding.key then
        return ""
    end
    local symbols = { ctrl = "\u{2303}", alt = "\u{2325}", cmd = "\u{2318}", shift = "\u{21E7}" }
    local parts = {}
    for _, m in ipairs(binding.mods) do
        table.insert(parts, symbols[m] or m)
    end
    table.insert(parts, string.upper(binding.key))
    return "  " .. table.concat(parts)
end

local menuItems = {
    {
        title = "Larger Text Size" .. shortcutLabel(of.cfg.hotkeys.increase),
        fn = function()
            of.adjustTextSize(true, function(ok)
                report(ok, "increase")
            end)
        end,
    },
    {
        title = "Smaller Text Size" .. shortcutLabel(of.cfg.hotkeys.decrease),
        fn = function()
            of.adjustTextSize(false, function(ok)
                report(ok, "decrease")
            end)
        end,
    },
    {
        title = "Toggle Text Size" .. shortcutLabel(of.cfg.hotkeys.toggle),
        fn = function()
            of.toggleTextSize(function(ok)
                report(ok, "toggle")
            end)
        end,
    },
    { title = "-" },
    {
        title = "Reload Config",
        fn = function()
            hs.reload()
        end,
    },
}

--------------------------------------------------------------------------------
-- 5) Create the menubar icon. It must live in a global: Hammerspoon removes a
--    menubar item once its object is garbage-collected, and locals of this file
--    go out of scope when it finishes loading.
--------------------------------------------------------------------------------
outlookFontMenu = hs.menubar.new()
if outlookFontMenu then
    outlookFontMenu:setTitle("A")
    outlookFontMenu:setTooltip("Outlook Font Size Shortcuts")
    outlookFontMenu:setMenu(menuItems)
else
    of.notify("Outlook Font", "Could not create menubar item. Check the Hammerspoon console for errors.")
end
