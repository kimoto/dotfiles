require'auto-save'.setup({
  trigger_events = {"InsertLeave", "BufLeave", "FocusLost"},
  --, "ModeChanged" これを有効にすると、ノーマルモード時のSが効かなくなる
  --{"InsertLeave", "TextChanged"},
})
