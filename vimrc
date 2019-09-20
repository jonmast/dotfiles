set rtp^=/usr/share/vim/vimfiles/
set hlsearch           " highlight searches
set incsearch          " do incremental searching
set showmatch          " jump to matching brackets
set ignorecase         " Case insensitive search
set smartcase          " Case sensitive if search contains capitals
set mouse=a
set laststatus=2
set noshowmode
set showcmd            "show command as you type
set wildmode=longest,list,full
set wildmenu
set wildignorecase "case insensitive filename completion
set wrap               "dont wrap lines
set linebreak          "wrap lines at convenient points
set number
set relativenumber
set guitablabel=%t
set ts=2               " Tabs are 2 spaces
set bs=indent,eol,start
set shiftwidth=2       " Tabs under smart indent
set formatoptions+=j
set autoindent
set smarttab
set expandtab
"vertical/horizontal scroll off settings
set scrolloff=3
set sidescrolloff=7
set sidescroll=1

set history=2000        " Number of things to remember in history.
set ttimeout
set ttimeoutlen=10     " Time to wait after ESC (default causes an annoying delay)
set completeopt=menuone
set updatetime=300

set splitbelow
set splitright

set novisualbell       " No blinking .
set noerrorbells       " No noise.
set autoread
set viminfo^=!
set display+=lastline
set list
set listchars=tab:>\ ,trail:·,extends:>,precedes:<,nbsp:+
set tags^=./.git/tags;

set inccommand=nosplit

" gvim specific
set mousehide  " Hide mouse after chars typed
if v:version >= 703
    "undo settings
    set undodir=~/.vim/undofiles
    set undofile

endif
if has("gui_running")
  " GUI is running or is about to start.
  " Maximize gvim window.
  set lines=999 columns=999
endif

" RipGrep
if executable('rg')
  " Use ag over grep
  set grepprg=rg\ --vimgrep\ --no-heading
  set grepformat=%f:%l:%c:%m,%f:%l:%m

  " Use ag in CtrlP for listing files. Lightning fast and respects .gitignore
  let g:ctrlp_user_command = 'rg --color=never -g"!vendor/cache/*" --files %s'

  " ag is fast enough that CtrlP doesn't need to cache
  let g:ctrlp_use_caching = 0

  " Ack.vim adds some niceties for searching
  let g:ackprg = 'rg --vimgrep --no-heading'
endif

if filereadable(expand('~/.vim_bundles'))
  source ~/.vim_bundles
endif

set shortmess+=c

inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

nnoremap <silent> gh :call CocAction('doHover')<CR>
inoremap <silent><expr> <c-space> coc#refresh()

let g:coc_global_extensions = [
\  'coc-css',
\  'coc-dictionary',
\  'coc-json',
\  'coc-rls',
\  'coc-solargraph',
\  'coc-syntax',
\  'coc-tsserver',
\  'coc-tslint-plugin',
\  'coc-vetur',
\  'coc-ultisnips',
\  'coc-vimlsp',
\  'coc-git',
\  'coc-python',
\]

let g:lexima_enable_basic_rules = 0

inoremap <expr> <Plug>LeximaCR lexima#expand('<LT>CR>', 'i')

let g:UltiSnipsExpandTrigger = "<c-u>"
let g:UltiSnipsJumpForwardTrigger = "<c-j>"
let g:UltiSnipsJumpBackwardTrigger = "<c-k>"
let g:UltiSnipsRemoveSelectModeMappings = 0

augroup vimrcEx
  autocmd!

  " For HTML
  autocmd FileType html set omnifunc=htmlcomplete#CompleteTags

  autocmd VimResized * :silent! wincmd =
  " When editing a file, always jump to the last known cursor position.
  " Don't do it for commit messages, when the position is invalid, or when
  " inside an event handler (happens when dropping a file on gvim).
  autocmd BufReadPost *
    \ if &ft != 'gitcommit' && line("'\"") > 0 && line("'\"") <= line("$") |
    \   exe "normal g`\"" |
    \ endif
  autocmd BufRead,BufNewFile *.md set filetype=markdown
  autocmd FileType markdown setlocal spell
  autocmd BufRead,BufNewFile *.md setlocal textwidth=80
  autocmd FileType gitcommit setlocal spell
  " Allow stylesheets to autocomplete hyphenated words
  autocmd FileType css,scss,sass setlocal iskeyword+=-
  " Question marks are valid in ruby metods
  " The question mark causes issues with tag jumping in vim-ruby, disabling
  " for now
  " autocmd FileType ruby,eruby setlocal iskeyword+=?

  " Autoclose invoker reload split
  autocmd TermClose term://*:ir q

  autocmd FileType go setlocal nolist

  autocmd BufReadPost quickfix map <buffer> <MiddleMouse> gx
augroup END

runtime macros/matchit.vim
nnoremap <F5> :GundoToggle<CR>
noremap <C-s> <esc>:w<cr>
vmap <Enter> <Plug>(EasyAlign)

let mapleader = ' '
nnoremap <leader>y :CtrlPBuffer<cr>
nnoremap <leader>f :CtrlPMRUFiles<cr>
nnoremap <leader>rm :CtrlPModels<cr>
nnoremap <leader>rc :CtrlPControllers<cr>
nnoremap <leader>rv :CtrlPViews<cr>
nnoremap <Leader>e :e <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <Leader>h :nohl<CR>
nnoremap <Leader>v :tabe ~/.vimrc<CR>
nnoremap <Leader>w :w<CR>

"Git shortcuts
nnoremap <leader>gs :Gstatus<cr>
nnoremap <leader>ga :Git add
nnoremap <leader>gp :Gpush<cr>
nnoremap <leader>gc :Gcommit -v<cr>
nnoremap <leader>gc :Gcommit -v<cr>
nnoremap <leader>gq :silent! !git add -A<cr>:Gcommit -v<cr>
nnoremap <leader>gb :Gblame<cr>

" System clipboard mappings
vmap <Leader>y "+y
nnoremap <Leader>p "+p
nnoremap <Leader>P "+P
" Make middle click copy work as expected
vmap <LeftRelease> "*ygv

" test mappings
nnoremap <Leader>t :TestFile<CR>
nnoremap <Leader>s :TestNearest<CR>
nnoremap <Leader>l :TestLast<CR>
nnoremap <Leader>a :TestSuite<CR>

let test#strategy = 'dispatch'
" Don't try to guess test file
let g:test#no_alternate = 1
let test#ruby#cucumber#executable='bin/spinach'

let g:dispatch_compilers = { 'bin/spinach': 'cucumber' }

call camelcasemotion#CreateMotionMappings(',')

" reverse semicolon and colon
nnoremap ; :
nnoremap : ;
vnoremap ; :
vnoremap : ;

" bind K to grep word under cursor
nnoremap K :Ack! "\b<C-R><C-W>\b"<CR>:cw<CR>

" Shortcut for restarting invoker server
command! OR split | terminal oxidux restart

" Open corresponding file in SF and diff it
command! SFdiff vs ../sellect_frontend/% | windo diffthis

command! MN tabe my-notes.md

" Ask which tag to jump to when there is more than one match
" nnoremap <C-]> g<C-]>

set cursorline
set background=dark
set termguicolors
let g:solarized_term_italics=1

" colorscheme solarized8_dark
colorscheme gruvbox

let g:ctrlp_match_func = { 'match': 'pymatcher#PyMatch' }

let g:splitjoin_ruby_curly_braces=0
let g:splitjoin_ruby_hanging_args=0

let g:localvimrc_persistent=1

let g:ale_sign_column_always = 1
let g:airline#extensions#ale#enabled = 1
let g:ale_linters = {
\   'php': ['hack', 'langserver', 'php', 'phpmd', 'phpstan'],
\   'javascript': ['standard'],
\   'typescript': [],
\}

" Auto-format rust code after save
let g:rustfmt_autosave = 1
let g:rustfmt_fail_silently = 1 " Don't display errors, ALE handles that

" Use 2 spaces instead of 4 for indenting multiline list items
let g:vim_markdown_new_list_item_indent = 2

syntax on
filetype on
filetype plugin        on
filetype indent        on
