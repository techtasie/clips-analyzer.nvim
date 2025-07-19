local M = {}
local parser = require('clips-analyzer.parser')

-- Global state
local state = {
  search_buf = nil,
  search_win = nil,
  detail_buf = nil,
  detail_win = nil,
  timeline_buf = nil,
  timeline_win = nil,
  current_facts = {},
  search_query = "",
  selected_fact = nil,
  selected_facts = {},  -- For multi-fact selection
  log_file = nil
}

-- Utility functions
local function create_floating_window(width_ratio, height_ratio, title)
  local width = math.floor(vim.o.columns * width_ratio)
  local height = math.floor(vim.o.lines * height_ratio)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center'
  })
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  return buf, win
end

local function close_window(win, buf)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

local function set_buffer_content(buf, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

local function highlight_search_results(buf, query)
  if query == "" then return end
  
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local start_pos = 1
    while true do
      local match_start, match_end = string.find(line:lower(), query:lower(), start_pos, true)
      if not match_start then break end
      
      vim.api.nvim_buf_add_highlight(buf, -1, 'Search', i - 1, match_start - 1, match_end)
      start_pos = match_end + 1
    end
  end
end

local function format_fact_for_display(fact)
  local status = fact.retracted and "[RETRACTED]" or "[ACTIVE]"
  local timestamp = string.format("[%s]", fact.timestamp)
  
  -- Ensure we show the actual fact content, not just the ID
  local content = fact.content or ""
  if content == "" then
    content = string.format("f-%d (no content)", fact.id)
  end
  
  -- Mark selected facts
  local selected_mark = ""
  if state.selected_facts[fact.id] then
    selected_mark = "★ "
  end
  
  return string.format("%s%s %s f-%-3d %s", selected_mark, timestamp, status, fact.id, content)
end

local function filter_facts(facts, query)
  if query == "" then return facts end
  
  -- Use the enhanced search from parser
  return parser.search_facts(facts, query, false)
end

local function update_search_results()
  if not state.search_buf then return end
  
  local filtered_facts = filter_facts(state.current_facts, state.search_query)
  
  local lines = {}
  table.insert(lines, "CLIPS Log Analyzer - Structured Search")
  table.insert(lines, string.format("Query: '%s' | Results: %d | File: %s", 
    state.search_query, #filtered_facts, state.log_file or "None"))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")
  
  -- Add search help if no query
  if state.search_query == "" then
    table.insert(lines, "Search Examples:")
    table.insert(lines, "  robot:ROBOT3        - Find facts where slot 'robot' contains 'ROBOT3'")
    table.insert(lines, "  state=WAITING       - Find facts where slot 'state' contains 'WAITING'")
    table.insert(lines, "  template:task       - Find all facts of template 'task'")
    table.insert(lines, "  :[task,worker,goal] - Find facts of multiple templates (a,b,c)")
    table.insert(lines, "  template:[a,b],gen46 - Find templates a,b that contain 'gen46'")
    table.insert(lines, "  fact:{template:task, state:!DONE} - Tasks never marked DONE")
    table.insert(lines, "  slot:name           - Find facts that have a 'name' slot")
    table.insert(lines, "  value:failed        - Find facts with any slot containing 'failed'")
    table.insert(lines, "  ROBOT3              - Simple text search")
    table.insert(lines, "")
    table.insert(lines, "Press / to start searching, ? for more help")
    table.insert(lines, "")
  end
  
  if #filtered_facts == 0 and state.search_query ~= "" then
    table.insert(lines, "No facts found matching your query.")
    table.insert(lines, "")
    table.insert(lines, "Try:")
    table.insert(lines, "  - Use 'slot:value' format for structured search")
    table.insert(lines, "  - Use 'template:name' to find facts by template")
    table.insert(lines, "  - Use simple text for basic search")
  else
    for _, fact in ipairs(filtered_facts) do
      table.insert(lines, format_fact_for_display(fact))
    end
  end
  
  table.insert(lines, "")
  
  -- Show selected facts info
  local selected_count = 0
  for _ in pairs(state.selected_facts) do
    selected_count = selected_count + 1
  end
  
  if selected_count > 0 then
    table.insert(lines, string.format("Selected: %d facts | Press <c> to view combined details | <x> to clear selection", selected_count))
  end
  
  table.insert(lines, "Controls: <Enter> Details | <Space> Select/Deselect | / Search | ? Help | <Esc> Close | <C-r> Refresh")
  
  set_buffer_content(state.search_buf, lines)
  highlight_search_results(state.search_buf, state.search_query)
end

local function show_fact_details(fact_id)
  local fact_history = {}
  for _, fact in ipairs(state.current_facts) do
    if fact.id == fact_id then
      table.insert(fact_history, fact)
    end
  end
  
  if #fact_history == 0 then
    vim.notify("No history found for fact f-" .. fact_id, vim.log.levels.WARN)
    return
  end
  
  -- Sort by line number to show chronological order
  table.sort(fact_history, function(a, b) return a.line_num < b.line_num end)
  
  if not state.detail_buf then
    state.detail_buf, state.detail_win = create_floating_window(0.8, 0.6, "Fact Details: f-" .. fact_id)
  end
  
  local lines = {}
  table.insert(lines, string.format("Fact History for f-%d", fact_id))
  table.insert(lines, string.rep("=", 60))
  table.insert(lines, "")
  
  -- Analyze fact modifications (when retraction and assertion happen at same time)
  local modifications = {}
  local i = 1
  while i <= #fact_history do
    local current = fact_history[i]
    local next_fact = fact_history[i + 1]
    
    if next_fact and current.retracted and not next_fact.retracted and 
       current.timestamp == next_fact.timestamp then
      -- This is a modification (retract + assert at same time)
      table.insert(modifications, {
        action = "MODIFIED",
        timestamp = current.timestamp,
        line_num = current.line_num,
        from_content = current.content,
        to_content = next_fact.content,
        is_modification = true
      })
      i = i + 2 -- Skip both retraction and assertion
    else
      -- Regular assertion or retraction
      table.insert(modifications, {
        action = current.retracted and "RETRACTED" or "ASSERTED",
        timestamp = current.timestamp,
        line_num = current.line_num,
        content = current.content,
        is_modification = false
      })
      i = i + 1
    end
  end
  
  for i, mod in ipairs(modifications) do
    table.insert(lines, string.format("%d. %s at %s (line %d)", 
      i, mod.action, mod.timestamp, mod.line_num))
    
    if mod.is_modification then
      -- Parse and display both versions for modifications in diff format
      local from_structure = parser.get_fact_structure({content = mod.from_content})
      local to_structure = parser.get_fact_structure({content = mod.to_content})
      
      -- Show diff-style changes
      if from_structure.template and to_structure.template then
        -- Compare slots and show only differences
        local all_slots = {}
        for slot, _ in pairs(from_structure.slots) do
          all_slots[slot] = true
        end
        for slot, _ in pairs(to_structure.slots) do
          all_slots[slot] = true
        end
        
        local has_changes = false
        for slot, _ in pairs(all_slots) do
          local from_val = from_structure.slots[slot]
          local to_val = to_structure.slots[slot]
          
          if from_val ~= to_val then
            has_changes = true
            if from_val and to_val then
              -- Value changed - preserve full values
              table.insert(lines, string.format("     %s: %s → %s", slot, from_val, to_val))
            elseif from_val then
              -- Slot removed
              table.insert(lines, string.format("     %s: %s → (removed)", slot, from_val))
            else
              -- Slot added
              table.insert(lines, string.format("     %s: (added) → %s", slot, to_val))
            end
          end
        end
        
        if not has_changes then
          table.insert(lines, "     (no slot changes - content may have been reformatted)")
        end
      else
        -- Fallback to raw content diff
        table.insert(lines, "   - %s", mod.from_content)
        table.insert(lines, "   + %s", mod.to_content)
      end
    else
      -- Parse and display single fact
      local structure = parser.get_fact_structure({content = mod.content})
      if structure.template then
        table.insert(lines, string.format("   Template: %s", structure.template))
        
        if next(structure.slots) then
          for slot, value in pairs(structure.slots) do
            if type(value) == "boolean" then
              table.insert(lines, string.format("     %s: %s", slot, value and "true" or "false"))
            else
              table.insert(lines, string.format("     %s: %s", slot, tostring(value)))
            end
          end
        else
          -- No slots found, show raw content
          table.insert(lines, string.format("   Raw Content: %s", mod.content))
        end
      else
        -- No template found, show the raw content
        if mod.content and mod.content ~= "" then
          table.insert(lines, string.format("   Content: %s", mod.content))
        else
          table.insert(lines, "   Content: (empty or unparsed)")
        end
      end
    end
    table.insert(lines, "")
  end
  
  table.insert(lines, "Controls: <Esc> Close | <t> Timeline | <s> Search similar | <Enter> Jump to line")
  
  set_buffer_content(state.detail_buf, lines)
  
  -- Set up keymaps for detail window
  local opts = { noremap = true, silent = true, buffer = state.detail_buf }
  vim.keymap.set('n', '<Esc>', function()
    close_window(state.detail_win, state.detail_buf)
    state.detail_win, state.detail_buf = nil, nil
  end, opts)
  
  vim.keymap.set('n', 't', function()
    M.show_fact_timeline(fact_id)
  end, opts)
  
  vim.keymap.set('n', 's', function()
    local latest_fact = fact_history[#fact_history]
    local structure = parser.get_fact_structure(latest_fact)
    if structure.template then
      -- Close the detail window
      close_window(state.detail_win, state.detail_buf)
      state.detail_win, state.detail_buf = nil, nil
      
      -- Notify user about the search they can perform
      vim.notify(string.format("Use ':ClipsSearch' and search for 'template:%s' to find similar facts", structure.template), vim.log.levels.INFO)
      
      -- Copy the search query to clipboard if available
      if vim.fn.has('clipboard') == 1 then
        vim.fn.setreg('+', "template:" .. structure.template)
        vim.notify("Search query copied to clipboard: template:" .. structure.template, vim.log.levels.INFO)
      end
    else
      vim.notify("Could not determine template for similar search", vim.log.levels.WARN)
    end
  end, opts)
  
  vim.keymap.set('n', '<Enter>', function()
    local line_idx = vim.api.nvim_win_get_cursor(state.detail_win)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.detail_buf, line_idx - 1, line_idx, false)[1]
    
    -- Extract line number from detail entry (look for pattern like "(line 123)")
    local line_num = string.match(line_content, "%(line (%d+)%)")
    if line_num and state.log_file then
      -- Close detail window and jump to original file
      close_window(state.detail_win, state.detail_buf)
      state.detail_win, state.detail_buf = nil, nil
      
      vim.cmd('edit ' .. state.log_file)
      vim.api.nvim_win_set_cursor(0, {tonumber(line_num), 0})
      vim.cmd('normal! zz')
      vim.notify(string.format("Jumped to line %s in %s", line_num, vim.fn.fnamemodify(state.log_file, ":t")), vim.log.levels.INFO)
    end
  end, opts)
end

local function show_combined_facts_details()
  local selected_fact_ids = {}
  for fact_id in pairs(state.selected_facts) do
    table.insert(selected_fact_ids, fact_id)
  end
  
  if #selected_fact_ids == 0 then
    vim.notify("No facts selected for combination", vim.log.levels.WARN)
    return
  end
  
  table.sort(selected_fact_ids)
  
  if not state.detail_buf then
    state.detail_buf, state.detail_win = create_floating_window(0.9, 0.8, string.format("Combined Facts (%d selected)", #selected_fact_ids))
  end
  
  local lines = {}
  table.insert(lines, string.format("Combined Analysis for %d Facts", #selected_fact_ids))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")
  
  -- Group facts by template for better organization
  local facts_by_template = {}
  for _, fact_id in ipairs(selected_fact_ids) do
    local fact_history = {}
    for _, fact in ipairs(state.current_facts) do
      if fact.id == fact_id then
        table.insert(fact_history, fact)
      end
    end
    
    if #fact_history > 0 then
      -- Get the latest version to determine template
      table.sort(fact_history, function(a, b) return a.line_num < b.line_num end)
      local latest_fact = fact_history[#fact_history]
      local structure = parser.get_fact_structure({content = latest_fact.content})
      local template = structure.template or "unknown"
      
      if not facts_by_template[template] then
        facts_by_template[template] = {}
      end
      
      table.insert(facts_by_template[template], {
        id = fact_id,
        history = fact_history,
        latest = latest_fact,
        structure = structure
      })
    end
  end
  
  -- Display facts grouped by template
  for template, facts in pairs(facts_by_template) do
    table.insert(lines, string.format("📋 Template: %s (%d facts)", template, #facts))
    table.insert(lines, string.rep("-", 60))
    
    for _, fact_info in ipairs(facts) do
      local fact_id = fact_info.id
      local latest = fact_info.latest
      local structure = fact_info.structure
      
      table.insert(lines, string.format("  f-%d: %s", fact_id, latest.retracted and "[RETRACTED]" or "[ACTIVE]"))
      
      -- Show key slots for quick overview
      if next(structure.slots) then
        local key_slots = {}
        local slot_count = 0
        for slot, value in pairs(structure.slots) do
          slot_count = slot_count + 1
          if slot_count <= 3 then -- Show first 3 slots
            if type(value) == "boolean" then
              table.insert(key_slots, string.format("%s: %s", slot, value and "true" or "false"))
            else
              local display_value = tostring(value)
              if #display_value > 30 then
                display_value = display_value:sub(1, 27) .. "..."
              end
              table.insert(key_slots, string.format("%s: %s", slot, display_value))
            end
          end
        end
        
        if #key_slots > 0 then
          table.insert(lines, string.format("    %s", table.concat(key_slots, " | ")))
        end
        
        if slot_count > 3 then
          table.insert(lines, string.format("    ... and %d more slots", slot_count - 3))
        end
      end
      
      -- Show modification count
      local mod_count = 0
      local i = 1
      while i <= #fact_info.history do
        local current = fact_info.history[i]
        local next_fact = fact_info.history[i + 1]
        
        if next_fact and current.retracted and not next_fact.retracted and 
           current.timestamp == next_fact.timestamp then
          mod_count = mod_count + 1
          i = i + 2
        else
          i = i + 1
        end
      end
      
      if mod_count > 0 then
        table.insert(lines, string.format("    Modifications: %d", mod_count))
      end
      
      table.insert(lines, "")
    end
    
    table.insert(lines, "")
  end
  
  -- Look for potential relationships between facts
  table.insert(lines, "🔍 Relationship Analysis")
  table.insert(lines, string.rep("-", 60))
  
  local relationships = find_fact_relationships(selected_fact_ids)
  if #relationships > 0 then
    for _, rel in ipairs(relationships) do
      table.insert(lines, string.format("  %s", rel))
    end
  else
    table.insert(lines, "  No obvious relationships detected")
  end
  
  table.insert(lines, "")
  table.insert(lines, "Controls: <Esc> Close | <1-9> Individual Details | <t> Timeline View | <Enter> Jump to line")
  
  set_buffer_content(state.detail_buf, lines)
  
  -- Set up keymaps for combined detail window
  local opts = { noremap = true, silent = true, buffer = state.detail_buf }
  vim.keymap.set('n', '<Esc>', function()
    close_window(state.detail_win, state.detail_buf)
    state.detail_win, state.detail_buf = nil, nil
  end, opts)
  
  vim.keymap.set('n', 't', function()
    show_combined_timeline(selected_fact_ids)
  end, opts)
  
  -- Add number keys for quick access to individual facts
  for i = 1, math.min(9, #selected_fact_ids) do
    vim.keymap.set('n', tostring(i), function()
      show_fact_details(selected_fact_ids[i])
    end, opts)
  end
end

-- Helper function to find relationships between facts
local function find_fact_relationships(fact_ids)
  local relationships = {}
  
  -- Get all fact data
  local facts_data = {}
  for _, fact_id in ipairs(fact_ids) do
    local fact_history = {}
    for _, fact in ipairs(state.current_facts) do
      if fact.id == fact_id then
        table.insert(fact_history, fact)
      end
    end
    
    if #fact_history > 0 then
      table.sort(fact_history, function(a, b) return a.line_num < b.line_num end)
      local latest = fact_history[#fact_history]
      local structure = parser.get_fact_structure({content = latest.content})
      facts_data[fact_id] = {
        history = fact_history,
        latest = latest,
        structure = structure
      }
    end
  end
  
  -- Look for shared slot values
  local slot_values = {}
  for fact_id, data in pairs(facts_data) do
    for slot, value in pairs(data.structure.slots) do
      if type(value) == "string" and #value > 2 then
        if not slot_values[value] then
          slot_values[value] = {}
        end
        table.insert(slot_values[value], {fact_id = fact_id, slot = slot})
      end
    end
  end
  
  for value, facts in pairs(slot_values) do
    if #facts > 1 then
      local fact_refs = {}
      for _, fact_info in ipairs(facts) do
        table.insert(fact_refs, string.format("f-%d.%s", fact_info.fact_id, fact_info.slot))
      end
      table.insert(relationships, string.format("Shared value '%s': %s", value, table.concat(fact_refs, ", ")))
    end
  end
  
  -- Look for temporal relationships (facts modified around the same time)
  local time_groups = {}
  for fact_id, data in pairs(facts_data) do
    for _, event in ipairs(data.history) do
      if not time_groups[event.timestamp] then
        time_groups[event.timestamp] = {}
      end
      table.insert(time_groups[event.timestamp], {fact_id = fact_id, action = event.retracted and "retracted" or "asserted"})
    end
  end
  
  for timestamp, events in pairs(time_groups) do
    if #events > 1 then
      local event_strs = {}
      for _, event in ipairs(events) do
        table.insert(event_strs, string.format("f-%d %s", event.fact_id, event.action))
      end
      table.insert(relationships, string.format("Simultaneous at %s: %s", timestamp, table.concat(event_strs, ", ")))
    end
  end
  
  return relationships
end

-- Show combined timeline for multiple facts
local function show_combined_timeline(fact_ids)
  if not state.timeline_buf then
    state.timeline_buf, state.timeline_win = create_floating_window(0.95, 0.8, string.format("Combined Timeline (%d facts)", #fact_ids))
  end
  
  local lines = {}
  table.insert(lines, string.format("Combined Timeline for %d Facts", #fact_ids))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")
  
  -- Collect all events from all facts
  local all_events = {}
  
  for _, fact_id in ipairs(fact_ids) do
    local fact_history = {}
    for _, fact in ipairs(state.current_facts) do
      if fact.id == fact_id then
        table.insert(fact_history, fact)
      end
    end
    
    table.sort(fact_history, function(a, b) return a.line_num < b.line_num end)
    
    -- Process this fact's timeline
    local i = 1
    while i <= #fact_history do
      local current = fact_history[i]
      local next_fact = fact_history[i + 1]
      
      if next_fact and current.retracted and not next_fact.retracted and 
         current.timestamp == next_fact.timestamp then
        -- Modification
        table.insert(all_events, {
          timestamp = current.timestamp,
          line_num = current.line_num,
          fact_id = fact_id,
          type = "MODIFIED",
          char = "◆",
          from_content = current.content,
          to_content = next_fact.content
        })
        i = i + 2
      else
        -- Regular event
        table.insert(all_events, {
          timestamp = current.timestamp,
          line_num = current.line_num,
          fact_id = fact_id,
          type = current.retracted and "RETRACTED" or "ASSERTED",
          char = current.retracted and "✗" or "●",
          content = current.content
        })
        i = i + 1
      end
    end
  end
  
  -- Sort all events by line number (chronological order)
  table.sort(all_events, function(a, b) return a.line_num < b.line_num end)
  
  -- Display combined timeline
  for i, event in ipairs(all_events) do
    local fact_color = ((event.fact_id - 1) % 4) + 1 -- Cycle through 4 colors
    local fact_indicator = string.format("f-%d", event.fact_id)
    
    table.insert(lines, string.format("  %s %s [%s] %s Line %d", 
      event.char, event.timestamp, event.type, fact_indicator, event.line_num))
    
    if event.type == "MODIFIED" then
      -- Show compact diff for modifications
      local from_structure = parser.get_fact_structure({content = event.from_content})
      local to_structure = parser.get_fact_structure({content = event.to_content})
      
      if from_structure.template and to_structure.template then
        local changes = {}
        local all_slots = {}
        for slot, _ in pairs(from_structure.slots) do all_slots[slot] = true end
        for slot, _ in pairs(to_structure.slots) do all_slots[slot] = true end
        
        for slot, _ in pairs(all_slots) do
          local from_val = from_structure.slots[slot]
          local to_val = to_structure.slots[slot]
          if from_val ~= to_val then
            if from_val and to_val then
              table.insert(changes, string.format("%s: %s→%s", slot, from_val, to_val))
            elseif from_val then
              table.insert(changes, string.format("%s: %s→(removed)", slot, from_val))
            else
              table.insert(changes, string.format("%s: (added)→%s", slot, to_val))
            end
          end
        end
        
        local diff_summary = #changes > 0 and table.concat(changes, ", ") or "content reformatted"
        table.insert(lines, string.format("    │ %s", diff_summary))
      else
        table.insert(lines, string.format("    │ content changed"))
      end
    else
      table.insert(lines, string.format("    │ %s", event.content))
    end
    
    if i < #all_events then
      table.insert(lines, "    │")
    end
  end
  
  table.insert(lines, "")
  table.insert(lines, "Controls: <Esc> Close | <j/k> Navigate | <Enter> Jump to line")
  
  set_buffer_content(state.timeline_buf, lines)
  
  -- Set up keymaps
  local opts = { noremap = true, silent = true, buffer = state.timeline_buf }
  vim.keymap.set('n', '<Esc>', function()
    close_window(state.timeline_win, state.timeline_buf)
    state.timeline_win, state.timeline_buf = nil, nil
  end, opts)
  
  vim.keymap.set('n', '<Enter>', function()
    local line_idx = vim.api.nvim_win_get_cursor(state.timeline_win)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.timeline_buf, line_idx - 1, line_idx, false)[1]
    
    local line_num = string.match(line_content, "Line (%d+)")
    if line_num and state.log_file then
      close_window(state.timeline_win, state.timeline_buf)
      state.timeline_win, state.timeline_buf = nil, nil
      
      vim.cmd('edit ' .. state.log_file)
      vim.api.nvim_win_set_cursor(0, {tonumber(line_num), 0})
      vim.cmd('normal! zz')
    end
  end, opts)
end

function M.show_fact_timeline(fact_id)
  local fact_history = {}
  for _, fact in ipairs(state.current_facts) do
    if fact.id == fact_id then
      table.insert(fact_history, fact)
    end
  end
  
  if #fact_history == 0 then
    vim.notify("No timeline data for fact f-" .. fact_id, vim.log.levels.WARN)
    return
  end
  
  -- Sort by line number
  table.sort(fact_history, function(a, b) return a.line_num < b.line_num end)
  
  if not state.timeline_buf then
    state.timeline_buf, state.timeline_win = create_floating_window(0.9, 0.7, "Timeline: f-" .. fact_id)
  end
  
  local lines = {}
  table.insert(lines, string.format("Timeline for Fact f-%d", fact_id))
  table.insert(lines, string.rep("=", 80))
  table.insert(lines, "")
  
  -- Analyze modifications (when retraction and assertion happen at same time)
  local timeline_events = {}
  local i = 1
  while i <= #fact_history do
    local current = fact_history[i]
    local next_fact = fact_history[i + 1]
    
    if next_fact and current.retracted and not next_fact.retracted and 
       current.timestamp == next_fact.timestamp then
      -- This is a modification - show diff-style compact format
      local from_structure = parser.get_fact_structure({content = current.content})
      local to_structure = parser.get_fact_structure({content = next_fact.content})
      
      local diff_summary = ""
      if from_structure.template and to_structure.template then
        -- Compare slots and create a compact summary
        local changes = {}
        local all_slots = {}
        for slot, _ in pairs(from_structure.slots) do
          all_slots[slot] = true
        end
        for slot, _ in pairs(to_structure.slots) do
          all_slots[slot] = true
        end
        
        for slot, _ in pairs(all_slots) do
          local from_val = from_structure.slots[slot]
          local to_val = to_structure.slots[slot]
          
          if from_val ~= to_val then
            if from_val and to_val then
              table.insert(changes, string.format("%s: %s→%s", slot, from_val, to_val))
            elseif from_val then
              table.insert(changes, string.format("%s: %s→(removed)", slot, from_val))
            else
              table.insert(changes, string.format("%s: (added)→%s", slot, to_val))
            end
          end
        end
        
        if #changes > 0 then
          diff_summary = table.concat(changes, ", ")
        else
          diff_summary = "content reformatted"
        end
      else
        diff_summary = "content changed"
      end
      
      table.insert(timeline_events, {
        char = "◆",
        status = "MODIFIED",
        timestamp = current.timestamp,
        line_num = current.line_num,
        content = diff_summary
      })
      i = i + 2 -- Skip both retraction and assertion
    else
      -- Regular event
      table.insert(timeline_events, {
        char = current.retracted and "✗" or "●",
        status = current.retracted and "RETRACTED" or "ASSERTED",
        timestamp = current.timestamp,
        line_num = current.line_num,
        content = current.content
      })
      i = i + 1
    end
  end
  
  for i, event in ipairs(timeline_events) do
    table.insert(lines, string.format("  %s %s [%s] Line %d", 
      event.char, event.timestamp, event.status, event.line_num))
    table.insert(lines, string.format("    │ %s", event.content))
    
    if i < #timeline_events then
      table.insert(lines, "    │")
    end
  end
  
  table.insert(lines, "")
  table.insert(lines, "Controls: <Esc> Close | <j/k> Navigate | <Enter> Jump to line")
  
  set_buffer_content(state.timeline_buf, lines)
  
  -- Add syntax highlighting
  vim.api.nvim_buf_set_option(state.timeline_buf, 'filetype', 'clips-timeline')
  
  -- Set up keymaps
  local opts = { noremap = true, silent = true, buffer = state.timeline_buf }
  vim.keymap.set('n', '<Esc>', function()
    close_window(state.timeline_win, state.timeline_buf)
    state.timeline_win, state.timeline_buf = nil, nil
  end, opts)
  
  vim.keymap.set('n', '<Enter>', function()
    local line_idx = vim.api.nvim_win_get_cursor(state.timeline_win)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.timeline_buf, line_idx - 1, line_idx, false)[1]
    
    -- Extract line number from timeline entry
    local line_num = string.match(line_content, "Line (%d+)")
    if line_num and state.log_file then
      -- Close timeline and jump to original file
      close_window(state.timeline_win, state.timeline_buf)
      state.timeline_win, state.timeline_buf = nil, nil
      
      vim.cmd('edit ' .. state.log_file)
      vim.api.nvim_win_set_cursor(0, {tonumber(line_num), 0})
      vim.cmd('normal! zz')
    end
  end, opts)
end

-- Function to extract fact ID from current line in log file
local function get_fact_id_from_line(line)
  -- Look for fact ID patterns like "==> f-123" or "<== f-456"
  local fact_id = string.match(line, "==> f%-(%d+)") or string.match(line, "<== f%-(%d+)")
  return fact_id and tonumber(fact_id) or nil
end

-- Function to get fact ID under cursor or from line
local function get_fact_id_under_cursor_or_line()
  -- Get current cursor position
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local col_num = vim.api.nvim_win_get_cursor(0)[2]
  local current_line = vim.api.nvim_get_current_line()
  
  -- First, try to get the word under cursor
  local word_under_cursor = vim.fn.expand('<cword>')
  
  -- Check if the word under cursor is a complete fact ID (f-123)
  local cursor_fact_id = word_under_cursor:match("^f%-(%d+)$")
  if cursor_fact_id then
    return tonumber(cursor_fact_id)
  end
  
  -- Check if it's just a number (could be a fact ID)
  local cursor_number = tonumber(word_under_cursor)
  if cursor_number then
    return cursor_number
  end
  
  -- Enhanced: Look for fact ID patterns and check if cursor is specifically on the f-<num> part
  -- This handles cases where cursor is on 'f' or '-' in 'f-123' but NOT on separators
  for i = 1, #current_line do
    local fact_start, fact_end, fact_id = current_line:find("(f%-%d+)", i)
    if fact_start then
      -- Check if cursor is within this specific fact ID (1-indexed to 0-indexed conversion)
      if col_num >= fact_start - 1 and col_num < fact_end then
        return tonumber(fact_id:match("f%-(%d+)"))
      end
      i = fact_end + 1
    else
      break
    end
  end
  
  -- Fall back to parsing the entire line only if cursor detection failed
  return get_fact_id_from_line(current_line)
end

-- Function to show fact details when called from log file
function M.show_fact_details_from_log()
  local fact_id = get_fact_id_under_cursor_or_line()
  
  if not fact_id then
    vim.notify("No fact ID found under cursor or on current line", vim.log.levels.WARN)
    return
  end
  
  -- Parse the current file if not already parsed
  if #state.current_facts == 0 then
    local current_file = vim.api.nvim_buf_get_name(0)
    if not current_file or current_file == "" then
      vim.notify("No file open", vim.log.levels.ERROR)
      return
    end
    
    state.log_file = current_file
    local success, facts = pcall(parser.parse_clips_log, current_file)
    if not success then
      vim.notify("Error parsing CLIPS log: " .. tostring(facts), vim.log.levels.ERROR)
      return
    end
    state.current_facts = facts
  end
  
  show_fact_details(fact_id)
end

-- Generate search suggestions based on current facts
local function get_search_suggestions()
  if #state.current_facts == 0 then return {} end
  
  local suggestions = {}
  
  -- Get templates
  local fact_types = parser.get_fact_types(state.current_facts)
  local template_names = {}
  for _, fact_type in ipairs(fact_types) do
    if fact_type.count > 1 then -- Only suggest common templates
      table.insert(suggestions, "template:" .. fact_type.name)
      table.insert(template_names, fact_type.name)
    end
  end
  
  -- Add multi-template syntax example if we have multiple common templates
  if #template_names >= 2 then
    local example_templates = {}
    for i = 1, math.min(3, #template_names) do
      table.insert(example_templates, template_names[i])
    end
    table.insert(suggestions, ":[" .. table.concat(example_templates, ",") .. "]")
    table.insert(suggestions, "template:[" .. table.concat(example_templates, ",") .. "],search_term")
  end
  
  -- Get common slots
  local slots = parser.get_all_slots(state.current_facts)
  for _, slot in ipairs(slots) do
    if slot.count > 2 then -- Only suggest slots that appear multiple times
      table.insert(suggestions, "slot:" .. slot.name)
      
      -- Get common values for this slot
      local values = parser.get_slot_values(state.current_facts, slot.name)
      for _, value in ipairs(values) do
        if value.count > 1 and string.len(value.value) > 2 then
          table.insert(suggestions, slot.name .. ":" .. value.value)
        end
      end
    end
  end
  
  return suggestions
end

function M.create_search_window()
  -- Close existing windows
  if state.search_win then
    close_window(state.search_win, state.search_buf)
  end
  
  -- Get current file path
  local current_file = vim.api.nvim_buf_get_name(0)
  if not current_file or current_file == "" then
    vim.notify("Please open a CLIPS log file first", vim.log.levels.ERROR)
    return
  end
  
  state.log_file = current_file
  
  -- Parse the current file
  local success, facts = pcall(parser.parse_clips_log, current_file)
  if not success then
    vim.notify("Error parsing CLIPS log: " .. tostring(facts), vim.log.levels.ERROR)
    return
  end
  
  state.current_facts = facts
  
  -- Create main search window
  state.search_buf, state.search_win = create_floating_window(0.9, 0.8, "CLIPS Log Analyzer")
  
  -- Initial display
  update_search_results()
  
  -- Set up keymaps
  local opts = { noremap = true, silent = true, buffer = state.search_buf }
  
  vim.keymap.set('n', '<Esc>', function()
    close_window(state.search_win, state.search_buf)
    close_window(state.detail_win, state.detail_buf)
    close_window(state.timeline_win, state.timeline_buf)
    state.search_win, state.search_buf = nil, nil
    state.detail_win, state.detail_buf = nil, nil
    state.timeline_win, state.timeline_buf = nil, nil
    state.selected_facts = {}  -- Clear selection when closing
  end, opts)
  
  vim.keymap.set('n', '/', function()
    -- Get suggestions based on current facts
    local suggestions = get_search_suggestions()
    
    vim.ui.input({
      prompt = 'Search facts (slot:value, template:name, etc.): ',
      default = state.search_query,
    }, function(input)
      if input then
        state.search_query = input
        update_search_results()
      end
    end)
  end, opts)
  
  vim.keymap.set('n', '?', function()
    show_search_help()
  end, opts)
  
  vim.keymap.set('n', '<C-r>', function()
    local success, facts = pcall(parser.parse_clips_log, state.log_file)
    if success then
      state.current_facts = facts
      state.selected_facts = {}  -- Clear selection on refresh
      update_search_results()
      vim.notify("Log file refreshed", vim.log.levels.INFO)
    else
      vim.notify("Error refreshing log: " .. tostring(facts), vim.log.levels.ERROR)
    end
  end, opts)
  
  vim.keymap.set('n', '<Enter>', function()
    local line_idx = vim.api.nvim_win_get_cursor(state.search_win)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.search_buf, line_idx - 1, line_idx, false)[1]
    
    -- Extract fact ID from line
    local fact_id = string.match(line_content, "f%-(%d+)")
    if fact_id then
      show_fact_details(tonumber(fact_id))
    end
  end, opts)
  
  -- Add space key for selecting/deselecting facts
  vim.keymap.set('n', '<Space>', function()
    local line_idx = vim.api.nvim_win_get_cursor(state.search_win)[1]
    local line_content = vim.api.nvim_buf_get_lines(state.search_buf, line_idx - 1, line_idx, false)[1]
    
    local fact_id = string.match(line_content, "f%-(%d+)")
    if fact_id then
      fact_id = tonumber(fact_id)
      if state.selected_facts[fact_id] then
        state.selected_facts[fact_id] = nil
        vim.notify(string.format("Deselected f-%d", fact_id), vim.log.levels.INFO)
      else
        state.selected_facts[fact_id] = true
        vim.notify(string.format("Selected f-%d", fact_id), vim.log.levels.INFO)
      end
      update_search_results()
    end
  end, opts)
  
  -- Add 'c' key for combined details
  vim.keymap.set('n', 'c', function()
    show_combined_facts_details()
  end, opts)
  
  -- Add 'x' key to clear selection
  vim.keymap.set('n', 'x', function()
    local count = 0
    for _ in pairs(state.selected_facts) do
      count = count + 1
    end
    state.selected_facts = {}
    update_search_results()
    vim.notify(string.format("Cleared selection (%d facts)", count), vim.log.levels.INFO)
  end, opts)
  
  -- Set cursor to first result line
  if #state.current_facts > 0 then
    vim.api.nvim_win_set_cursor(state.search_win, {5, 0})
  end
end

-- Show search help window
local function show_search_help()
  local help_buf, help_win = create_floating_window(0.7, 0.6, "Search Help")
  
  local lines = {
    "CLIPS Log Analyzer - Search Help",
    "=================================",
    "",
    "Search Formats:",
    "",
    "📋 Structured Search:",
    "  slot:value        - Find facts where 'slot' contains 'value'",
    "  slot=value        - Same as above (alternative syntax)",
    "  robot:ROBOT3      - Find facts where 'robot' slot contains 'ROBOT3'",
    "  state:WAITING     - Find facts where 'state' slot contains 'WAITING'",
    "",
    "🎯 Template Search:",
    "  template:task     - Find all facts of template 'task'",
    "  template:worker   - Find all facts of template 'worker'",
    "",
    "� Multi-Template Search:",
    "  :[task,worker,goal]      - Find facts of templates task, worker, or goal",
    "  :[a,b,c]                 - Find facts of templates a, b, or c",
    "",
    "⚡ Combined Search:",
    "  template:[a,b,c],gen46   - Find templates a,b,c containing 'gen46'",
    "  template:[task,goal],failed - Find task/goal facts containing 'failed'",
    "",
    "�🔍 Component Search:",
    "  slot:name         - Find facts that have a 'name' slot",
    "  value:failed      - Find facts with any slot containing 'failed'",
    "",
    "💬 Text Search:",
    "  ROBOT3            - Simple text search in fact content",
    "  failed            - Find any mention of 'failed'",
    "",
    "� Fact Combination:",
    "  <Space>           - Select/deselect facts for combination",
    "  c                 - View combined details of selected facts",
    "  x                 - Clear all selections",
    "",
    "�💡 Tips:",
    "  - Search is case-insensitive",
    "  - Use tab completion for suggestions",
    "  - Press 's' in fact details to search similar facts",
    "  - Select multiple facts to analyze relationships",
    "",
    "Press <Esc> to close this help"
  }
  
  set_buffer_content(help_buf, lines)
  
  vim.keymap.set('n', '<Esc>', function()
    close_window(help_win, help_buf)
  end, { noremap = true, silent = true, buffer = help_buf })
end

-- Syntax highlighting for timeline
vim.cmd([[
  augroup ClipsAnalyzer
    autocmd!
    autocmd FileType clips-timeline syntax match ClipsTimelineAssert "●.*ASSERTED.*"
    autocmd FileType clips-timeline syntax match ClipsTimelineRetract "✗.*RETRACTED.*"
    autocmd FileType clips-timeline syntax match ClipsTimelineModify "◆.*MODIFIED.*"
    autocmd FileType clips-timeline syntax match ClipsTimelinePipe "│"
    autocmd FileType clips-timeline highlight ClipsTimelineAssert ctermfg=green guifg=#50fa7b
    autocmd FileType clips-timeline highlight ClipsTimelineRetract ctermfg=red guifg=#ff5555
    autocmd FileType clips-timeline highlight ClipsTimelineModify ctermfg=yellow guifg=#f1fa8c
    autocmd FileType clips-timeline highlight ClipsTimelinePipe ctermfg=blue guifg=#8be9fd
  augroup END
]])

return M
