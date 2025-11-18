-- ref: https://qiita.com/naoya@github/items/81027083aeb70b309c14

-- ===== Utility functions =====
local function keyCode(key, modifiers)
   modifiers = modifiers or {}
   return function()
      hs.eventtap.event.newKeyEvent(modifiers, string.lower(key), true):post()
      hs.timer.usleep(1000)
      hs.eventtap.event.newKeyEvent(modifiers, string.lower(key), false):post()
   end
end

-- remapKey: mods, key, action, [opts]
-- opts:
--   onlyFor = {"AppName1", "AppName2"}  ← 指定アプリのみ有効
--   exceptFor = {"AppName1"}            ← 指定アプリ以外で有効
local function remapKey(modifiers, key, action, opts)
   hs.hotkey.bind(modifiers, key,
      function()
         local app = hs.application.frontmostApplication()
         local name = app and app:name() or ""

         if opts and opts.onlyFor then
            -- 指定アプリ限定
            for _, target in ipairs(opts.onlyFor) do
               if name == target then action(); return end
            end
            hs.eventtap.keyStroke(modifiers, key)
            return
         elseif opts and opts.exceptFor then
            -- 指定アプリを除外
            for _, ex in ipairs(opts.exceptFor) do
               if name == ex then return end
            end
         end

         -- デフォルト動作
         action()
      end,
      nil,
      function() -- repeat時
         local app = hs.application.frontmostApplication()
         local name = app and app:name() or ""

         if opts and opts.onlyFor then
            for _, target in ipairs(opts.onlyFor) do
               if name == target then action(); return end
            end
            hs.eventtap.keyStroke(modifiers, key)
            return
         elseif opts and opts.exceptFor then
            for _, ex in ipairs(opts.exceptFor) do
               if name == ex then return end
            end
         end

         action()
      end
   )
end

local function disableAllHotkeys()
   for _, v in pairs(hs.hotkey.getHotkeys()) do
      v["_hk"]:disable()
   end
end

local function enableAllHotkeys()
   for _, v in pairs(hs.hotkey.getHotkeys()) do
      v["_hk"]:enable()
   end
end

-- ===== App watcher =====
local function handleGlobalAppEvent(name, event, app)
   if event == hs.application.watcher.activated then
      if name ~= "Ghostty" then
         enableAllHotkeys()
      else
         disableAllHotkeys()
      end
   end
end

appsWatcher = hs.application.watcher.new(handleGlobalAppEvent)
appsWatcher:start()

-- ===== Global Emacs-style remaps =====
remapKey({"alt"}, "b", keyCode("left", {"alt"}))
remapKey({"alt"}, "f", keyCode("right", {"alt"}))
remapKey({"ctrl"}, "w", keyCode("delete", {"alt"}))
remapKey({'ctrl'}, "/", keyCode("z", {"cmd"}))

-- ===== Vivaldi限定 remaps =====
remapKey({"ctrl"}, "n", keyCode("down"), { onlyFor = {"Vivaldi"} })
remapKey({"ctrl"}, "p", keyCode("up"), { onlyFor = {"Vivaldi"} })
