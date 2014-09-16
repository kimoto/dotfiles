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
"set list "いろいろ表示
"set listchars=tab:>\ ,
" Tab入力したときに入力される空白の数
"set tabstop=2
"set shiftwidth=2
"set softtabstop=2

" バックアップファイルを作成する
set backup
set backupdir=~/tmp
set directory=~/tmp

" 日本語設定
set termencoding=utf8
set encoding=utf8

" カーソルのある行を強調する
" set cursorline

" 前回編集していた場所に自動でジャンプするように
au BufWritePost * mkview
autocmd BufReadPost * loadview

" 言語ごとの初期テンプレートファイル
autocmd BufNewFile *.pl 0r $HOME/.vim/template/perl.txt
autocmd BufNewFile *.rb 0r $HOME/.vim/template/ruby.txt
autocmd BufNewFile *.html 0r $HOME/.vim/template/html.txt
autocmd BufNewFile *.js 0r $HOME/.vim/template/js.txt

" key maps
" 保存/終了関係
nmap mm :w<CR>
nmap qq :q<CR>
nmap ff :Unite file<CR>
nmap fb :<C-u>Unite file_mru buffer<CR>

" emacs風のウインドウ制御
nnoremap <silent> <C-x>1 :only<CR>
nnoremap <silent> <C-x>2 :sp<CR>
nnoremap <silent> <C-x>3 :vsp<CR>
noremap!  

" 次のバッファに切り替え
nmap <C-T> :bn<CR>

" Neobundle bootstrap
if has('vim_starting')
	set nocompatible               " Be iMproved
	set runtimepath+=~/.vim/bundle/neobundle.vim/
endif
call neobundle#rc(expand('~/.vim/bundle/'))
NeoBundleFetch 'Shougo/neobundle.vim'

NeoBundle 'Shougo/neobundle.vim'
NeoBundle 'Shougo/vimproc', {
      \ 'build' : {
      \     'windows' : 'make -f make_mingw32.mak',
      \     'cygwin' : 'make -f make_cygwin.mak',
      \     'mac' : 'make -f make_mac.mak',
      \     'unix' : 'make -f make_unix.mak',
      \    },
      \ }
NeoBundle 'Shougo/vimshell'

" Unite
NeoBundle 'Shougo/unite.vim'
let g:unite_enable_start_insert=1

NeoBundle "Shougo/vimfiler.vim" "ref: http://d.hatena.ne.jp/h1mesuke/20100611/p1


"============================================
" Neocomplcache
"============================================
NeoBundle 'Shougo/neocomplcache'
let g:neocomplcache_enable_at_startup = 1
let g:neocomplcache_enable_smart_case = 1
let g:neocomplcache_min_syntax_length = 3

" Plugin key-mappings.
inoremap <expr><C-g>     neocomplcache#undo_completion()
inoremap <expr><C-l>     neocomplcache#complete_common_string()

" Define dictionary.
let g:neocomplcache_dictionary_filetype_lists = {
    \ 'default' : '',
    \ 'vimshell' : $HOME.'/.vimshell_hist',
    \ 'scheme' : $HOME.'/.gosh_completions'
        \ }

" Define keyword.
if !exists('g:neocomplcache_keyword_patterns')
    let g:neocomplcache_keyword_patterns = {}
endif
let g:neocomplcache_keyword_patterns['default'] = '\h\w*'

" Enable omni completion.
autocmd FileType css setlocal omnifunc=csscomplete#CompleteCSS
autocmd FileType html,markdown setlocal omnifunc=htmlcomplete#CompleteTags
autocmd FileType javascript setlocal omnifunc=javascriptcomplete#CompleteJS
autocmd FileType python setlocal omnifunc=pythoncomplete#Complete
" added
autocmd FileType xml setlocal omnifunc=xmlcomplete#CompleteTags
autocmd FileType css set omnifunc=csscomplete#CompleteCSS
autocmd FileType xml set omnifunc=xmlcomplete#CompleteTags
autocmd FileType perl set omnifunc=perlcomplete#CompletePERL
autocmd FileType c set omnifunc=ccomplete#Complete
autocmd FileType ruby,eruby set omnifunc=rubycomplete#Complete
au BufRead,BufNewFile nginx.conf set ft=nginx

" tabstop settings
autocmd FileType ruby set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType text set expandtab tabstop=2 shiftwidth=2 softtabstop=2
autocmd FileType html set expandtab tabstop=4 shiftwidth=4 softtabstop=4
autocmd FileType javascript set expandtab tabstop=4 shiftwidth=4 softtabstop=4
autocmd FileType perl set expandtab tabstop=4 shiftwidth=4 softtabstop=4
au BufNewFile,BufRead *.tx set filetype=tt2html
au BufNewFile,BufRead *.psgi set filetype=perl
"au BufNewFile,BufRead *.jshintrc set filetype=json
"au BufNewFile,BufRead *.jslintrc set filetype=json

" Recommended key-mappings.
" <CR>: close popup and save indent.
inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
function! s:my_cr_function()
  return neocomplcache#smart_close_popup() . "\<CR>"
  " For no inserting <CR> key.
  "return pumvisible() ? neocomplcache#close_popup() : "\<CR>"
endfunction
" <TAB>: completion.
inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
" <C-h>, <BS>: close popup and delete backword char.
inoremap <expr><C-h> neocomplcache#smart_close_popup()."\<C-h>"
inoremap <expr><BS> neocomplcache#smart_close_popup()."\<C-h>"
inoremap <expr><C-y>  neocomplcache#close_popup()
inoremap <expr><C-e>  neocomplcache#cancel_popup()

" Enable heavy omni completion.
if !exists('g:neocomplcache_omni_patterns')
  let g:neocomplcache_omni_patterns = {}
endif
let g:neocomplcache_omni_patterns.php = '[^. \t]->\h\w*\|\h\w*::'
let g:neocomplcache_omni_patterns.c = '[^.[:digit:] *\t]\%(\.\|->\)'
let g:neocomplcache_omni_patterns.cpp = '[^.[:digit:] *\t]\%(\.\|->\)\|\h\w*::'

" For perlomni.vim setting.
" https://github.com/c9s/perlomni.vim
let g:neocomplcache_omni_patterns.perl = '\h\w*->\h\w*\|\h\w*::'

NeoBundle 'Shougo/neosnippet'
NeoBundle 'Shougo/neosnippet-snippets'
" Plugin key-mappings.
imap <C-k>     <Plug>(neosnippet_expand_or_jump)
smap <C-k>     <Plug>(neosnippet_expand_or_jump)
xmap <C-k>     <Plug>(neosnippet_expand_target)
" SuperTab like snippets behavior.
imap <expr><TAB> neosnippet#expandable_or_jumpable() ?
\ "\<Plug>(neosnippet_expand_or_jump)"
\: pumvisible() ? "\<C-n>" : "\<TAB>"
smap <expr><TAB> neosnippet#expandable_or_jumpable() ?
\ "\<Plug>(neosnippet_expand_or_jump)"
\: "\<TAB>"
" For snippet_complete marker.
if has('conceal')
  set conceallevel=2 concealcursor=i
endif
" Enable snipMate compatibility feature.
let g:neosnippet#enable_snipmate_compatibility = 1
" Tell Neosnippet about the other snippets
let g:neosnippet#snippets_directory='~/.vim/bundle/vim-snippets/snippets'

NeoBundle 'altercation/vim-colors-solarized'
NeoBundle 'tpope/vim-rails', { 'autoload' : {
			\ 'filetypes' : ['haml', 'ruby', 'eruby'] }}
" rails.vim
let g:rubycomplete_rails = 1
let g:rubycomplete_classes_in_global = 1

"NeoBundle 'basyura/unite-rails'
NeoBundle 'vim-ruby/vim-ruby'
NeoBundle 'thinca/vim-ref'
NeoBundle 'thinca/vim-quickrun'
NeoBundle 'tpope/vim-endwise'
"NeoBundle 'git://github.com/tsukkee/unite-tag.git'
NeoBundle 'vim-scripts/ruby-matchit'
"NeoBundle 'yuku-t/vim-ref-ri'
"NeoBundle 'soh335/vim-ref-jquery'
"NeoBundle 'soh335/vim-ref-pman'
"NeoBundle 'mojako/ref-sources.vim'

NeoBundle 'vim-scripts/TT2-syntax'
NeoBundle 'vim-perl/vim-perl'

NeoBundle 'vim-scripts/YankRing.vim'
let g:yankring_history_dir = $HOME.'/tmp'

NeoBundle 'houtsnip/vim-emacscommandline'
NeoBundle 'Lokaltog/vim-powerline'
"NeoBundle 'airblade/vim-gitgutter'
NeoBundle 'tpope/vim-fugitive' " 重いのでやめた

"NeoBundle 'othree/html5.vim'
"NeoBundle 'pangloss/vim-javascript'
NeoBundle 'lukaszb/vim-web-indent'

"NeoBundle 'Lokaltog/vim-easymotion'
"nmap s <Plug>(easymotion-s2)
"
"NeoBundle "elzr/vim-json"

NeoBundle 'Yggdroot/indentLine'
let g:indentLine_faster = 1

"================================
" Syntax Check
"================================
"NeoBundle 'basyura/jslint.vim'
NeoBundle 'scrooloose/syntastic'
" jslint.vim
"function! s:javascript_filetype_settings()
"  autocmd BufLeave     <buffer> call jslint#clear()
"  autocmd BufWritePost <buffer> call jslint#check()
"  autocmd CursorMoved  <buffer> call jslint#message()
"endfunction
"autocmd FileType javascript call s:javascript_filetype_settings()

let g:syntastic_enable_signs = 1
let g:syntastic_auto_loc_list = 2
let g:syntastic_javascript_checkers = ["jshint"]
let g:syntastic_html_checkers = ["jshint"]
let g:syntastic_mode_map = { 'mode': 'passive',
                           \ 'active_filetypes': ['ruby', 'javascript', 'html'],
                           \ 'passive_filetypes': [] }
let g:syntastic_error_symbol = '✗'
let g:syntastic_warning_symbol = '!'

" Vimを終了してもUndo
if has('persistent_undo')
	set undofile
	set undodir=./.vimundo,~/.vim/undo
endif

" Solarized
syntax enable
set background=dark
let g:solarized_termcolors=256
filetype plugin indent on " Required!
colorscheme solarized

" 行末スペースの可視化
augroup HighlightTrailingSpaces
        autocmd!
        autocmd VimEnter,WinEnter,ColorScheme * highlight TrailingSpaces term=underline guibg=Red ctermbg=Red
        autocmd VimEnter,WinEnter * match TrailingSpaces /\s\+$/
augroup END

NeoBundleCheck
