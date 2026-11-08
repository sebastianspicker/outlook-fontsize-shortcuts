local M = {}

-- Helper to safely get attribute value from a node
local function get_attribute(node, key)
    if not node then
        return nil
    end
    -- Check if node has the attributeValue method
    if type(node.attributeValue) ~= "function" then
        return nil
    end
    -- Use pcall to handle any errors from the accessibility API
    local ok, value = pcall(function()
        return node:attributeValue(key)
    end)
    if ok then
        return value
    end
    return nil
end

local function children_of(node)
    return get_attribute(node, "AXChildren") or {}
end

local function contains_any(text, substrings)
    for _, substring in ipairs(substrings) do
        if type(substring) == "string" and string.find(text, substring, 1, true) then
            return true
        end
    end
    return false
end

-- Depth-first search for the first node that has `role` (nil matches no role) or is
-- static text containing any of `substrings`. Reads each node once, whereas calling
-- find_first_by_role and find_static_text per label walks the whole tree each time.
function M.find_role_or_static_text(root, role, substrings)
    if not root then
        return nil
    end
    local node_role = get_attribute(root, "AXRole")
    if role ~= nil and node_role == role then
        return root
    end
    if node_role == "AXStaticText" then
        local value = get_attribute(root, "AXValue") or get_attribute(root, "AXTitle") or ""
        if contains_any(value, substrings or {}) then
            return root
        end
    end
    for _, child in ipairs(children_of(root)) do
        local found = M.find_role_or_static_text(child, role, substrings)
        if found then
            return found
        end
    end
    return nil
end

function M.find_first_by_role(root, role)
    return M.find_role_or_static_text(root, role, nil)
end

function M.find_static_text(root, substring)
    return M.find_role_or_static_text(root, nil, { substring })
end

function M.find_ancestor_by_role(node, role)
    local current = node
    local depth = 0
    local max_depth = 50
    while current do
        if get_attribute(current, "AXRole") == role then
            return current
        end
        depth = depth + 1
        if depth >= max_depth then
            return nil
        end
        current = get_attribute(current, "AXParent")
    end
    return nil
end

function M.find_button_group_near_labels(root, label_texts)
    for _, label in ipairs(label_texts or {}) do
        local elem = M.find_static_text(root, label)
        if elem then
            local grp = elem
            while grp do
                local btns = {}
                for _, child in ipairs(children_of(grp)) do
                    if get_attribute(child, "AXRole") == "AXButton" then
                        table.insert(btns, child)
                    end
                end
                if #btns >= 2 then
                    return btns
                end
                grp = get_attribute(grp, "AXParent")
            end
        end
    end
    return nil
end

-- Returns the button for "larger" or "smaller" by matching AXTitle/AXValue to labels; nil if ambiguous.
function M.button_by_size_label(buttons, larger_text, smaller_text, want_larger)
    if not buttons or #buttons < 2 or not larger_text or not smaller_text then
        return nil
    end
    local larger_btn, smaller_btn
    for _, btn in ipairs(buttons) do
        local title = (get_attribute(btn, "AXTitle") or get_attribute(btn, "AXValue") or ""):gsub("^%s*(.-)%s*$", "%1")
        if string.find(title, larger_text, 1, true) then
            larger_btn = btn
        elseif string.find(title, smaller_text, 1, true) then
            smaller_btn = btn
        end
    end
    if want_larger then
        return larger_btn
    end
    return smaller_btn
end

return M
