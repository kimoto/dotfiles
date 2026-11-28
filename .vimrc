" The fallback editor for machines without nvim, so it loads no plugins: a
" plugin manager that clones from the network is what fails first exactly
" where a fallback is needed (offline, old git, a fresh box).

" Settings
set nocompatible
set smartindent
set number
set showcmd " 打ちかけのコマンドを右下に出す
set ruler " カーソルの行と桁を出す
set laststatus=2 " ステータスラインを常に出す
set statusline=[%n]%t\ %=%1*%m%*%r%{'['.(&fenc!=''?&fenc:&enc).':'.&ff.']'}[%<%{fnamemodify(getcwd(),':~')}]\ %-6(%l,%c%V%)\ %4P
set showmatch " 閉じ括弧を打つと、対応する開き括弧へ一瞬カーソルが飛ぶ
set nowrap " 長い行を折り返さない
set backspace=indent,eol,start " インデント・改行・挿入開始前の文字も BS で消せる
set expandtab " Tab キーでタブ文字でなく空白を入れる
set smartcase " 検索語に大文字があるときだけ大文字小文字を区別する
set mouse=a " マウスでスクロール・選択できる
set ttymouse=xterm2 " ドラッグも端末から受け取る
set incsearch " 検索語を打つそばから当たる所へ飛ぶ
set ignorecase " 検索で大文字小文字を区別しない
set hlsearch " 検索に当たった所を全部色付けする
set scrolloff=5 " カーソルの上下に常に5行見せる
set nomodeline " ファイル内の vim: 設定行を読まない
set wildmenu " : コマンドの Tab 補完で候補を一覧に出す
set hidden " 保存していないバッファを残したまま別のファイルへ移れる
set sidescroll=1 " 横スクロールを1桁ずつにする
set ambiwidth=double " ○ や ※ を全角幅で扱い、カーソルがずれない
set display+=lastline " 画面に入りきらない最後の行も @ にせず途中まで出す
set tabstop=4 " タブ文字を4桁で表示し、Tab キーも4桁ぶん空白を入れる
set tags=$HOME/tags,./tags,./TAGS,tags,TAGS

" バックアップとスワップは ~/tmp に置き、編集中のディレクトリを汚さない
set backup
set backupdir=~/tmp
set directory=~/tmp

" 閉じて開き直しても undo できる
if has('persistent_undo')
	set undofile
	set undodir=./.vimundo,~/.vim/undo
endif

" netrwの閲覧履歴(~/.vim/.netrwhist)を書き出さない
let g:netrw_dirhistmax = 0

" 文字コードは UTF-8
set termencoding=utf8
set encoding=utf8

syntax enable
set background=dark
filetype plugin indent on
highlight Normal ctermbg=NONE guibg=NONE

" 保存時の表示状態を残し、次に開くと同じ位置・折りたたみで開く
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
" mm で保存、qq で閉じる
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
