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

nmap <F5> :QuickRun<CR>

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
let g:acp_enableAtStartup = 0

" neocomplcacheの設定
let g:neocomplcache_enable_at_startup = 1
let g:neocomplcache_enable_smart_case = 1
let g:neocomplcache_enable_camel_case_completion = 1
let g:neocomplcache_enable_underbar_completion = 1
let g:neocomplcache_min_syntax_length = 3
let g:neocomplcache_enable_auto_select = 1
"let g:neocomplcache_lock_buffer_name_pattern = *ku*’
"let g:neocomplcache_snippets_dir = '~/.vim/snippets'

" Plugin key-mappings.
" <C-K> にマッピング
imap <C-K> <Plug>(neocomplcache_snippets_expand)
smap <C-K> <Plug>(neocomplcache_snippets_expand)
imap <C-O> <Plug>(neocomplcache_snippets_jump)
smap <C-O> <Plug>(neocomplcache_snippets_jump)

" SuperTab like snippets behavior.
"imap <expr><TAB> neocomplcache#sources#snippets_complete#expandable() ? "\<Plug>(neocomplcache_snippets_expand)" : pumvisible() ? "\<C-n>" : "\<TAB>"

" Recommended key-mappings.
" <CR>: close popup and save indent.
inoremap <expr><CR>  neocomplcache#smart_close_popup() . "\<CR>"
" <TAB>: completion.
inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
" <C-h>, <BS>: close popup and delete backword char.
inoremap <expr><C-h> neocomplcache#smart_close_popup()."\<C-h>"
inoremap <expr><BS> neocomplcache#smart_close_popup()."\<C-h>"
inoremap <expr><C-y>  neocomplcache#close_popup()
inoremap <expr><C-e>  neocomplcache#cancel_popup()

" cursorline表示する
"autocmd InsertEnter * set nocul
"autocmd InsertLeave * set cul

"set cursorline
"set nocursorline
"highlight CursorLine cterm=reverse,standout ctermbg=6
call pathogen#runtime_append_all_bundles()

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
"nmap ff :FuzzyFinderMruFile<CR>
"nmap bb :FuzzyFinderBuffer<CR>
"let g:FuzzyFinder_Migemo = 0

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
"

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

nmap bg :FufBuffer<CR>
nmap bG :FufFile <C-r>=expand('%:~:.')[:-1-len(expand('%:~:.:t'))]<CR><CR>
nmap gb :FufFile **/<CR>
"nmap bb :FufMruFile<CR>
nmap bq :FufQuickfix<CR>

" fuzzyfinderで行検索
nmap bl :FufLine<CR>
nmap ff :FufMruFile<CR>

" jptemplate
"let g:jpTemplateKey '<C-A>'
" neocomplcache
"let g:NeoComplCache_EnableAtStartup = 1
" 大文字小文字を区別する
"let g:NeoComplCache_SmartCase = 1
"" キャメルケース補完を有効にする
"let g:NeoComplCache_EnableCamelCaseCompletion = 1
"" アンダーバー補完を有効にする
"let g:NeoComplCache_EnableUnderbarCompletion = 1
"" シンタックスファイルの補完対象キーワードとする最小の長さ
"let g:NeoComplCache_MinSyntaxLength = 3
"" プラグイン毎の補完関数を呼び出す文字数
"let g:NeoComplCache_PluginCompletionLength = {
"  \ 'keyword_complete'  : 2,
"  \ 'syntax_complete'   : 2
"  \ }
"
nnoremap <silent> <C-]> :FufTag! <C-r>=expand('<cword>')<CR><CR> 

" comment out
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

"nnoremap <Leader>c <Esc>:set opfunc=DoCommentOp<CR>g@
nmap <Space> <Esc>:set opfunc=DoCommentOp<CR>g@
nmap <C-Space> <Esc>:set opfunc=UnCommentOp<CR>
vnoremap <Leader>c <Esc>:call CommentMark(1,'<','>')<CR>
vnoremap <Leader>C <Esc>:call CommentMark(0,'<','>')<CR>

" 開いてるバッファを自動インデントする
map <F6> gg=G<CR><C-o><C-o>
map <F7> :q<CR>
map <F8> :q!<CR>

" normal mode enter to change line
"noremap <CR> o<ESC>

" load local file
let local_vimrc_path = $HOME . "/.vimrc.local"
if(file_readable(local_vimrc_path))
  execute "source " . local_vimrc_path
endif

"if v:version >= 700
"  set runtimepath+=$HOME/.vim/fullsets
"endif

