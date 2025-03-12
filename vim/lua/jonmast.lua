-- globals vim
local dap = require('dap')

dap.adapters.lldb = {
  type = 'executable',
  command = '/usr/bin/lldb-vscode',
  name = 'lldb',
}

dap.configurations.cpp = {
  {
    name = 'Treesitter',
    type = 'lldb',
    request = 'launch',
    program = '/usr/bin/tree-sitter',
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = { 'test' },
  },
  {
    name = 'Launch',
    type = 'lldb',
    request = 'launch',
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = {},
  },
}

-- Use CPP config for Rust and C as well
dap.configurations.c = dap.configurations.cpp
dap.configurations.rust = dap.configurations.cpp

require 'nvim-treesitter.configs'.setup {
  -- ensure_installed = "all",
  ignore_install = { "r", "godotResource", "scala" },
  highlight = {
    enable = true,
  },
  matchup = {
    enable = true,
  },
  playground = {
    enable = true,
  },
  textobjects = {
    select = {
      enable = true,
      -- Automatically jump forward to textobj, similar to targets.vim
      lookahead = true,

      keymaps = {
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
      },
    },
  },
}

require 'telescope'.setup {
  defaults = {
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
      auto_validate = false
    }
  }
}

require('telescope').load_extension('frecency')

require("nvim-autopairs").setup { map_cr = false }
require("oil").setup({
  keymaps = {
    ["<C-h>"] = { "actions.select", opts = { horizontal = true }, desc = "Open the entry in a horizontal split" }
  }
})
vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })

-- local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
-- if not (vim.uv or vim.loop).fs_stat(lazypath) then
--   vim.fn.system({
--     "git",
--     "clone",
--     "--filter=blob:none",
--     "https://github.com/folke/lazy.nvim.git",
--     "--branch=stable", -- latest stable release
--     lazypath,
--   })
-- end
-- vim.opt.rtp:prepend(lazypath)
--
-- require("lazy").setup({
--   {
--     "vhyrro/luarocks.nvim",
--     priority = 1000,
--     config = true,
--   },
--   {
--     "nvim-neorg/neorg",
--     dependencies = { "luarocks.nvim" },
--     version = "*",
--     config = function()
--       require("neorg").setup {
--         load = {
--           ["core.defaults"] = {},
--           ["core.concealer"] = {},
--           ["core.dirman"] = {
--             config = {
--               workspaces = {
--                 notes = "~/notes",
--               },
--               default_workspace = "notes",
--             },
--           },
--         },
--       }
--
--       vim.wo.foldlevel = 99
--       vim.wo.conceallevel = 2
--     end,
--   }
-- })

require("copilot").setup({
  -- Disable opts handled by cmp
  suggestion = { enabled = false },
  panel = { enabled = false },
})
require("copilot_cmp").setup()

local has_words_before = function()
  if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then return false end
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
end

-- Set up nvim-cmp.
local cmp = require 'cmp'

cmp.setup({
  snippet = {
    expand = function(args)
      vim.snippet.expand(args.body) -- For native neovim snippets (Neovim v0.10+)
    end,
  },
  window = {
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.abort(),
    ['<CR>'] = cmp.mapping.confirm({ select = false }),
    ["<Tab>"] = vim.schedule_wrap(function(fallback)
      if cmp.visible() and has_words_before() then
        cmp.confirm({ select = true })
      else
        fallback()
      end
    end),
  }),
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
  }, {
    { name = "copilot" },
    { name = 'buffer' },
    { name = 'nvim_lsp_signature_help' }
  }),
  -- preselect = cmp.PreselectMode.None,
  experimental = {
    ghost_text = {
      hl_group = 'CmpGhostText',
    },
  },
})

-- hi def CmpGhostText guifg=#808080 ctermfg=244
vim.cmd.highlight({ 'CmpGhostText', 'guifg=#808080', 'ctermfg=244' })

cmp.setup.filetype('gitcommit', {
  sources = cmp.config.sources({
    { name = 'git' },
  }, {
    { name = 'buffer' },
  })
})
require("cmp_git").setup()

-- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline({ '/', '?' }, {
  mapping = cmp.mapping.preset.cmdline(),
  sources = {
    { name = 'buffer' }
  }
})

-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline(':', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = cmp.config.sources({
    { name = 'path' }
  }, {
    { name = 'cmdline' }
  }),
  matching = { disallow_symbol_nonprefix_matching = false }
})

-- Autoinstall LSP servers. MUST come before lsp init
require("mason").setup()
require("mason-lspconfig").setup()

-- Set up lspconfig.
local lspconfig_defaults = require('lspconfig').util.default_config
lspconfig_defaults.capabilities = vim.tbl_deep_extend(
  'force',
  lspconfig_defaults.capabilities,
  require('cmp_nvim_lsp').default_capabilities()
)

require 'typescript-tools'.setup {}
-- require'lspconfig'.ts_ls.setup{} -- Putting this first so it has priority in code actions
require 'lspconfig'.eslint.setup {}
require 'lspconfig'.graphql.setup { filetypes = { 'typescript' } }
require 'lspconfig'.jsonls.setup {}
require 'lspconfig'.lua_ls.setup {
  on_init = function(client)
    if client.workspace_folders then
      local path = client.workspace_folders[1].name
      if path ~= vim.fn.stdpath('config') and (vim.loop.fs_stat(path .. '/.luarc.json') or vim.loop.fs_stat(path .. '/.luarc.jsonc')) then
        return
      end
    end

    client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
      runtime = {
        version = 'LuaJIT'
      },
      -- Make the server aware of Neovim runtime files
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME
          -- Depending on the usage, you might want to add additional paths here.
          -- "${3rd}/luv/library"
          -- "${3rd}/busted/library",
        }
      }
    })
  end,
  settings = {
    Lua = {}
  }
}
require 'lspconfig'.prismals.setup {}
require 'lspconfig'.rust_analyzer.setup {}
require 'lspconfig'.vimls.setup {}

-- TODO: git

vim.api.nvim_create_augroup('LspFormat', { clear = true })
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local opts = { noremap = true, silent = true }
    local buffer = args.buf

    vim.keymap.set('n', 'gh', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
    vim.keymap.set("n", "<leader>vd", '<cmd>lua vim.diagnostic.open_float()<cr>', opts)
    vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
    vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)
    vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>', opts)
    vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)
    vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', opts)
    vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)
    vim.keymap.set('n', '<leader>rn', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
    vim.keymap.set({ 'n', 'v' }, '<leader>ca', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)

    -- Typesript files
    if vim.bo.filetype == 'typescript' or vim.bo.filetype == 'typescriptreact' then
      vim.keymap.set('n', '<leader>rf', '<cmd>lua vim.lsp.buf.formatting()<cr>', opts)
    end

    -- Format the current buffer on save
    vim.api.nvim_create_autocmd('BufWritePre', {
      buffer = args.buf,
      group = 'LspFormat',
      callback = function()
        local conform_fmt = require('conform').list_formatters_to_run(buffer)

        -- Skip lsp format if we have a conform formatter
        if #conform_fmt <= 0 then
          local clients = vim.lsp.get_clients({ bufnr = buffer })
          for _, client in ipairs(clients) do
            if client.supports_method('textDocument/formatting') then
              vim.lsp.buf.format({ bufnr = buffer })
              break -- Stop after first formatting client
            end
          end
        end
      end,
    })
  end,
})

require("conform").setup({
  formatters_by_ft = {
    -- Conform will run the first available formatter
    typescript = { "prettierd", "prettier", stop_after_first = true },
    typescriptreact = { "prettierd", "prettier", stop_after_first = true },
    javascript = { "prettierd", "prettier", stop_after_first = true },
    json = { "prettierd", "prettier", stop_after_first = true },
  },
  format_on_save = {
    timeout_ms = 500,
  },
})


require("noice").setup()
