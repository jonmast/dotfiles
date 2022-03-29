local ext = require("telescope._extensions")
local frecency_db = require("telescope._extensions.frecency.db_client")

local fzf = ext.manager.fzf

local function db_score(self, entry)
  for _, file_entry in ipairs(self.state.frecency) do
    local filepath = entry.cwd .. "/" .. string.gsub(entry.value, "^%./", "")
    if file_entry.filename == filepath then
      return file_entry.score
    end
  end

  return 0
end

local function frecency_score(self, prompt, line, entry)
  if prompt == nil or prompt == "" then
    return 9999 - db_score(self, entry)
  end

  local default_score = self.default_scoring_function(self, prompt, line, entry)

  if default_score ~= -1 then
    local frecency = db_score(self, entry)
    -- print("Entry: " .. entry.value .. " FZF: " .. default_score .. " CSTM: " .. frecency)

    return default_score / ((frecency + 1) * 0.5)
  end

  return default_score
end

local function frecency_start(self, prompt)
  self.default_start(self, prompt)

  if not self.state.frecency then
    self.state.frecency = frecency_db.get_file_scores()
  end
end

local frecency_sorter = function(opts)
  local fzf_sorter = fzf.native_fzf_sorter()

  fzf_sorter.default_scoring_function = fzf_sorter.scoring_function
  fzf_sorter.default_start = fzf_sorter.start

  fzf_sorter.scoring_function = frecency_score
  fzf_sorter.start = frecency_start

  return fzf_sorter
end

return {
  frecency_sorter = frecency_sorter,
}
