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
set completeopt=longest,menuone

set splitbelow
set splitright

set novisualbell       " No blinking .
set noerrorbells       " No noise.
set autoread
set viminfo^=!
set display+=lastline
set list
set listchars=tab:>\ ,trail:-,extends:>,precedes:<,nbsp:+

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

" The Silver Searcher
if executable('ag')
  " Use ag over grep
  set grepprg=ag\ --nogroup\ --nocolor

  " Use ag in CtrlP for listing files. Lightning fast and respects .gitignore
  let g:ctrlp_user_command = 'ag %s -l --nocolor -g "" --ignore "*.png" --ignore "*.jpg" --ignore "*.svg"'
  let g:ctrlp_lazy_update  = 350

  " ag is fast enough that CtrlP doesn't need to cache
  let g:ctrlp_use_caching = 0
endif

if filereadable(expand('~/.vim_bundles'))
  source ~/.vim_bundles
endif

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
  autocmd FileType ruby,eruby setlocal iskeyword+=?

  autocmd! BufReadPost,BufWritePost * Neomake
  autocmd ColorScheme * hi link NeomakeWarning SpellBad
augroup END

runtime macros/matchit.vim
nnoremap <F5> :GundoToggle<CR>
noremap <C-s> <esc>:w<cr>
vmap <Enter> <Plug>(EasyAlign)
" quick access buffer stuff
nnoremap gn :bn<cr>
nnoremap gp :bp<cr>
nnoremap gd :Bdelete<cr>
nnoremap gs :CtrlPBuffer<cr>

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

" Default to rspec on initial startup
let g:test#last_command = 'rspec'
let g:test#last_position = { 'file': 'test_spec.rb' }
let test#strategy = 'dispatch'

call camelcasemotion#CreateMotionMappings(',')

" reverse semicolon and colon
nnoremap ; :
nnoremap : ;
vnoremap ; :
vnoremap : ;

" bind K to grep word under cursor
nnoremap K :grep! "\b<C-R><C-W>\b"<CR>:cw<CR>


set background=dark
colorscheme solarized
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_ruby_checkers=['mri', 'rubocop']
let g:syntastic_slim_checkers=['slimrb', 'slim_lint']
let g:syntastic_javascript_checkers=['eslint']
let g:syntastic_typescript_tsc_fname = ''
" let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

let g:ctrlp_match_func = { 'match': 'pymatcher#PyMatch' }

let g:ycm_key_list_select_completion=['<C-n>', '<Down>']
let g:ycm_key_list_previous_completion=['<C-p>', '<Up>']
let g:ycm_collect_identifiers_from_tags_files = 1
let g:ycm_seed_identifiers_with_syntax = 1
let g:ycm_server_python_interpreter='/usr/bin/python'
let g:rubycomplete_rails = 1
let g:ycm_rust_src_path='/home/jon/.rust-src'

nnoremap <leader>gf :YcmCompleter GoTo<CR>

let g:UltiSnipsExpandTrigger="<Tab>"
let g:UltiSnipsJumpForwardTrigger="<Tab>"
let g:UltiSnipsJumpBackwardTrigger="<S-Tab>"

let g:splitjoin_ruby_curly_braces=0
let g:splitjoin_ruby_hanging_args=0

syntax on
filetype on
filetype plugin        on
filetype indent        on
