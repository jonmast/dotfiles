return {
  {
    "alexghergh/nvim-tmux-navigation",
    keys = {
      {
        "<C-h>",
        "<Cmd>NvimTmuxNavigateLeft<cr>",
        desc = "Navigate left"
      },
      {
        "<C-j>",
        "<Cmd>NvimTmuxNavigateDown<cr>",
        desc = "Navigate down"
      },
      {
        "<C-k>",
        "<Cmd>NvimTmuxNavigateUp<cr>",
        desc = "Navigate up"
      },
      {
        "<C-l>",
        "<Cmd>NvimTmuxNavigateRight<cr>",
        desc = "Navigate right"
      },
    },
    config = true,
  },
  {
    'bkad/CamelCaseMotion',
    config = function()
      vim.call('camelcasemotion#CreateMotionMappings', ',')
    end
  },
  'sheerun/vim-polyglot',
  'AndrewRadev/splitjoin.vim',
  'editorconfig/editorconfig-vim',
  'andymass/vim-matchup',
  'mfussenegger/nvim-dap',
  {
    'windwp/nvim-autopairs',
    opts = {
      map_cr = false
    }
  },
  'pantharshit00/vim-prisma',
}
