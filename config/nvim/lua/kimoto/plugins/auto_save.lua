-- ModeChanged is deliberately absent: with it, S in normal mode stops working.
require('auto-save').setup({
  trigger_events = { 'InsertLeave', 'BufLeave', 'FocusLost' },
})
