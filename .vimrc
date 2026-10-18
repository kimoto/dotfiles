" The fallback editor for machines without nvim, so it loads no plugins: a
" plugin manager that clones from the network is what fails first exactly
" where a fallback is needed (offline, old git, a fresh box).

" Settings
set nocompatible
set smartindent
set number
set showcmd " 入力したコマンドをステータスラインに表示
set ruler " 位置情報を表示
set laststatus=2 " ステータスラインを表示
set statusline=[%n]%t\ %=%1*%m%*%r%{'['.(&fenc!=''?&fenc:&enc).':'.&ff.']'}[%<%{fnamemodify(getcwd(),':~')}]\ %-6(%l,%c%V%)\ %4P
set showmatch " 対応する括弧を強調表示
set nowrap " 長い行を折り返さない
set backspace=indent,eol,start " バックスペースの挙動
set expandtab " タブではなく適切な数の空白を使う
set smartcase " 大文字小文字を無視して検索
set mouse=a " マウス機能(wheel scroll)を有効に
set ttymouse=xterm2 " 同上
set incsearch " インクリメンタルサーチ
set ignorecase " 検索時に大文字小文字区別しない
set hlsearch " マッチした単語をカラー表示
set scrolloff=5 " 上下から、指定した行数に達したら自動スクロール
set nomodeline " モードライン機能の無効化
set wildmenu " 強化されたコマンドライン補完を使用
set hidden " バッファを保存しないで他のファイルを開けるようにする
set sidescroll=1 " 水平スクロール時の文字数
set ambiwidth=double "特殊な文字でもカーソル位置がずれないように
set display+=lastline "最後の行を可能な限り最後まで表示
" Tab入力したときに入力される空白の数
set tabstop=4
set tags=$HOME/tags,./tags,./TAGS,tags,TAGS

" バックアップファイルを作成する
set backup
set backupdir=~/tmp
set directory=~/tmp

" Vimを終了してもUndo
if has('persistent_undo')
	set undofile
	set undodir=./.vimundo,~/.vim/undo
endif

" netrwの閲覧履歴(~/.vim/.netrwhist)を書き出さない
let g:netrw_dirhistmax = 0

" 日本語設定
set termencoding=utf8
set encoding=utf8

syntax enable
set background=dark
filetype plugin indent on
highlight Normal ctermbg=NONE guibg=NONE

" 前回編集していた場所に自動でジャンプするように
au BufWritePost * mkview
autocmd BufReadPost * loadview

" 言語ごとの初期テンプレートファイル
autocmd BufNewFile *.pl 0r $HOME/.vim/template/perl.txt
autocmd BufNewFile *.rb 0r $HOME/.vim/template/ruby.txt
autocmd BufNewFile *.html 0r $HOME/.vim/template/html.txt
autocmd BufNewFile *.js 0r $HOME/.vim/template/js.txt

" ファイルタイプごとのインデント
autocmd FileType ruby,text set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType html,javascript,perl set expandtab tabstop=4 shiftwidth=4 softtabstop=4
au BufRead,BufNewFile nginx.conf set ft=nginx
au BufNewFile,BufRead *.psgi set filetype=perl

" 行末スペースの可視化
augroup HighlightTrailingSpaces
	autocmd!
	autocmd VimEnter,WinEnter,ColorScheme * highlight TrailingSpaces term=underline guibg=Red ctermbg=Red
	autocmd VimEnter,WinEnter * match TrailingSpaces /\s\+$/
augroup END

" key maps
" 保存/終了関係
nmap mm :w<CR>
nmap qq :q<CR>

" emacs風のウインドウ制御
nnoremap <silent> <C-x>1 :only<CR>
nnoremap <silent> <C-x>2 :sp<CR>
nnoremap <silent> <C-x>3 :vsp<CR>

" 次のバッファに切り替え
nmap <C-T> :bn<CR>

" 補完候補が出ているときは <TAB> で次の候補へ
inoremap <expr><TAB> pumvisible() ? "\<C-n>" : "\<TAB>"
