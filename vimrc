set rtp^=/usr/share/vim/vimfiles/

" testing coc extensions
" set rtp^=~/dev/coc-dev/coc-rust-analyzer
" let g:coc_node_args = ['--nolazy', '--inspect-brk=6045']

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

inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

nnoremap <silent> gh :call CocActionAsync('doHover')<CR>
inoremap <silent><expr> <c-space> coc#refresh()
" inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm()
"                               \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

let g:endwise_no_mappings = 1
inoremap <silent><expr> <cr> pumvisible() ? "\<C-y>\<c-r>=EndwiseDiscretionary()\<CR>" 
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>\<c-r>=EndwiseDiscretionary()\<CR>"


" Use `[g` and `]g` to navigate diagnostics
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

nmap <leader>rn <Plug>(coc-rename)

" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" autofix
nmap <leader>qf <Plug>(coc-fix-current)

nmap <leader>ca <Plug>(coc-codeaction-cursor)
vmap <leader>ca <Plug>(coc-codeaction-selected)

" Map function and class text objects
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
omap ic <Plug>(coc-classobj-i)
xmap ac <Plug>(coc-classobj-a)
omap ac <Plug>(coc-classobj-a)

let g:coc_global_extensions = [
\  'coc-rust-analyzer',
\  'coc-css',
\  'coc-dictionary',
\  'coc-json',
\  'coc-solargraph',
\  'coc-syntax',
\  'coc-tsserver',
\  'coc-tslint-plugin',
\  'coc-vetur',
\  'coc-ultisnips',
\  'coc-vimlsp',
\  'coc-git',
\  'coc-python',
\  'coc-diagnostic',
\  'coc-stylelint',
\  'coc-pairs',
\  'coc-prettier'
\]
" \  'coc-eslint',

let g:UltiSnipsExpandTrigger = "<c-u>"
let g:UltiSnipsJumpForwardTrigger = "<c-j>"
let g:UltiSnipsJumpBackwardTrigger = "<c-k>"
let g:UltiSnipsRemoveSelectModeMappings = 0

let g:gundo_prefer_python3 = 1

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

  autocmd FileType go setlocal nolist

  autocmd BufReadPost quickfix map <buffer> <MiddleMouse> gx
  autocmd BufReadPost quickfix map <buffer> gX /tmp\/screenshot<CR>gx

  " Use ruby highlighting for Workarea decorators
  autocmd BufNewFile,BufRead *.decorator set filetype=ruby

  autocmd BufNewFile,BufRead *.env set filetype=sh.env

  " Folds
  " autocmd Syntax haml setlocal foldmethod=indent
  " autocmd Syntax haml normal zR

  autocmd FileType php setlocal commentstring=//%s

  " Turn off annoying shellcheck for dotenv files
  autocmd BufNewFile,BufRead .env let b:coc_diagnostic_disable=1
augroup END

nnoremap <F5> :GundoToggle<CR>
noremap <C-s> <esc>:w<cr>
vmap <Enter> <Plug>(EasyAlign)

nnoremap <Leader>e :e <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <Leader>h :nohl<CR>
nnoremap <Leader>v :tabe ~/.vimrc<CR>
nnoremap <Leader>w :w<CR>

"Git shortcuts
nnoremap <leader>gs :Git<cr>
nnoremap <leader>ga :Git add
nnoremap <leader>gp :Gpush<cr>
nnoremap <leader>gc :Gcommit -v<cr>
nnoremap <leader>gc :tab :Git commit -v<cr>
nnoremap <leader>gq :silent! !git add -A<cr>:tab :Git commit -v<cr>
nnoremap <leader>gb :Git blame<cr>
nnoremap <leader>gf :GBrowse<cr>

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

" Typescript support
let g:test#javascript#mocha#file_pattern = '\v.\.test\.(ts|js|tsx|jsx)$'
let test#javascript#mocha#executable='npm test -- '

let g:dispatch_compilers = { 'bin/spinach': 'cucumber' }

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

" Shortcut for restarting invoker server
command! OR split | terminal oxidux restart

command! MN tabe my-notes.md

" Ask which tag to jump to when there is more than one match
" nnoremap <C-]> g<C-]>

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

" Auto-format rust code after save
let g:rustfmt_autosave = 1
let g:rustfmt_fail_silently = 1 " Don't display errors, coc handles that

" Use 2 spaces instead of 4 for indenting multiline list items
let g:vim_markdown_new_list_item_indent = 2

let g:matchup_matchparen_offscreen = {'method': 'popup'}

filetype on
filetype plugin        on
filetype indent        on
syntax on

lua <<EOF
require 'nvim-treesitter.configs'.setup {
  ensure_installed = "maintained",
  highlight = {
    enable = true,
  },
  matchup = {
    enable = true,
  },
}

require('telescope').load_extension('coc')
require('telescope').load_extension('frecency')

require 'telescope.init'.setup {
  defaults = {
    file_sorter = require('frecency_sorter').frecency_sorter,
    mappings = {
      i = {
        ["<C-p>"] = require('telescope.actions').cycle_history_prev,
        ["<C-n>"] = require('telescope.actions').cycle_history_next,
        ["<C-k>"] = require('telescope.actions').move_selection_previous,
        ["<C-j>"] = require('telescope.actions').move_selection_next,
      },
    }
  },
  extensions = {
    frecency = {
      default_workspace = ':CWD:'
    }
  }
}

-- require('telescope').load_extension('fzf')
EOF
