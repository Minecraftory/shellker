-- SPDX-FileCopyrightText: 2024 MrOlegTitovDev
--
-- SPDX-License-Identifier: CC-BY-NC-SA-4.0

-- Events

local function pullEvent(filter)
    return coroutine.yield(filter)
end

local function sleep(duration, interruptable)
    local started_timer = os.startTimer(duration)
    repeat
        local event, timer = pullEvent(not interruptable and "timer" or nil)
    until timer == started_timer or (event == "terminate" and interruptable)
    os.cancelTimer(started_timer)
end

-- IO

function write(text, width)
    local w,h = term.getSize()
    local x,y = term.getCursorPos()

    local start_x = x
    if width ~= nil then
        w = math.min(width+start_x,w)
    end

    local function newLine()
        _, y = term.getCursorPos()
        if y == h then
            term.scroll(1)
        end
        y = math.min(y+1, h)
        term.setCursorPos(start_x, y)
    end

    local function writeWrapped(data)
        x,y = term.getCursorPos()
        data = tostring(data)
        while #data > 0 do
            local remaning_space = math.max(w-x, 0)
            term.write(data:sub(1,remaning_space))
            data = data:sub(remaning_space+1)
            if remaning_space == 0 then
                newLine()
            end
            x,y = term.getCursorPos()
        end
    end

    text = tostring(text)
    for line in text:gmatch("[^\n\r]*") do
        if #line == 0 then
            newLine()
        end
        while #line > 0 do
            local spaces = line:match("^[ \t]+")
            if spaces ~= nil then
                writeWrapped(spaces)
                line = line:sub(#spaces+1)
            end
            local word = line:match("[^ \t]+")
            if word ~= nil then
                x, _ = term.getCursorPos()
                if #word > math.max(w-x, 0) then
                    newLine()
                end
                writeWrapped(word)
                line = line:sub(#word+1)
            else
                break
            end
        end
    end
end

function read(text, width, history)  -- TODO: Add completions
    local w, h = term.getSize()
    local x, y = term.getCursorPos()

    if width ~= nil then
        w = width+x
    end

    if history == nil then
        history = {}
    end

    if text == nil then
        text = ""
    else
        text = tostring(text)
    end
    history[#history+1] = text
    local history_pos = #history
    local pos = math.max(#text+1, 1)

    local function clearLine()
        term.setCursorPos(x,y)
        term.write((" "):rep(w-x+1))
    end

    local function draw()
        clearLine()
        term.setCursorPos(x,y)
        term.write(text:sub(math.max(pos-(w-x),1), math.max(pos-(w-x),1)+math.max(w-x, 0)))
        term.setCursorPos(math.min(pos+x-1,w),y)
    end

    term.setCursorBlink(true)
    draw()

    while true do
        local event_data = {pullEvent()}
        if event_data[1] == "char" then
            text = text:sub(1,math.max(pos-1,0)).. event_data[2].. text:sub(pos)
            pos = pos + 1
        elseif event_data[1] == "key" then
            if event_data[2] == 259 then  -- Backspace
                text = text:sub(1,math.max(pos-2, 0)).. text:sub(pos)
                pos = math.max(pos-1, 1)
            elseif event_data[2] == 261 then  -- Delete
                text = text:sub(1,math.max(pos-1,0)).. text:sub(pos+1)
            elseif event_data[2] == 263 then  -- Left
                pos = math.max(pos-1, 1)
            elseif event_data[2] == 262 then  -- Right
                pos = math.min(pos+1, #text+1)
            elseif event_data[2] == 268 then  -- Home
                pos = 1
            elseif event_data[2] == 269 then  -- End
                pos = #text + 1
            elseif event_data[2] == 265 then  -- Up
                if history_pos == #history then
                    history[#history] = text
                end
                history_pos = math.max(history_pos-1, 1)
                text = history[history_pos]
                pos = #text+1
            elseif event_data[2] == 264 then  -- Down
                if history_pos == #history then
                    history[#history] = text
                end
                history_pos = math.min(history_pos+1, #history)
                text = history[history_pos]
                pos = #text+1
            elseif event_data[2] == 257 or event_data[2] == 335 then -- Enter
                break
            end
        end
        draw()
    end
    term.setCursorBlink(false)

    table.remove(history, #history)

    return text
end

local function fsFind(path, patt)
    if not fs.exists(path) then
        return {}
    end
    local found = {}
    local files = fs.list(path)
    for i=1, #files do
        if tostring(files[i]):match(patt) then
            found[#found+1] = fs.combine(path, files[i])
        end
    end
    return found
end

-- Shellker Loader

LOADER_VERSION = "Shellker version 1.0"
LOADER_CONFIG_DIR = "/etc/default/"
local loader_config = {}

--  Configuration

local function defineConfigParam(name, default_val, description)
    if loader_config[name] then
        return
    end
    loader_config[name] = {default_val, default_val, description}
end

local function defineConfig()
    -- Genral
    defineConfigParam("DEFAULT", 1, "Sets the default menu entry. Must be numeric.")
    defineConfigParam("SAVEDEFAULT", 0, "If set to 1 this setting will automatically set the last selected OS the default entry.")
    defineConfigParam("TIMEOUT", 5, "Sets the time period in seconds for the menu to be displayed before automatically booting unless the user intervenes.")
    defineConfigParam("LOADERS_DIRECTORIES", "", "Sets the additional directories to search for loaders. Paths must separeted with ';' and start from root `/': /myos/boot;/otheros.")
    -- UI
    defineConfigParam("TITLE_MARGIN", 10, "Top margin of the header as a percentage of the screen height.")
    defineConfigParam("LIST_MARGINS", 10, "Margins of the list borders as a percentage of the screen sizes.")
    defineConfigParam("LIST_HEIGHT", 25, "List height as a percentage of the screen height.")
    defineConfigParam("MANUAL_MARGIN", 10, "Top margin of the header as a percentage of the screen height.")
    -- Default boot args
    defineConfigParam("#Default Boot Args", "Ex: /rom/loader.lua=test arg;123", "List of default boot args that will be passed to loader when booting OS. Name should be path to loader. Args must be separated with `;'")
end

local function saveConfig()
    local config_data = {}
    for key, data in pairs(loader_config) do
        config_data[#config_data+1] = (data[3] ~= nil and "#".. tostring(data[3]).. "\n" or "").. tostring(key).. "=".. tostring(data[1] ~= nil and data[1] or "")
    end
    if not fs.exists(LOADER_CONFIG_DIR) then
        fs.makeDir(LOADER_CONFIG_DIR)
    end
    local file = fs.open(fs.combine(LOADER_CONFIG_DIR, "shellker"), "w")
    file.write(table.concat(config_data, "\n\n"))
    file.close()
end

local function loadConfig()
    if not fs.exists(fs.combine(LOADER_CONFIG_DIR, "shellker")) then
        return saveConfig()
    end
    local file = fs.open(fs.combine(LOADER_CONFIG_DIR, "shellker"), "r")
    local contents = file.readAll()
    file.close()
    for line in contents:gmatch("[^\n]+") do
        line = line:gsub("^[ \t]+|[ \t]+$", "")
        if line:match("^[^# \t]") then
            local eq_pos = line:find("=")
            if eq_pos ~= nil then
                local key = tostring(line):sub(1,eq_pos-1)
                local val = tostring(line):sub(eq_pos+1)
                if #key > 0 and #val > 0 then
                    if loader_config[key] ~= nil then
                        loader_config[key][1] = val:match("^[%d%p]+$") and tonumber(val) or val
                    else
                        loader_config[key] = {val:match("^[%d%p]+$") and tonumber(val) or val}
                    end
                end
            end
        end
    end
end

local function getConfigParam(name, default)
    local param = loader_config[name]
    if param == nil then
        return default
    end
    return param[1] ~= nil and param[1] or default
end

local function setConfigParam(name, new_val)
    if loader_config[name] == nil then
        return
    end
    loader_config[name][1] = new_val
    saveConfig()
end

defineConfig()  -- Define config params with default values
loadConfig()  -- Load config from file and change params values if it exists or create file and write default definitions
--  loaders

-- Searches for files that have "loader" in the name.
local function findLoaders()
    local directories = {"/boot/", "/rom"}
    for path in tostring(getConfigParam("LOADERS_DIRECTORIES", "")):gmatch("[%a%d._-%s]+") do
        if #path > 0 then
            directories[#directories+1] = path
        end
    end

    local boot_loaders = {}
    for _, directory in pairs(directories) do
        for _, val in pairs(fsFind(directory, "loader.lua")) do
            if not fs.isDir(val) then
                boot_loaders[#boot_loaders+1] = val
            end
        end
    end
    return boot_loaders
end

--  UI

local function drawManual(x, start_y, w, manual)
    local _, h = term.getSize()
    local _, y = term.getCursorPos()

    local man_x = math.max(x, math.ceil(x+(w/2 - #manual[1]/2)))
    local top_padding = getConfigParam("MANUAL_MARGIN", 10)
    start_y = start_y+math.ceil(h*top_padding/100)

    for i=start_y+1,h do
        term.setCursorPos(1,i)
        term.clearLine()
    end

    for i=1,#manual do
        term.setCursorPos(man_x, start_y+i)
        write(manual[i])
        _, y = term.getCursorPos()
        start_y = start_y + math.max(y-(start_y+i), 0)
    end
    return y
end

local function drawInterface()
    term.clear()

    local w,h = term.getSize()
    local top_padding = getConfigParam("TITLE_MARGIN", 10)
    local list_paddings = getConfigParam("LIST_MARGINS", 10)
    local list_height = getConfigParam("LIST_HEIGHT", 25)

    term.setCursorPos(w/2 - #LOADER_VERSION/2,math.ceil(h*top_padding/100))
    term.write(LOADER_VERSION)
    local x, y = term.getCursorPos()

    -- Drawing borders

    term.setCursorPos(math.ceil(w*list_paddings/100), y+math.ceil(h*list_paddings/100))
    
    local list_start_x, list_start_y = term.getCursorPos()
    list_height = math.max(math.ceil(h*list_height/100)-1, 1)
    local list_width = (w-math.ceil(w*list_paddings/100))-(math.ceil(w*list_paddings/100)+1)+1

    term.write(string.char(151).. string.char(131):rep(list_width-1).. string.char(149))
    local list_end_x = term.getCursorPos()
    list_end_x = math.max(list_end_x - 1, 1)
    for i=1,list_height do
        term.setCursorPos(list_start_x, list_start_y+i)
        term.write(string.char(149))
        term.setCursorPos(list_end_x, list_start_y+i)
        term.write(string.char(149))
    end
    local _, y = term.getCursorPos()
    term.setCursorPos(list_start_x,y+1)
    term.write(string.char(141).. string.char(140):rep((w-math.ceil(w*list_paddings/100))-(math.ceil(w*list_paddings/100)+1)).. string.char(133))

    -- Returning list dimensions
    return list_start_x, list_start_y, list_width, list_height
end

local function drawList(start_x, start_y, width, height, position, entries)
    for i=1,height do
        term.setCursorPos(start_x+1, start_y+i)
        term.write((" "):rep(width-1))
    end
    position = math.min(position, #entries)
    local start_pos = math.max(position-height+1, 1)
    local end_pos = math.max(start_pos+height-1, 1)
    local visible_list = {table.unpack(entries, start_pos, end_pos)}
    for i=1,#visible_list do
        term.setCursorPos(start_x+1, start_y+i)
        local is_selected = i == position - (start_pos - 1)
        if is_selected then
            term.setBackgroundColor(0x100)
            term.write(tostring(visible_list[i]):sub(1,width-1).. (" "):rep(math.max(width-1-#visible_list[i],0)))
            term.setBackgroundColor(0x8000)
            term.setTextColor(0x100)
            term.setCursorPos(term.getCursorPos()-1, start_y+i)
            term.write(string.char(149))
            term.setTextColor(0x1)
        else
            term.write(tostring(visible_list[i]):sub(1,width-2).. (" "):rep(math.max(width-1-#visible_list[i],0)))
        end
        if i == #visible_list and end_pos < #entries then -- Draw arrow that indicates more elements below
            local x, y = term.getCursorPos()
            term.setCursorPos(math.max(start_x+width-2, start_x+1), y)
            if is_selected then
                term.setBackgroundColor(0x100)
            end
            term.write(string.char(31))
            term.setBackgroundColor(0x8000)
        end

        if i == 1 and start_pos > 1 then -- Draw arrow that indicates more elements above
            local x, y = term.getCursorPos()
            term.setCursorPos(math.max(start_x+width-2, start_x+1), y)
            if is_selected then
                term.setBackgroundColor(0x100)
            end
            term.write(string.char(30))
            term.setBackgroundColor(0x8000)
        end
    end
end

local function drawCommandLine()
    term.clear()
    local w,h = term.getSize()
    local top_padding = getConfigParam("TITLE_MARGIN", 10)
    local man_texts = {"Minimal BASH-like line editing is supported.", "`exit' at any time exits."}

    term.setCursorPos(w/2 - #LOADER_VERSION/2,math.ceil(h*top_padding/100))
    term.write(LOADER_VERSION)
    local x, y = term.getCursorPos()

    drawManual(1, y-1, w, man_texts)

    _, y = term.getCursorPos()
    
    return y
end

--  Command-line commands

local function commandHelp(commands, pattern)  -- TODO: write text with safe scroll
    if pattern == nil then
        pattern = ".*"
    end
    local man = {}
    for cmd, cmd_data in pairs(commands) do
        if tostring(cmd):match(pattern) then
            man[#man+1] = tostring(cmd).. (#cmd_data >= 2 and " - ".. tostring(cmd_data[2]) or "")
        end
    end
    return " ".. table.concat(man, "\n ")
end

local function commandConfig(key, new_val)
    if key == nil then
        local config_data = {}
        for param, data in pairs(loader_config) do
            if data[1] ~= nil then
                config_data[#config_data+1] = tostring(param).. "=".. tostring(data[1])  --.. (data[3] ~= nil and " (".. tostring(data[3]).. ")" or "")
            end
        end
        return table.concat(config_data, "\n")
    end
    local value = getConfigParam(key)
    if value == nil then
        return "Config key does not exist."
    end
    if new_val == nil then
        return tostring(key).. " is set to `".. tostring(value).. "'."
    end
    setConfigParam(key, new_val)
    return tostring(key).. " was set to `".. tostring(new_val).. "'."
end

local function commandBoot()
    return nil, "boot"
end

local function commandClear()
    drawCommandLine()
end

local function commandDate()
    return os.date("!%Y-%m-%dT%TZ")
end

local function commandEcho(...)
    return table.concat({...}, " ")
end

local function commandHalt()
    os.shutdown()
end

local function commandLs(path)
    if path == nil then
        path = "/"
    end
    local text = ""
    if not fs.exists(path) then
        return "Specified path does not exists."
    end
    if not fs.isDir(path) then
        return "Specified path is not a directory."
    end
    local files = fs.list(path)
    for i=1,#files do
        if fs.isDir(fs.combine(path, files[i])) then
            files[i] = files[i].. "/"
        end
    end
    return table.concat(files, " ")
end

local function commandCat(path)
    if path == nil then
        return "Specify the path to the file."
    end
    if not fs.exists(path) then
        return "Specified path does not exists."
    end
    if fs.isDir(path) then
        return "Specified path is a directory."
    end
    local file = fs.open(path, "r")
    local text = file.readAll()
    file.close()
    return text
end

local function commandHexDump(path, offset, length)
    if path == nil then
        return "Specify the path to the file."
    end
    if not fs.exists(path) then
        return "Specified path does not exists."
    end
    if fs.isDir(path) then
        return "Specified path is a directory."
    end
    local file = fs.open(path, "r")
    if offset then
        file.seek("cur", math.max(offset, 0))
    end
    local content
    if length == nil then
        content = file.readAll()
    else
        content = file.read(tonumber(length))
    end
    file.close()
    local bytes = {string.byte(content, 1,-1)}
    return table.concat(bytes, " ")
end

local function commandRegExp(pattern, string)
    if pattern == nil then
        return "Specify the regular expression."
    end
    if tostring(string):match(tostring(pattern)) then
        return "The specified string matches the pattern."
    else
        return "The specified string does not match the pattern."
    end
end

local function commandSearch(path, pattern)
    if path == nil then
        return "Specify the path to the files to search."
    end
    if pattern == nil then
        return "Specify a pattern for the search."
    end
    if not fs.exists(path) then
        return "Specified path does not exists."
    end
    if not fs.isDir(path) then
        return "Specified path is not a directory."
    end
    local files = fsFind(path, pattern)
    for i=1,#files do
        if fs.isDir(files[i]) then
            files[i] = files[i].. "/"
        end
    end
    return table.concat(files, " ")
end

local function commandSleep(delay)
    if delay == nil then
        return "Specfiy the delay to wait for."
    end
    if type(delay) ~= "number" then
        return "Delay must be a number."
    end
    sleep(delay, true)
end

local function commandReboot()
    os.reboot()
end

local function commandExit()
    return nil, "list"
end

--   Handlers

local function handleList(x, y, w, h, entries, start_pos, timeout_timer)
    local position = 1
    if start_pos ~= nil then
        position = math.min(start_pos, #entries)
    end
    while true do
        drawList(x,y,w,h,position,entries)
        local event_data = {pullEvent()}
        if event_data[1] == "key" then
            if event_data[2] == 264 then  -- Down
                position = math.min(position+1, #entries)
                if timeout_timer ~= nil then
                    return "list", position
                end
            elseif event_data[2] == 265 then  -- Up
                position = math.max(position-1, 1)
                if timeout_timer ~= nil then
                    return "list", position
                end
            elseif event_data[2] == 67 then  -- c
                return "cmd"
            elseif event_data[2] == 69 then  -- e
                return "args", position
            elseif event_data[2] == 257 or event_data[2] == 335 then  -- Enter
                return "boot", position
            else
                if timeout_timer ~= nil then
                    return "list", position
                end
            end
        elseif event_data[1] == "timer" and event_data[2] == timeout_timer then
            return "boot", position
        end
    end
end

local function handleCommandLine()
    local w, h = term.getSize()
    local y = drawCommandLine()
    local commands_history = {}

    local available_commands = {
        ["boot"]={commandBoot, "Boot the OS which has been selected."},
        ["cat"]={commandCat, "Display the contents of the specified file."},
        ["clear"]={commandClear, "Clear the screen."},
        ["config"]={commandConfig, "Display values of the config or the specified key. Changes value if a new value is specified."},
        ["date"]={commandDate, "Print the current date and time."},
        ["echo"]={commandEcho, "Display the requested text."},
        ["halt"]={commandHalt, "The command halts the computer."},
        ["help"]={commandHelp, "Display helpful information about builtin commands."},
        ["hexdump"]={commandHexDump, "Show raw contents of a specified file."},
        ["ls"]={commandLs, "List the contents of specified directory."},
        ["reboot"]={commandReboot, "Reboot the computer."},
        ["regexp"]={commandRegExp, "Test if regular expression matches string."},
        ["search"]={commandSearch, "Search files and directory in specified path."},
        ["sleep"]={commandSleep, "Sleep for specified seconds. Interrupts when pressing `CTRL+T'."},
        ["exit"]={commandExit, "Return to loader menu."}
    }

    local function scroll()
        _, y = term.getCursorPos()
        if y == h then
            term.scroll(1)
        end
        y = math.min(y+1, h)
        term.setCursorPos(1, y)
    end

    while true do
        scroll()
        term.write("shellker>")
        local text = read(nil, nil, commands_history)
        commands_history[#commands_history+1] = text
        text = text:gsub("^[ \t]+|[ \t]+$", "")  -- Removing start and end spaces
        local cmd_data = {}
        for part in text:gmatch("[^ \t]+") do  -- Iterating through all words in entered text
            cmd_data[#cmd_data+1] = part:match("^[%d%p]+$") and tonumber(part) or part  -- If string contains only digits and punctuation then convert it to number
        end
        if #cmd_data > 0 then
            local args = {table.unpack(cmd_data, 2)}
            local cmd = available_commands[tostring(cmd_data[1]):lower()]
            if cmd ~= nil then
                if cmd[1] == commandHelp then
                    table.insert(args, 1, available_commands)
                end
                local res, mode = cmd[1](table.unpack(args))
                if mode ~= nil then
                    return mode
                end
                if res ~= nil then
                    scroll()
                    write(res)
                end
            else
                scroll()
                write("Unknown command `".. tostring(cmd_data[1]).. "'.")
                scroll()
                write("Type `help' to list available commands.")
            end
        end
    end
end

local function handleArgs(x, y, w, h, args)
    local position = math.max(#args, 1)
    local man_texts = {"Use the ".. string.char(30).. " and ".. string.char(31).. " keys to select line.", "Press enter to edit selected line,", "`x' to boot, `c' for a command-line", "or F1 to return to the loader menu."}

    drawManual(x, y+h, w, man_texts)

    while true do
        drawList(x,y,w,h, position, args)
        local event_data = {pullEvent("key")}
        if event_data[2] == 264 then  -- Down
            if position == #args and #tostring(args[position]):gsub("[ \t]", "") > 0 then
                args[#args+1] = ""
                position = math.min(position+1, #args)
            end
            position = math.min(position+1, #args)
        elseif event_data[2] == 265 then  -- Up
            position = math.max(position-1, 1)
        elseif event_data[2] == 257 or event_data[2] == 335 then  -- Enter
            term.setCursorPos(x+1, math.min(y+position, y+h))
            local line = read(args[position], w-2)
            if #line:gsub("[ \t]", "") > 0 then
                args[position] = line
            elseif position > 1 then
                table.remove(args,position)
                position = math.max(position-1, 1)
            end
        elseif event_data[2] == 290 then  -- F1
            return "list", args
        elseif event_data[2] == 88 then  -- x
            return "boot", args
        elseif event_data[2] == 67 then  -- c
            return "cmd", args
        end
        if #args > 1 and position ~= #args and #tostring(args[#args]):gsub("[ \t]", "") == 0 then
            table.remove(args, #args)
        end
    end
end

local function handleBoot(loader_path, args)
    term.clear()
    term.setCursorPos(1,1)
    if not fs.exists(loader_path) then
        return "list", false, "File does not exists."
    end
    if fs.isDir(loader_path) then
        return "list", false, "Specified path is a directory."
    end
    local file = fs.open(loader_path, "r")
    local content = file.readAll()
    file.close()
    local func, err = load(content)
    if func == nil then
        return "list", false, "Unable to boot the selected OS due to\n`".. (err ~= nil and tostring(err).. "." or "unknown error.").. "'\nPlease, report this error to its author."
    end
    local ok, loader = pcall(func)
    if ok and loader == nil then
        return nil, true
    elseif not ok then
        return "list", false, "Unable to boot the selected OS due to\n`".. (loader ~= nil and tostring(loader).. "." or "unknown error.").. "'\nPlease, report this error to its author."
    end
    if type(loader) ~= "table" or type(loader["boot"]) ~= "function" then
        return "list", false, "Failed to boot the selected OS because its boot loader does not return table with the `boot' function.\nPlease report this error to its developers."
    end
    pcall(loader["boot"], table.unpack(args))
    return nil, true
end

local function main()
    local loaders = findLoaders()  -- Linuxale (on /discord/@justxale)
    local boot_args = {}
    local mode = "list"
    local selected_boot = getConfigParam("DEFAULT", 1)
    local timeout = getConfigParam("TIMEOUT", 5)

    local man_texts = {"Use the ".. string.char(30).. " and ".. string.char(31).. " keys to select entry.", "Press enter to boot the selected OS,", "`e' to edit the commands before boot", "or `c' for a command-line."}

    if #loaders == 0 then
        write("No bootable media was found. Press `enter' to enter command-line.")
        read()
        mode = "cmd"
    end

    for i=1,#loaders do  -- Try to find and load args from the config
        local args_string = getConfigParam(loaders[i])
        if args_string ~= nil then
            local args = {}
            for part in tostring(args_string):gmatch("[%a%d%s]+") do
                args[#args+1] = part
            end
            boot_args[i] = args
        end
    end

    local timeout_timer = nil
    if timeout >= 0 then
        man_texts[#man_texts+1] = "The selected entry will be loaded in ".. tostring(timeout).. "s."
        timeout_timer = os.startTimer(timeout)
    end

    local list_x, list_y, list_w, list_h = drawInterface()
    drawManual(list_x, list_y+list_h, list_w, man_texts)

    while true do
        local res = {}
        if #loaders == 0 then
            mode = "cmd"
        end
        if mode == "list" then
            res = {handleList(list_x, list_y, list_w, list_h, loaders, selected_boot, timeout_timer)}
            if #res > 1 then
                selected_boot = res[2]
                if getConfigParam("SAVEDEFAULT", 0) == 1 then
                    setConfigParam("DEFAULT", selected_boot)
                end
            end
            if timeout_timer ~= nil then
                os.cancelTimer(timeout_timer)
                timeout_timer = nil
                table.remove(man_texts, #man_texts)
                drawManual(list_x, list_y+list_h, list_w, man_texts)
            end
            -- pullEvent() -- TODO: Add timeout if char event is not queued
        elseif mode == "args" then
            local args = boot_args[selected_boot]
            if args == nil then
                args = {""} -- Set to default args
                boot_args[selected_boot] = args
            end
            res = {handleArgs(list_x, list_y, list_w, list_h, args)}
            if #res > 1 then
                boot_args[selected_boot] = res[2]
            end
            -- pullEvent() -- TODO: Add timeout if char event is not queued
            drawManual(list_x, list_y+list_h, list_w, man_texts)
        elseif mode == "cmd" then
            res = {handleCommandLine()}
            list_x, list_y, list_w, list_h = drawInterface()
            drawManual(list_x, list_y+list_h, list_w, man_texts)
        elseif mode == "boot" then
            if getConfigParam("SAVEDEFAULT", 0) == 1 then
                setConfigParam("DEFAULT", selected_boot)
            end
            res = {handleBoot(loaders[selected_boot])}
            if res[2] ~= nil and res[2] == true then  -- Success
                break
            end
            term.clear()
            term.setCursorPos(1,1)
            write((res[3] ~= nil and tostring(res[3]) or "Unable to boot the selected OS due to an unknown error.").. "\n\nPress any key to return to the Shellker.")
            pullEvent("key")
            list_x, list_y, list_w, list_h = drawInterface()
            drawManual(list_x, list_y+list_h, list_w, man_texts)
        end
        mode = #res > 0 and res[1] or "list"
    end
    os.shutdown()
end

main()
