"= vimrc 
set nocompatible " 非互換モード
set background=light " カラーテーマを変更
set number " 行番号を表示する
set showcmd " 入力したコマンドをステータスラインに表示
set ruler " 位置情報を表示
set laststatus=2 " ステータスラインを表示
"set statusline=%<%f\ %m%r%h%w%{'['.(&fenc!=''?&fenc:&enc).']['.&ff.']'}%=%l,%c%V%8P
set statusline=[%n]%t\ %=%1*%m%*%r%{'['.(&fenc!=''?&fenc:&enc).':'.&ff.']'}[%<%{fnamemodify(getcwd(),':~')}]\ %-6(%l,%c%V%)\ %4P
set smartindent " 自動インデント
set showmatch " 対応する括弧を強調表示
set nowrap " 長い行を折り返さない
set backspace=indent,eol,start " バックスペースの挙動
set expandtab " タブではなく適切な数の空白を使う
set smartcase " 大文字小文字を無視して検索
set shiftwidth=2
set softtabstop=2
set mouse=a
set ttymouse=xterm2

" バックアップファイルを作成する
set backup
set backupdir=~/tmp
set directory=~/tmp

" 日本語設定
set termencoding=utf8
set encoding=utf8

" シンタックスカラー表示を有効にする
syntax on
"colorscheme desert

" ファイルタイプごとのプラグインを有効にする
filetype on
filetype plugin on
filetype plugin indent on
filetype indent on

"set rtp+=~/.vim/bundle/vundle/
"call vundle#rc()

"Bundle 'L9'
"Bundle 'gmarik/vundle'
"Bundle 'rstacruz/sparkup', {'rtp': 'vim/'}
"Bundle 'FuzzyFinder'
"Bundle 'tpope/vim-fugitive'
"Bundle 'lokaltog/vim-easymotion'
"Bundle 'FuzzyFinder'
"Bundle 'rails.vim'
"Bundle 'git://git.wincent.com/command-t.git'
"Bundle 'Shougo/neocomplcache'
"Bundle 'Shogo/unite.vim'
"Bundle 'scrooloose/nerdcommenter'
"Bundle 'thinca/vim-puickrun'
"Bundle 'thinca/vim-ref'
"Bundle 'kana/vim-fakeclip'
"Bundle 'Shougo/vimproc'
"Bundle 'Shougo/vimshell'

" 前回開いた編集個所を表示する
au BufWritePost * mkview
autocmd BufReadPost * loadview

" autocomplpop無効化
"let g:acp_enableAtStartup = 0

" neocomplcacheの設定
let g:neocomplcache_enable_at_startup = 0
"let g:neocomplcache_enable_smart_case = 1
"let g:neocomplcache_enable_camel_case_completion = 1
"let g:neocomplcache_enable_underbar_completion = 1
"let g:neocomplcache_min_syntax_length = 3
"let g:neocomplcache_enable_auto_select = 1
"let g:neocomplcache_lock_buffer_name_pattern = *ku*’

" cursorline表示する
"autocmd InsertEnter * set nocul
"autocmd InsertLeave * set cul

"set cursorline
"set nocursorline
"highlight CursorLine cterm=reverse,standout ctermbg=6

" コマンドモードで Emacs キーバインド
cmap <C-A> <Home>
cmap <C-F> <Right>
cmap <C-B> <Left>
cmap <C-D> <Delete>
cmap <Esc>b <S-Left>
cmap <Esc>f <S-Right>

map <C-N> <C-X><C-N>

set incsearch " インクリメンタルサーチ
set ignorecase " 検索時に大文字小文字区別しない
set hlsearch " マッチした単語をカラー表示
set autoindent
set scrolloff=5 " 上下から、指定した行数に達したら自動スクロール
set nomodeline " モードライン機能の無効化
set wildmenu " 強化されたコマンドライン補完を使用
set hidden " バッファを保存しないで他のファイルを開けるようにする
set sidescroll=1 " 水平スクロール時の文字数
set mouse=a " enable mouse
set ttymouse=xterm2

" タブが対応する空白の数
set tabstop=2
" ,e で編集しているファイルを実行する
function! ShebangExecute()
  let m = matchlist(getline(1), '#!\(.*\)')
  if(len(m) > 2)
    execute '!'. m[1] . ' %'
  else
    execute '!' &ft ' %'
  endif
endfunction
nmap ,e :call ShebangExecute()<CR>

" for php
let php_sql_query=1
let php_htmlInStrings=1
let php_noShortTags=0
let php_folding=1

" lustyexplorer.vim
let g:LustyExplorerSuppressRubyWarning = 1
nmap fz :FilesystemExplorer<CR>

" yankring.vim
if has('viminfo')
  set vi^=!
endif

let g:yankring_history_dir = '~/tmp/'

" fuzzyfinder.vim
"nmap ff :FuzzyFinderFile<CR>
nmap ff :FuzzyFinderMruFile<CR>
"nmap bb :FuzzyFinderBuffer<CR>
let g:FuzzyFinder_Migemo = 0

" for debug
nmap ss :source %<CR>

" VCSCommand
nmap sdf :VCSVimDiff<CR>
nmap sci :VCSCommit<CR>
nmap sup :VCSUpdate<CR>
nmap sad :VCSAdd<CR>
nmap sst :VCSStatus<CR>

" save
nmap mm :w<CR>
nmap me :w<CR> :call ShebangExecute()<CR>
nmap qq :q<CR>
nmap qw :wq<CR>
nmap mq :wq<CR>

" refe.vim
let g:RefeCommand = $HOME . "/utils/refe_utf8.sh"

" matchit.vim
source $VIMRUNTIME/macros/matchit.vim

" emacs風のウインドウ制御
nnoremap <silent> <C-x>1 :only<CR>
nnoremap <silent> <C-x>2 :sp<CR>
nnoremap <silent> <C-x>3 :vsp<CR>

" 矢印キーでバッファ切替制御
"nnoremap <silent> <Right> :bn<CR>
"nnoremap <silent> <Left> :bp<CR>

" minibufexpl
let g:miniBufExplMapWindowNavVim = 1
let g:miniBufExplMapWindowNavArrows = 1
let g:miniBufExplMapCTabSwitchBuffs = 1

" vim-ruby
let g:rubycomplete_buffer_loading = 1
let g:rubycomplete_classes_in_global = 1
let g:rubycomplete_rails = 1

" 自動保存
"set autowrite
" set autowriteall
"autocmd CursorHold *  wall
"autocmd CursorHoldI *  wall
"set updatecount=100
"set updatetime=200

" omnifunc
autocmd FileType javascript set omnifunc=javascriptcomplete#CompleteJS
autocmd FileType php set omnifunc=phpcomplete#CompletePHP
autocmd FileType python set omnifunc=pythoncomplete#Complete
autocmd FileType html set omnifunc=htmlcomplete#CompleteTags
autocmd FileType css set omnifunc=csscomplete#CompleteCSS
autocmd FileType xml set omnifunc=xmlcomplete#CompleteTags
autocmd FileType perl set omnifunc=perlcomplete#CompletePERL
autocmd FileType c set omnifunc=ccomplete#Complete
autocmd FileType ruby,eruby set omnifunc=rubycomplete#Complete
let g:rubycomplete_rails = 1
let g:rubycomplete_classes_in_global = 1
"let g:rubycomplete_include_object = 1
"let g:rubycomplete_include_objectspace = 1

call pathogen#runtime_append_all_bundles()

" load local file
let local_vimrc_path = $HOME . "/.vimrc.local"
if(file_readable(local_vimrc_path))
  execute "source " . local_vimrc_path
endif

if v:version >= 700
  set runtimepath+=$HOME/.vim/fullsets
endif
