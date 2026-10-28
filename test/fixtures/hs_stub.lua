-- A stand-in for Hammerspoon's `hs`, enough to load hammerspoon/translate.lua
-- under plain luajit and drive its keys: hotkeys, the copy, the menu, the
-- task it starts and the popups it opens (their page, every update() sent to
-- it, and its message handler) are recorded in `stub`, and timers run when the
-- test says. Everything else answers with an object that accepts any call.

stub = { hotkeys = {}, tasks = {}, keystrokes = {}, choosers = {}, timers = {}, changeCount = 0,
         popups = {}, pasted = {}, written = {} }

local any
any = setmetatable({}, {
   __index = function() return any end,
   __call = function() return any end,
})

local function chain(t)
   return setmetatable(t, { __index = function() return function(self) return self end end })
end

local screen = { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end }

-- Enough JSON for update()'s arguments: strings, booleans and arrays of them.
local function json(v)
   if type(v) == "table" then
      local parts = {}
      for i = 1, #v do parts[i] = json(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
   elseif type(v) == "string" then
      return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
   end
   return tostring(v)
end

-- The handler a popup's page posts to; the next webview created takes it.
local pendingHandler

hs = setmetatable({
   configdir = "/hs",
   mouse = {
      absolutePosition = function() return { x = 100, y = 100 } end,
      getCurrentScreen = function() return screen end,
   },
   screen = { mainScreen = function() return screen end, find = function() return screen end },
   hotkey = {
      bind = function(mods, key, pressed, released)
         stub.hotkeys[table.concat(mods, "+") .. "+" .. key] = released or pressed
      end,
   },
   eventtap = {
      keyStroke = function(mods, key)
         table.insert(stub.keystrokes, table.concat(mods, "+") .. "+" .. key)
         stub.changeCount = stub.changeCount + 1  -- the app copies the selection
      end,
      new = function() return chain({}) end,
      event = { types = { keyDown = 10 }, properties = { keyboardEventAutorepeat = 8 } },
   },
   keycodes = { map = { c = 8, escape = 53 } },
   json = { encode = json },
   base64 = { decode = function(s) return "PNG:" .. s end },
   image = {
      imageFromPath = function(path)
         local f = io.open(path, "rb")
         local data = f and f:read("*a")
         if f then f:close() end
         table.insert(stub.written, path)
         return data and { data = data } or nil
      end,
   },
   webview = {
      usercontent = {
         new = function()
            return { setCallback = function(self, fn) pendingHandler = fn; return self end }
         end,
      },
      new = function()
         local view = chain({ updates = {}, handler = pendingHandler })
         function view:html(page) self.page = page; return self end
         function view:evaluateJavaScript(js) table.insert(self.updates, js); return self end
         function view:delete() self.deleted = true end
         -- Posts a message from this popup's page, as the page's JavaScript would.
         function view:post(body) self.handler({ body = body }) end
         table.insert(stub.popups, view)
         return view
      end,
   },
   pasteboard = {
      changeCount = function() return stub.changeCount end,
      setContents = function(text) table.insert(stub.pasted, text) end,
      writeObjects = function(image) table.insert(stub.pasted, image.data); return true end,
   },
   timer = {
      secondsSinceEpoch = function() return 0 end,
      doEvery = function(_, fn)
         local t = chain({ stopped = false, stop = function(self) self.stopped = true end })
         t.fn = fn
         table.insert(stub.timers, t)
         return t
      end,
      doAfter = function(_, fn) fn() end,
   },
   chooser = {
      new = function(callback)
         local c = chain({ callback = callback })
         function c:choices(list) self.list = list; return self end
         table.insert(stub.choosers, c)
         return c
      end,
   },
   task = {
      new = function(path, done, stream, argv)
         local t = chain({ path = path, argv = argv, done = done, stream = stream })
         function t:isRunning() return false end
         table.insert(stub.tasks, t)
         return t
      end,
   },
}, { __index = function() return any end })

-- Runs every live timer once, as the clock ticking past its interval would.
function stub.tick()
   for _, t in ipairs(stub.timers) do
      if not t.stopped then t.fn() end
   end
end

-- Picks the menu row whose text is `label` in the last menu shown.
function stub.choose(label)
   local c = stub.choosers[#stub.choosers]
   for _, row in ipairs(c.list) do
      if row.text == label then return c.callback(row) end
   end
   error("no menu row " .. label)
end

-- The last update() the newest popup was sent, as the JSON of its arguments.
function stub.lastUpdate()
   local view = stub.popups[#stub.popups]
   return view.updates[#view.updates]
end
