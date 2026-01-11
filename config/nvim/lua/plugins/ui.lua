return {
  {
    'akinsho/bufferline.nvim',
    version = "*",
    opts = {
      options = {
        mode = "tabs",
      }
    },
    dependencies = 'nvim-tree/nvim-web-devicons',
  },
  {
    "rcarriga/nvim-notify",
    opts = {
      background_colour = "#000000"
    },
    keys = {
      {
        "<leader>cc",
        function()
          require("notify").dismiss({ silent = true, pending = true })
        end,
        desc = "Clear notifications"
      },
    },
  },
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    -- @type require'noice'.Config
    opts = {
      lsp = {
        hover = {
          silent = true,
        }
      }
    },
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    }
  },
  'stevearc/dressing.nvim',
}
