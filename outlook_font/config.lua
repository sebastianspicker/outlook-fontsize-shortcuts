-- Configuration concern: defaults, sanitizing and loading of the external JSON(C) file.
-- Self-contained: requires nothing and never notifies; it returns data and problems.
local M = {}

-- True only for contiguous integer keys 1..n; tables with holes are not arrays.
local function is_array(t)
    if type(t) ~= "table" then
        return false
    end
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" then
            return false
        end
        count = count + 1
    end
    return count == #t
end

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deep_copy(v)
    end
    return out
end

local function deep_merge(dst, src)
    if type(dst) ~= "table" then
        dst = {}
    end
    if type(src) ~= "table" then
        return dst
    end

    for k, v in pairs(src) do
        -- An empty table counts as an empty JSON object: merging it is a no-op, whereas
        -- replacing a default object with it would drop all of that object's fields.
        if
            type(v) == "table"
            and type(dst[k]) == "table"
            and (next(v) == nil or not is_array(v))
            and (not is_array(dst[k]))
        then
            dst[k] = deep_merge(dst[k], v)
        else
            dst[k] = deep_copy(v)
        end
    end
    return dst
end

local function strip_jsonc(raw)
    if type(raw) ~= "string" then
        return raw
    end

    local out = {}
    local i = 1
    local len = #raw

    local in_string = false
    local escape = false

    local in_line_comment = false
    local in_block_comment = false

    while i <= len do
        local ch = raw:sub(i, i)
        local next_ch = (i < len) and raw:sub(i + 1, i + 1) or ""

        if in_line_comment then
            -- Line comment ends at newline (handle both \n and \r\n)
            if ch == "\n" then
                in_line_comment = false
                table.insert(out, ch)
            elseif ch == "\r" and next_ch == "\n" then
                in_line_comment = false
                table.insert(out, ch)
                -- \n will be handled in next iteration
            end
            i = i + 1
        elseif in_block_comment then
            if ch == "*" and next_ch == "/" then
                in_block_comment = false
                i = i + 2
            else
                i = i + 1
            end
        elseif in_string then
            table.insert(out, ch)
            if escape then
                -- After an escape, the next character is literal
                -- This handles \", \\, \/, \b, \f, \n, \r, \t, \uXXXX
                escape = false
            elseif ch == "\\" then
                escape = true
            elseif ch == '"' then
                in_string = false
            end
            i = i + 1
        else
            -- Not in string or comment
            if ch == '"' then
                in_string = true
                table.insert(out, ch)
                i = i + 1
            elseif ch == "/" and next_ch == "/" then
                in_line_comment = true
                i = i + 2
            elseif ch == "/" and next_ch == "*" then
                in_block_comment = true
                i = i + 2
            else
                table.insert(out, ch)
                i = i + 1
            end
        end
    end

    -- Note: We don't warn about unterminated strings/comments here
    -- The JSON decoder will report parse errors if the result is invalid
    return table.concat(out)
end

local default_cfg = {
    appNames = { "Outlook", "Microsoft Outlook" },
    settingsMenu = { "Outlook", "Settings…" },
    preferencesMenu = { "Outlook", "Preferences…" },
    headerLabels = {
        "Personal Settings",
        "Persönliche Einstellungen",
        "Paramètres personnels",
        "Configuración personal",
    },
    generalLabels = {
        "General",
        "Allgemein",
        "Général",
    },
    labelTexts = {
        "Text display size",
        "Größe der Textanzeige",
        "Taille d'affichage du texte",
        "Tamaño de visualización de texto",
    },
    overlayText = {
        larger = "Larger",
        smaller = "Smaller",
    },
    delays = {
        activate = 0.1, -- seconds after app:activate()
        waitInterval = 0.05, -- polling interval
        timeout = 3, -- seconds overall timeout for waits
    },
    retry = {
        attempts = 2, -- number of retries after first attempt
        interval = 0.2, -- seconds between retries
    },
    overlayDuration = 1.2, -- seconds before overlay auto-dismisses
    showOverlay = true, -- if false, only notifications are shown (no canvas)
    hotkeys = {
        increase = { mods = { "ctrl", "alt", "cmd" }, key = "g" },
        decrease = { mods = { "ctrl", "alt", "cmd" }, key = "k" },
        toggle = { mods = { "ctrl", "alt", "cmd" }, key = "t" },
    },
}

local function is_string_array(value)
    if not is_array(value) or #value == 0 then
        return false
    end
    for _, v in ipairs(value) do
        if type(v) ~= "string" then
            return false
        end
    end
    return true
end

local function sanitize_config(ext)
    if type(ext) ~= "table" then
        return deep_copy(default_cfg), {}
    end

    local merged = deep_merge(deep_copy(default_cfg), ext)
    local warnings = {}

    local function warn(key, expected)
        table.insert(warnings, key .. " (" .. expected .. ")")
    end

    local function reset_top(key)
        merged[key] = deep_copy(default_cfg[key])
    end

    local function ensure_string_array(key)
        if merged[key] ~= nil and not is_string_array(merged[key]) then
            warn(key, "string[]")
            reset_top(key)
        end
    end

    local function ensure_table_with_fields(key, fields)
        if merged[key] == nil then
            return
        end
        if type(merged[key]) ~= "table" or is_array(merged[key]) then
            warn(key, "table")
            reset_top(key)
            return
        end
        for subkey, expected in pairs(fields) do
            local value = merged[key][subkey]
            if value ~= nil and type(value) ~= expected then
                warn(key .. "." .. subkey, expected)
                merged[key][subkey] = default_cfg[key][subkey]
            end
        end
    end

    ensure_string_array("appNames")
    ensure_string_array("settingsMenu")
    ensure_string_array("preferencesMenu")
    ensure_string_array("headerLabels")
    ensure_string_array("generalLabels")
    ensure_string_array("labelTexts")

    ensure_table_with_fields("overlayText", { larger = "string", smaller = "string" })
    ensure_table_with_fields("delays", { activate = "number", waitInterval = "number", timeout = "number" })
    ensure_table_with_fields("retry", { attempts = "number", interval = "number" })

    if merged.delays.waitInterval <= 0 then
        warn("delays.waitInterval", "number > 0")
        merged.delays.waitInterval = default_cfg.delays.waitInterval
    end
    if merged.delays.timeout <= 0 then
        warn("delays.timeout", "number > 0")
        merged.delays.timeout = default_cfg.delays.timeout
    end
    if merged.retry.interval < 0 then
        warn("retry.interval", "number >= 0")
        merged.retry.interval = default_cfg.retry.interval
    end

    if merged.overlayDuration ~= nil and type(merged.overlayDuration) ~= "number" then
        warn("overlayDuration", "number")
        merged.overlayDuration = default_cfg.overlayDuration
    end
    if merged.showOverlay ~= nil and type(merged.showOverlay) ~= "boolean" then
        warn("showOverlay", "boolean")
        merged.showOverlay = default_cfg.showOverlay
    end

    local function valid_binding(b)
        return type(b) == "table" and is_string_array(b.mods) and type(b.key) == "string"
    end
    if
        merged.hotkeys == nil
        or type(merged.hotkeys) ~= "table"
        or not valid_binding(merged.hotkeys.increase)
        or not valid_binding(merged.hotkeys.decrease)
    then
        if merged.hotkeys ~= nil then
            warn("hotkeys", "table with .increase/.decrease { mods, key }")
        end
        merged.hotkeys = deep_copy(default_cfg.hotkeys)
    elseif
        merged.hotkeys.toggle ~= nil
        and merged.hotkeys.toggle ~= false
        and not valid_binding(merged.hotkeys.toggle)
    then
        warn("hotkeys.toggle", "{ mods, key } or false")
        merged.hotkeys.toggle = deep_copy(default_cfg.hotkeys.toggle)
    end

    return merged, warnings
end

function M.defaults()
    return deep_copy(default_cfg)
end

function M.sanitize(ext)
    return sanitize_config(ext)
end

-- opts = { path = string (required), decode = function(raw) -> value (may throw) | nil }
-- Returns cfg_or_nil, problems where problems = { { title = ..., message = ... }, ... }.
function M.load(opts)
    local cfg_path = opts.path

    local f = io.open(cfg_path, "r")
    if not f then
        return nil, {}
    end
    local ok_read, raw = pcall(function()
        return f:read("*a")
    end)
    f:close()
    if not ok_read then
        return nil,
            {
                { title = "Config Error", message = string.format("Failed to read %s (%s)", cfg_path, tostring(raw)) },
            }
    end
    if raw == nil then
        return nil, {}
    end

    local stripped = strip_jsonc(raw)
    local ext, decode_err
    if type(opts.decode) ~= "function" then
        decode_err = "no JSON decoder available"
    else
        local ok, value = pcall(opts.decode, stripped)
        if ok then
            ext = value
        else
            decode_err = tostring(value)
        end
    end

    if type(ext) == "table" then
        local cfg, warnings = sanitize_config(ext)
        local problems = {}
        if #warnings > 0 then
            table.insert(problems, {
                title = "Config Warning",
                message = "Invalid config keys reset to defaults: " .. table.concat(warnings, ", "),
            })
        end
        return cfg, problems
    elseif ext ~= nil then
        return nil, { { title = "Config Error", message = string.format("Expected object in %s", cfg_path) } }
    elseif decode_err then
        return nil,
            {
                { title = "Config Error", message = string.format("Failed to parse %s (%s)", cfg_path, decode_err) },
            }
    end
    return nil, {}
end

return M
