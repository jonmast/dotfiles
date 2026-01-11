return {
  {
    "zbirenbaum/copilot.lua",
    event = "InsertEnter",
    cmd = "Copilot",
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
    }
  },
  {
    "hrsh7th/nvim-cmp",
    version = false,
    event = "InsertEnter",
    dependencies = {
      'neovim/nvim-lspconfig',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
      'hrsh7th/cmp-nvim-lsp-signature-help',
      {
        "zbirenbaum/copilot-cmp",
        opts = {}
      }
    },
    opts = function()
      local cmp = require('cmp')

      vim.cmd.highlight({ 'CmpGhostText', 'guifg=#808080', 'ctermfg=244' })

      local has_words_before = function()
        if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then return false end
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
      end

      return {
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
          { name = "copilot" },
        }, {
          { name = 'buffer' },
          { name = 'nvim_lsp_signature_help' }
        }),
        experimental = {
          ghost_text = {
            hl_group = 'CmpGhostText',
          },
        },
      }
    end
  },
  'petertriho/cmp-git',

  {
    'neovim/nvim-lspconfig',
    dependencies = {
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
    },
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup()

      vim.lsp.config('*', {
        capabilities = vim.tbl_deep_extend(
          'force',
          vim.lsp.protocol.make_client_capabilities(),
          require('cmp_nvim_lsp').default_capabilities()
        )
      })


      vim.lsp.config('graphql', { filetypes = { 'typescript' } })
      vim.lsp.enable({
        'eslint',
        'graphql',
        'jsonls',
        'prismals',
        'rust_analyzer',
        'tsgo',
        'vimls',
        'yamlls',
      })
    end
  },
}
