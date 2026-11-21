-- Runs bin/tidy_to_drive.sh every hour, so documents left on the Desktop end
-- up filed in Drive and the rest in the Trash without anyone remembering to.
-- Why from Hammerspoon and the one-time setup: the header of that script.

-- ~/.hammerspoon is a symlink into the repo; the script sits beside it in bin/.
local REPO = hs.fs.pathToAbsolute(hs.configdir) .. "/.."
local SCRIPT = REPO .. "/bin/tidy_to_drive.sh"
local LOG = os.getenv("HOME") .. "/Library/Logs/dotfiles/tidy_to_drive.log"
local INTERVAL = 60 * 60
-- Past login, when the Desktop and the network are both up.
local FIRST_RUN_DELAY = 5 * 60

local function appendLog(text)
   if text == nil or text == "" then return end
   hs.fs.mkdir(os.getenv("HOME") .. "/Library/Logs/dotfiles")
   local f = io.open(LOG, "a")
   if f then
      f:write(text)
      f:close()
   end
end

-- A global: a task or timer only a local refers to can be collected mid-run.
tidyTask = nil

local function runTidy()
   if tidyTask and tidyTask:isRunning() then return end
   tidyTask = hs.task.new("/bin/bash", function(exitCode, stdout, stderr)
      appendLog(stdout)
      appendLog(stderr)
      -- The script's exit codes: 1 a failure (a file kept back, or a missing tool), 3
      -- left files it could not call for the owner to look at.
      local messages = {
         [1] = "片付けが止まったか、移せなかったファイルがあります。",
         [3] = "残すか迷うファイルがあります。Desktop に置いたままです。",
      }
      if exitCode ~= 0 then
         hs.notify.new({
            title = "Desktop の片付け",
            informativeText = (messages[exitCode] or "片付けが止まりました。") .. " ログ: " .. LOG,
         }):send()
      end
   end, { SCRIPT })
   local env = tidyTask:environment()
   -- Hammerspoon starts with launchd's bare PATH: no Homebrew (rclone), no
   -- ~/.local/bin (claude).
   env.PATH = os.getenv("HOME") .. "/.local/bin:/opt/homebrew/bin:/usr/local/bin:" .. (env.PATH or "/usr/bin:/bin")
   tidyTask:setEnvironment(env)
   tidyTask:start()
end

tidyTimer = hs.timer.doEvery(INTERVAL, runTidy)
tidyFirstRun = hs.timer.doAfter(FIRST_RUN_DELAY, runTidy)
