"===========================================================
"  ____    ____  __  .___  ___. .______        ______ 
"  \   \  /   / |  | |   \/   | |   _  \      /      |
"   \   \/   /  |  | |  \  /  | |  |_)  |    |  ,----'
"    \      /   |  | |  |\/|  | |      /     |  |     
"  __ \    /    |  | |  |  |  | |  |\  \----.|  `----.
" (__) \__/     |__| |__|  |__| | _| `._____| \______|
"
" Author: kimoto
"===========================================================

" =======================
"   汎用設定
" =======================
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
"set nowrap " 長い行を折り返さない
set wrap " 長い行を折り返さない
set backspace=indent,eol,start " バックスペースの挙動
set expandtab " タブではなく適切な数の空白を使う
set smartcase " 大文字小文字を無視して検索
set shiftwidth=2
set softtabstop=2
set mouse=a " マウス機能(wheel scroll)を有効に
set ttymouse=xterm2 " 同上
set incsearch " インクリメンタルサーチ
set ignorecase " 検索時に大文字小文字区別しない
set hlsearch " マッチした単語をカラー表示
set autoindent
set scrolloff=5 " 上下から、指定した行数に達したら自動スクロール
set nomodeline " モードライン機能の無効化
set wildmenu " 強化されたコマンドライン補完を使用
set hidden " バッファを保存しないで他のファイルを開けるようにする
set sidescroll=1 " 水平スクロール時の文字数
set ambiwidth=double "特殊な文字でもカーソル位置がずれないように
set display+=lastline "最後の行を可能な限り最後まで表示

" Tab入力したときに入力される空白の数
set tabstop=2

" バックアップファイルを作成する
set backup
set backupdir=~/tmp
set directory=~/tmp

" 日本語設定
set termencoding=utf8
set encoding=utf8

" カーソルのある行を強調する
set cursorline

" シンタックスカラー表示を有効にする
syntax on
"colorscheme desert

" ファイルタイプごとのプラグインを有効にする
filetype on
filetype plugin on
filetype plugin indent on
filetype indent on

" 前回編集していた場所に自動でジャンプするように
au BufWritePost * mkview
autocmd BufReadPost * loadview

" 一定の時間ごとに自動保存
"set autowrite
" set autowriteall
"autocmd CursorHold *  wall
"autocmd CursorHoldI *  wall
"set updatecount=100
"set updatetime=200

" 賢い自動補完機能設定
autocmd FileType javascript set omnifunc=javascriptcomplete#CompleteJS
autocmd FileType php set omnifunc=phpcomplete#CompletePHP
autocmd FileType python set omnifunc=pythoncomplete#Complete
autocmd FileType html set omnifunc=htmlcomplete#CompleteTags
autocmd FileType css set omnifunc=csscomplete#CompleteCSS
autocmd FileType xml set omnifunc=xmlcomplete#CompleteTags
autocmd FileType perl set omnifunc=perlcomplete#CompletePERL
autocmd FileType c set omnifunc=ccomplete#Complete
autocmd FileType ruby,eruby set omnifunc=rubycomplete#Complete

" template
autocmd BufNewFile *.pl 0r /home/kimoto/.vim/template/perl.txt
autocmd BufNewFile *.rb 0r /home/kimoto/.vim/template/ruby.txt

" ===============================
"   プラグインの読み込みと設定
" ===============================
" pathogen.vimによって管理されているプラグインを一括読み込み
call pathogen#runtime_append_all_bundles()

" matchit.vim
" %による対応する括弧に移動機能の拡張版
" コンテキストにふさわしい移動の仕方をするようになる
source $VIMRUNTIME/macros/matchit.vim

" autocomplpop無効化
let g:acp_enableAtStartup = 1

" neocomplcacheの設定
let g:neocomplcache_enable_at_startup = 0
"let g:neocomplcache_enable_smart_case = 1
"let g:neocomplcache_enable_camel_case_completion = 1
"let g:neocomplcache_enable_underbar_completion = 1
"let g:neocomplcache_min_syntax_length = 3
"let g:neocomplcache_enble_auto_select = 1

" for php
let php_sql_query=1
let php_htmlInStrings=1
let php_noShortTags=0
let php_folding=1

" yankring.vim
let g:yankring_history_dir = '~/tmp/'

" minibufexpl
let g:miniBufExplMapWindowNavVim = 1
let g:miniBufExplMapWindowNavArrows = 1
let g:miniBufExplMapCTabSwitchBuffs = 1

" vim-ruby
let g:rubycomplete_buffer_loading = 1
let g:rubycomplete_classes_in_global = 1
let g:rubycomplete_rails = 1

" vim-ref.vim
"nmap <F12> :<C-u>Ref alc<Space>
let g:ref_alc_start_linenumber = 10
let g:ref_alc_encoding = 'UTF-8'

" fuzzy finder
let g:fuf_modesDisable = ['mrucmd']
let g:fuf_file_exclude = '\v\~$|\.(o|exe|bak|swp|gif|jpg|png)$|(^|[/\\])\.(hg|git|bzr)($|[/\\])'
let g:fuf_mrufile_exclude = '\v\~$|\.bak$|\.swp|\.howm$|\.(gif|jpg|png)$'
let g:fuf_mrufile_maxItem = 10000
let g:fuf_enumeratingLimit = 20
let g:fuf_keyPreview = '<C-]>'
let g:fuf_previewHeight = 0

" rails.vim
let g:rubycomplete_rails = 1
let g:rubycomplete_classes_in_global = 1
"let g:rubycomplete_include_object = 1
"let g:rubycomplete_include_objectspace = 1

" ===============================
"   スクリプト定義
" ===============================
" Comment or uncomment lines from mark a to mark b.
function! CommentMark(docomment, a, b)
  if !exists('b:comment')
    let b:comment = CommentStr() . ' '
  endif
  if a:docomment
    exe "normal! '" . a:a . "_\<C-V>'" . a:b . 'I' . b:comment
  else
    exe "'".a:a.",'".a:b . 's/^\(\s*\)' . escape(b:comment,'/') . '/\1/e'
  endif
endfunction

" Comment lines in marks set by g@ operator.
function! DoCommentOp(type)
  call CommentMark(1, '[', ']')
endfunction

" Uncomment lines in marks set by g@ operator.
function! UnCommentOp(type)
  call CommentMark(0, '[', ']')
endfunction

" Return string used to comment line for current filetype.
function! CommentStr()
  if &ft == 'cpp' || &ft == 'java' || &ft == 'javascript'
    return '//'
  elseif &ft == 'vim'
    return '"'
  elseif &ft == 'python' || &ft == 'perl' || &ft == 'sh' || &ft == 'R' || &ft == 'ruby'
    return '#'
  elseif &ft == 'lisp'
    return ';'
  endif
  return ''
endfunction

" =================================
"   KeyBind(nmap / imap / smap)
" =================================
" #1. normal mode bindings
map <C-N> <C-X><C-N>

" normalモードで Emacs KeyBind
cmap <C-A> <Home>
cmap <C-F> <Right>
cmap <C-B> <Left>
cmap <C-D> <Delete>
cmap <Esc>b <S-Left>
cmap <Esc>f <S-Right>

" 保存/終了関係
nmap mm :w<CR>
nmap qq :q<CR>

" VCSCommand
nmap sdf :VCSVimDiff<CR>
nmap sci :VCSCommit<CR>
nmap sup :VCSUpdate<CR>
nmap sad :VCSAdd<CR>
nmap sst :VCSStatus<CR>

" 開いてるバッファを自動インデントする
nmap <F3> :FufLine<CR>
nmap <F5> :QuickRun<CR>
nmap <F6> gg=G<CR><C-o><C-o>
nmap <F7> :q<CR>
nmap <F8> :q!<CR>

" fuzzyfinder (簡易にファイルを検索するための仕組み)
"nmap bG :FufFile <C-r>=expand('%:~:.')[:-1-len(expand('%:~:.:t'))]<CR><CR>
"nmap gb :FufFile **/<CR>
"nmap bq :FufQuickfix<CR>
nmap ff :FufMruFile<CR>
"nmap bb :FufBuffer<CR>
" bbだと左方向単語移動するときにtypoするのでキツイ

" emacs風のウインドウ制御
nnoremap <silent> <C-x>1 :only<CR>
nnoremap <silent> <C-x>2 :sp<CR>
nnoremap <silent> <C-x>3 :vsp<CR>

" 矢印キーでバッファ切替制御
"nnoremap <silent> <Right> :bn<CR>
"nnoremap <silent> <Left> :bp<CR>

" 次のバッファに切り替え
nmap <C-T> :bn<CR>

" #2. insert mode bindings
" <C-K> にsnippetsの展開をマッピング
imap <C-K> <Plug>(neocomplcache_snippets_expand)
smap <C-K> <Plug>(neocomplcache_snippets_expand)
imap <C-O> <Plug>(neocomplcache_snippets_jump)
smap <C-O> <Plug>(neocomplcache_snippets_jump)

" 以下neocomplcacheに書いてあった推奨設定をコピペ
"inoremap <expr><CR>  neocomplcache#smart_close_popup() . "\<CR>"
"inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
"inoremap <expr><C-h> neocomplcache#smart_close_popup()."\<C-h>"
"inoremap <expr><BS> neocomplcache#smart_close_popup()."\<C-h>"
"inoremap <expr><C-y>  neocomplcache#close_popup()
"inoremap <expr><C-e>  neocomplcache#cancel_popup()

" コメントアウト、アンコメント機能
"nnoremap <Leader>c <Esc>:set opfunc=DoCommentOp<CR>g@
"nmap <Spate> <Esc>:set opfunc=DoCommentOp<CR>g@
"nmap <C-Space> <Esc>:set opfunc=UnCommentOp<CR>
"vnoremap <Leader>c <Esc>:call CommentMark(1,'<','>')<CR>
"vnoremap <Leader>C <Esc>:call CommentMark(0,'<','>')<CR>

" load local config file
let local_vimrc_path = $HOME . "/.vimrc.local"
if(file_readable(local_vimrc_path))
  execute "source " . local_vimrc_path
endif
