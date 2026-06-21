return {
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = { 'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
      {
        "nvim-telescope/telescope-frecency.nvim",
        version = "*",
        config = function()
          require("telescope").load_extension "frecency"
        end,
      },
      {
        "debugloop/telescope-undo.nvim",
        config = function()
          require("telescope").load_extension "undo"
        end,
      },
    },
    lazy = true,
    cmd = "Telescope",
    opts = {
      defaults = {
        mappings = {
          i = {
            ["<C-p>"] = "cycle_history_prev",
            ["<C-n>"] = "cycle_history_next",
            ["<C-k>"] = "move_selection_previous",
            ["<C-j>"] = "move_selection_next"
          },
        }
      },
      extensions = {
        frecency = {
          auto_validate = false
        }
      }
    }
  },
}
