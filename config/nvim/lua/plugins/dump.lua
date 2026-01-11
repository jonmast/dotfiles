return {
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
