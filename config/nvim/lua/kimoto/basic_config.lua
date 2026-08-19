local opt = vim.opt
opt.ambiwidth = 'double'

opt.autoindent = true
opt.smartindent = true
opt.cursorline = true

opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2

opt.expandtab = true

opt.relativenumber = true
opt.number = true
opt.termguicolors = true

opt.smartcase = true
opt.ignorecase = true

opt.scrolloff = 10 -- 上下から、指定した行数に達したら自動スクロール
opt.signcolumn = 'yes' --行数表示の横に余白を追加
opt.wrap = true

opt.undofile = true -- Vimを終了してもUndo (undodir: stdpath('state')/undo, auto-created)

opt.breakindent = true -- 折り返した行のインデントを揃える (wrap = true 前提)

opt.updatetime = 250 -- CursorHold の待ち時間。既定 4000ms では gitsigns の行 blame が出ない
opt.timeoutlen = 400 -- マッピングの続きを待つ時間 (既定 1000ms)

-- ヤンクをシステムのクリップボードと共有する。yanky の system_clipboard は
-- 逆向き (クリップボード → ring) の同期なので、これが無いと nvim の外へ出せない。
opt.clipboard = 'unnamedplus'

opt.inccommand = 'split' -- :s の置換結果をプレビューする
opt.splitright = true -- 縦分割は右へ
opt.splitbelow = true -- 横分割は下へ
opt.confirm = true -- 未保存のまま閉じようとしたら E37 で弾かずに聞く

-- nvim-cmp が前提にする形。noselect なので <CR> が勝手に確定しない
opt.completeopt = 'menu,menuone,noselect'
