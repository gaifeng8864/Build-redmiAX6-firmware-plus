-- 自定义规则：校验、去重、原子保存；不写入实际节点或密钥。
local M = {}

-- 限制规则体积和条目数量，避免错误输入导致资源滥用。
local MAX_BYTES = 16384
local MAX_ITEMS = 256
local MAX_ITEM_BYTES = 512

function M.normalize(text)
    if type(text) ~= "string" then
        return nil, "Input must be text"
    end

    if #text > MAX_BYTES then
        return nil, "Input exceeds 16 KiB"
    end

    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    local values, seen = {}, {}
    local line_number = 0

    for line in (text .. "\n"):gmatch("(.-)\n") do
        line_number = line_number + 1
        local item = line:match("^%s*(.-)%s*$")
        if line:find("%c") then
            return nil, "Control character at line " .. line_number
        end

        if item ~= "" and item:sub(1, 1) ~= "#" then
            if #item > MAX_ITEM_BYTES then
                return nil, "Entry too long at line " .. line_number
            end

            if item:find("%c") then
                return nil, "Control character at line " .. line_number
            end

            local key = item:lower()

            if not seen[key] then
                values[#values + 1] = item
                seen[key] = true

                if #values > MAX_ITEMS then
                    return nil, "Too many entries"
                end
            end
        end
    end

    -- Preserve comments and blank lines in saved text.
    return text, values
end

-- 合并顺序：上游内置规则优先，追加用户规则，大小写不敏感去重。
function M.merge(builtin, custom)
    local result, seen = {}, {}

    for _, list in ipairs({builtin, custom}) do
        for _, item in ipairs(list) do
            local key = item:lower()

            if not seen[key] then
                result[#result + 1] = item
                seen[key] = true
            end
        end
    end

    return result
end

-- 验证后在同目录写入临时文件，通过 rename 原子替换单文件。
function M.atomic_write(path, text)
    local normalized, err = M.normalize(text)
    if not normalized then return nil, err end

    local fs = require "nixio.fs"
    local nixio = require "nixio"

    if fs.lstat(path, "type") == "lnk" then
        return nil, "Refusing symlink target"
    end

    local temp = path .. ".tmp." .. tostring(nixio.getpid())

    if fs.lstat(temp) then
        return nil, "Temporary file already exists: " .. temp
    end

    local function fail(reason)
        fs.remove(temp)
        return nil, reason
    end

    local ok = fs.writefile(temp, normalized)
    if not ok then return fail("Temporary write failed") end

    ok = fs.chmod(temp, "0600") -- 0600
    if not ok then return fail("Temporary chmod failed") end

    ok = fs.rename(temp, path)
    if not ok then return fail("Atomic rename failed") end

    return true
end
-- 两文件更新：先备份、再替换，若第二步失败则回滚第一步。
function M.save_pair(paths, texts)
    local fs = require "nixio.fs"
    local nixio = require "nixio"
    local entries = {}
    local pid = tostring(nixio.getpid())

    if paths[1] == paths[2] then
        return nil, "Duplicate target paths"
    end

    local function cleanup()
        for _, e in ipairs(entries) do
            if e.backup then fs.remove(e.backup) end
        end
    end

    -- Validate both fields before modifying either target.
    for i = 1, 2 do
        local normalized, err = M.normalize(texts[i])
        if not normalized then
            return nil, "List " .. i .. ": " .. tostring(err)
        end

        local kind = fs.lstat(paths[i], "type")
        if kind and kind ~= "reg" then
            return nil, "Target is not a regular file"
        end

        local old = nil
        if kind then
            old = fs.readfile(paths[i])
            if old == nil then
                return nil, "Cannot read original rules file"
            end
        end

        entries[i] = {
            path = paths[i],
            text = normalized,
            old = old,
            backup = paths[i] .. ".sniff-backup." .. pid
        }

        if fs.lstat(entries[i].backup) then
            return nil, "Backup path already exists"
        end
    end

    -- Prepare backups before the first replacement.
    for _, e in ipairs(entries) do
        if e.old ~= nil then
            if not fs.writefile(e.backup, e.old) then
                cleanup()
                return nil, "Cannot create backup"
            end
            if not fs.chmod(e.backup, "0600") then
                cleanup()
                return nil, "Cannot secure backup"
            end
        end
    end

    for i, e in ipairs(entries) do
        local ok, err = M.atomic_write(e.path, e.text)

        if not ok then
            local rollback_ok = true
            for j = i - 1, 1, -1 do
                local prev = entries[j]
                local restored
                if prev.old ~= nil then
                    restored = fs.rename(prev.backup, prev.path)
                else
                    restored = fs.remove(prev.path)
                end
                if not restored then rollback_ok = false end
            end

            if rollback_ok then cleanup() end
            return nil, "Write failed: " .. tostring(err)
                .. "; rollback " .. (rollback_ok and "OK" or "FAILED")
        end
    end

    cleanup()
    return true
end
return M
