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
set completeopt=menuone,noinsert,noselect,preview
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
set foldmethod=syntax
set foldlevelstart=99
set hidden
let mapleader = ' '

if exists('&inccommand')
  set inccommand=nosplit
endif

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
  set grepprg=rg\ --vimgrep\ --no-heading
  set grepformat=%f:%l:%c:%m,%f:%l:%m

  " Ack.vim adds some niceties for searching
  let g:ackprg = 'rg --vimgrep --no-heading'
endif

if filereadable(expand('~/.vim_bundles'))
  source ~/.vim_bundles
endif

set shortmess+=c

let g:graphql_javascript_tags=['gql', 'graphql', '\/\* \?GraphQL \?\*\/ \?']

augroup vimrcEx
  autocmd!

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

  autocmd BufReadPost quickfix map <buffer> <MiddleMouse> gx
  autocmd BufReadPost quickfix map <buffer> gX /tmp\/screenshot<CR>gx

  " Use ruby highlighting for Workarea decorators
  autocmd BufNewFile,BufRead *.decorator set filetype=ruby

  autocmd BufNewFile,BufRead *.env set filetype=sh.env

  " Disable custom formatexpr from TS plugin which breaks gq
  " https://github.com/HerringtonDarkholme/yats.vim/issues/218#issuecomment-1092187718
  autocmd FileType typescript setlocal formatexpr=

  autocmd FileType yaml let b:copilot_enabled=v:true
augroup END

nnoremap <F5> :UndotreeToggle<CR>

nnoremap <Leader>e :e <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <silent> <Leader>h :nohl<CR>
nnoremap <Leader>vv :tabe ~/.vimrc<CR>
nnoremap <Leader>vl :tabe ~/.dotfiles/vim/lua/jonmast.lua<CR>
nnoremap <silent> <Leader>w :w<CR>
nnoremap <silent> <Leader>ii :TSToolsAddMissingImports<CR>

"Git shortcuts
nnoremap <leader>gs :Git<cr>
nnoremap <leader>ga :Git add
nnoremap <leader>gp :Gpush<cr>
nnoremap <leader>gc :Gcommit -v<cr>
nnoremap <leader>gc :tab :Git commit -v<cr>
nnoremap <leader>gq :silent! !git add -A<cr>:tab :Git commit -v<cr>
nnoremap <leader>gb :Git blame -M -C<cr>
nnoremap <leader>gf :GBrowse<cr>
vnoremap <leader>gf :GBrowse<cr>

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

let test#custom_runners = {'Ruby': ['rails_decorators']}

call camelcasemotion#CreateMotionMappings(',')

let g:projectionist_heuristics = {
  \ "package.json": {
    \ "**/__tests__/*.ts": { "alternate": "{}.ts"},
    \ "*.ts": { "alternate": "{dirname}/__tests__/{basename}.ts"}
    \ }
\ }

" reverse semicolon and colon
nnoremap ; :
nnoremap : ;
vnoremap ; :
vnoremap : ;

nnoremap <silent> <C-p> :Telescope find_files<CR>

" bind K to grep word under cursor
nnoremap K :Ack! "\b<C-R><C-W>\b"<CR>:cw<CR>

command! MN tabe my-notes.md

" nvim-dap keybinds
nnoremap <silent> <F5> <Cmd>lua require'dap'.continue()<CR>
nnoremap <silent> <F10> <Cmd>lua require'dap'.step_over()<CR>
nnoremap <silent> <F11> <Cmd>lua require'dap'.step_into()<CR>
nnoremap <silent> <F12> <Cmd>lua require'dap'.step_out()<CR>
nnoremap <silent> <Leader>b <Cmd>lua require'dap'.toggle_breakpoint()<CR>
nnoremap <silent> <Leader>B <Cmd>lua require'dap'.set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>
nnoremap <silent> <Leader>lp <Cmd>lua require'dap'.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))<CR>
nnoremap <silent> <Leader>dr <Cmd>lua require'dap'.repl.open()<CR>
nnoremap <silent> <Leader>dl <Cmd>lua require'dap'.run_last()<CR>

set cursorline
set termguicolors
set background=dark

colorscheme gruvbox

let g:fzf_history_dir = '~/.cache/fzf-history'

let g:splitjoin_ruby_curly_braces=0
let g:splitjoin_ruby_hanging_args=0
let g:ruby_indent_assignment_style='variable'

let g:localvimrc_persistent=1

set signcolumn=yes
set cmdheight=2

" Use 2 spaces instead of 4 for indenting multiline list items
let g:vim_markdown_new_list_item_indent = 2

let g:matchup_matchparen_offscreen = {'method': 'popup'}

filetype on
filetype plugin        on
filetype indent        on
syntax on

lua <<EOF
require('jonmast')
EOF
