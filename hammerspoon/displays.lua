-- Remember the display arrangement for each set of connected monitors and put
-- it back when that set is plugged in again — the free counterpart of
-- BetterDisplay's per-setup layouts, with no command to type.
--
-- A set is identified by the monitors' model names (hs.screen:name()), not by
-- their UUIDs: a dock or a different port can hand the same monitor a new
-- UUID, and the model name is what stays put.
--
--   * The set of monitors changed  -> apply the arrangement saved for it.
--   * Same set, arrangement moved  -> save it (System Settings > Displays).
--   * A set never seen before      -> save whatever macOS chose, so the first
--                                     manual fix becomes the remembered one.
--
-- Arrangements live in hs.settings (Hammerspoon's own preferences plist), not
-- in this repo: displayplacer's output carries per-machine screen IDs, and the
-- repo is public.

local M = {}

local SETTINGS_KEY = "displays.arrangements"

-- macOS reports a hot-plug as several screen changes over a second or two
-- (mirroring, resolution, then position). Acting on the first one would save a
-- half-settled arrangement, so wait until the changes stop. The wait is the
-- hardware settling, not work this module could do faster.
local SETTLE_SECONDS = 2

local function findDisplayplacer()
   for _, path in ipairs({ "/opt/homebrew/bin/displayplacer", "/usr/local/bin/displayplacer" }) do
      if hs.fs.attributes(path) then
         return path
      end
   end
   return nil
end

-- The set's key: sorted model names, so plugging the same monitors into
-- different ports still matches. Two identical monitors appear twice.
local function currentSetKey()
   local names = {}
   for _, screen in ipairs(hs.screen.allScreens()) do
      table.insert(names, screen:name() or "unknown")
   end
   table.sort(names)
   return table.concat(names, " + ")
end

-- The last line of `displayplacer list` is a ready-made command that recreates
-- the current arrangement.
local function currentArrangement(bin)
   local output, ok = hs.execute(bin .. " list")
   if not ok or not output then
      return nil
   end
   local command = nil
   for line in output:gmatch("[^\n]+") do
      if line:match('^displayplacer "') then
         command = line
      end
   end
   return command
end

local function load()
   return hs.settings.get(SETTINGS_KEY) or {}
end

local function store(arrangements)
   hs.settings.set(SETTINGS_KEY, arrangements)
end

function M.start()
   local bin = findDisplayplacer()
   if not bin then
      -- Not installed yet (an early bootstrap phase): the rest of the config
      -- must keep working, so this feature simply stays off.
      return
   end

   local lastSetKey = currentSetKey()

   local function onSettled()
      local setKey = currentSetKey()
      local arrangement = currentArrangement(bin)
      if not arrangement then
         return
      end
      local arrangements = load()
      local saved = arrangements[setKey]

      if setKey ~= lastSetKey and saved and saved ~= arrangement then
         lastSetKey = setKey
         -- The saved line starts with "displayplacer"; run it by full path,
         -- since Hammerspoon does not inherit the shell's PATH.
         local _, ok = hs.execute(bin .. saved:sub(#"displayplacer" + 1))
         if ok then
            hs.alert.show("Display layout restored: " .. setKey)
         else
            hs.alert.show("Display layout restore failed: " .. setKey)
         end
         -- Applying moves the screens, which fires the watcher again; that
         -- pass reads the restored arrangement back and finds nothing to save.
         return
      end

      lastSetKey = setKey
      if saved ~= arrangement then
         arrangements[setKey] = arrangement
         store(arrangements)
      end
   end

   local settleTimer = hs.timer.delayed.new(SETTLE_SECONDS, onSettled)

   -- Globals, as in init.lua: a local watcher is garbage-collected and stops
   -- firing without any error.
   displaysWatcher = hs.screen.watcher.new(function()
      settleTimer:start()
   end)
   displaysWatcher:start()

   -- Record the arrangement in use when Hammerspoon starts, so the set already
   -- connected has something to return to.
   onSettled()
end

return M
