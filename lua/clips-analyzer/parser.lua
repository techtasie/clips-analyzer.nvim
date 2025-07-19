local M = {}

-- Parse a timestamp from CLIPS log format
local function parse_timestamp(line)
  local timestamp = string.match(line, "%[([^%]]+)%]")
  return timestamp or ""
end

-- Parse fact ID from lines like "==> f-123" or "<== f-123"
local function parse_fact_id(line)
  -- Look for assertion or retraction patterns
  local fact_id = string.match(line, "==> f%-(%d+)") or string.match(line, "<== f%-(%d+)")
  return fact_id and tonumber(fact_id) or nil
end

-- Extract fact content (everything after the fact ID)
local function extract_fact_content(line)
  -- Pattern to match: [timestamp] [main] [info] ==> f-123   (actual content...)
  -- More flexible pattern to handle variable spacing
  local content = string.match(line, "%[.-%] %[main%] %[info%] [=<]+ f%-%d+%s+(.+)")
  if not content then
    -- Try alternative format without main/info
    content = string.match(line, "[=<]+ f%-%d+%s+(.+)")
  end
  if not content then
    -- Even more flexible - just look for fact ID followed by content
    content = string.match(line, "f%-%d+%s+(.+)")
  end
  
  -- Handle truncated facts with "..."
  if content and string.find(content, "%.%.%.") then
    -- For truncated facts, extract what we can see
    content = string.gsub(content, "%s*%.%.%.%s*", " ... ")
  end
  
  return content or ""
end

-- Parse CLIPS fact structure into slots and values
local function parse_fact_structure(fact_content)
  if not fact_content or fact_content == "" then
    return {
      template = nil,
      slots = {},
      raw_content = fact_content
    }
  end
  
  local structure = {
    template = nil,
    slots = {},
    raw_content = fact_content
  }
  
  -- Extract template name (first word in parentheses)
  structure.template = string.match(fact_content, "%(([^%s%)]+)")
  
  -- For truncated facts with "...", we can still parse slots that are visible
  if string.find(fact_content, "%.%.%.") then
    -- Try to extract any visible slots before the truncation
    local before_dots = string.match(fact_content, "^(.-)%s*%.%.%.")
    if before_dots then
      -- Extract visible slots from the part before "..."
      for slot_match in string.gmatch(before_dots, "%(([^%)]+)%)") do
        local slot, value = string.match(slot_match, "^([^%s]+)%s+(.+)$")
        if slot and value then
          value = string.gsub(value, '^"(.*)"$', '%1')
          structure.slots[slot] = value
        elseif slot_match and not string.find(slot_match, "%s") then
          structure.slots[slot_match] = true
        end
      end
    end
    
    -- Also try to extract slots from the part after "..." - this is the key part!
    local after_dots = string.match(fact_content, "%.%.%.%s*(.+)")
    if after_dots then
      -- Process the part after "..." which may contain complete slot information
      local remaining = after_dots
      
      -- Extract slots and values - handle nested parentheses and quoted strings correctly
      local pos = 1
      while pos <= #remaining do
        local start_paren = string.find(remaining, "%(", pos)
        if not start_paren then break end
        
        -- Find the matching closing parenthesis, properly handling quotes
        local paren_count = 1
        local end_paren = nil
        local i = start_paren + 1
        
        while i <= #remaining and paren_count > 0 do
          local char = string.sub(remaining, i, i)
          
          if char == '"' then
            -- Found start of quoted string, find the end
            i = i + 1
            while i <= #remaining do
              local quote_char = string.sub(remaining, i, i)
              if quote_char == '"' then
                -- Check if it's escaped
                local prev_char = i > 1 and string.sub(remaining, i-1, i-1) or ""
                if prev_char ~= "\\" then
                  -- End of quoted string
                  break
                end
              end
              i = i + 1
            end
          elseif char == "(" then
            paren_count = paren_count + 1
          elseif char == ")" then
            paren_count = paren_count - 1
            if paren_count == 0 then
              end_paren = i
              break
            end
          end
          i = i + 1
        end
        
        if end_paren then
          -- Extract the slot content between parentheses
          local slot_content = string.sub(remaining, start_paren + 1, end_paren - 1)
          
          -- Parse slot name and values with proper quote handling
          local slot_parts = {}
          local current_part = ""
          local j = 1
          
          while j <= #slot_content do
            local char = string.sub(slot_content, j, j)
            
            if char == '"' then
              -- Start of quoted value
              local quote_start = j
              j = j + 1
              while j <= #slot_content do
                local quote_char = string.sub(slot_content, j, j)
                if quote_char == '"' then
                  local prev_char = j > 1 and string.sub(slot_content, j-1, j-1) or ""
                  if prev_char ~= "\\" then
                    -- End of quoted string
                    local quoted_value = string.sub(slot_content, quote_start, j)
                    if current_part == "" then
                      table.insert(slot_parts, quoted_value)
                    else
                      current_part = current_part .. quoted_value
                      table.insert(slot_parts, current_part)
                      current_part = ""
                    end
                    break
                  end
                end
                j = j + 1
              end
            elseif char == " " or char == "\t" then
              if current_part ~= "" then
                table.insert(slot_parts, current_part)
                current_part = ""
              end
              -- Skip whitespace
            else
              current_part = current_part .. char
            end
            j = j + 1
          end
          
          -- Add any remaining part
          if current_part ~= "" then
            table.insert(slot_parts, current_part)
          end
          
          if #slot_parts >= 2 then
            local slot = slot_parts[1]
            -- For multi-value slots, preserve all values
            if #slot_parts == 2 then
              local value = slot_parts[2]
              -- Clean up quotes from single values
              value = string.gsub(value, '^"(.*)"$', '%1')
              value = string.gsub(value, "^'(.*)'$", '%1')
              structure.slots[slot] = value
            else
              -- Multiple values - create a formatted string showing all values
              local values = {}
              for k = 2, #slot_parts do
                local value = slot_parts[k]
                -- Clean up quotes
                value = string.gsub(value, '^"(.*)"$', '%1')
                value = string.gsub(value, "^'(.*)'$", '%1')
                table.insert(values, value)
              end
              -- Store as a formatted string showing all values
              structure.slots[slot] = table.concat(values, ", ")
            end
          elseif #slot_parts == 1 then
            -- Single word slot (boolean or flag)
            structure.slots[slot_parts[1]] = true
          end
          
          pos = end_paren + 1
        else
          -- Malformed parentheses, skip
          pos = start_paren + 1
        end
      end
    end
  else
    -- Parse complete facts normally
    -- CLIPS facts are formatted like: (template-name (slot1 value1) (slot2 value2) ...)
    -- But may have truncated content with "..." like: (template ... (slot value))
    local remaining = fact_content
    
    -- Remove the template part and opening parenthesis - handle truncated facts
    if structure.template then
      -- Try to find where the template ends and slots begin
      local template_pattern = "^%(" .. structure.template .. ".-(%(.+%)%s*)%)%s*$"
      local slots_part = string.match(fact_content, template_pattern)
      if slots_part then
        remaining = slots_part
      else
        -- Fallback: just remove template and opening paren, keep everything else
        remaining = string.gsub(remaining, "^%(" .. structure.template .. "%s*", "", 1)
        remaining = string.gsub(remaining, "%s*%)%s*$", "")
      end
    end
    
    -- Extract slots and values - handle nested parentheses and quoted strings correctly
    -- CLIPS facts are formatted like: (template-name (slot1 value1) (slot2 value2) ...)
    -- We need to handle quoted values that may contain parentheses
    
    local pos = 1
    while pos <= #remaining do
      local start_paren = string.find(remaining, "%(", pos)
      if not start_paren then break end
      
      -- Find the matching closing parenthesis, properly handling quotes
      local paren_count = 1
      local end_paren = nil
      local i = start_paren + 1
      
      while i <= #remaining and paren_count > 0 do
        local char = string.sub(remaining, i, i)
        
        if char == '"' then
          -- Found start of quoted string, find the end
          i = i + 1
          while i <= #remaining do
            local quote_char = string.sub(remaining, i, i)
            if quote_char == '"' then
              -- Check if it's escaped
              local prev_char = i > 1 and string.sub(remaining, i-1, i-1) or ""
              if prev_char ~= "\\" then
                -- End of quoted string
                break
              end
            end
            i = i + 1
          end
        elseif char == "(" then
          paren_count = paren_count + 1
        elseif char == ")" then
          paren_count = paren_count - 1
          if paren_count == 0 then
            end_paren = i
            break
          end
        end
        i = i + 1
      end
      
      if end_paren then
        -- Extract the slot content between parentheses
        local slot_content = string.sub(remaining, start_paren + 1, end_paren - 1)
        
        -- Parse slot name and values with proper quote handling
        local slot_parts = {}
        local current_part = ""
        local i = 1
        
        while i <= #slot_content do
          local char = string.sub(slot_content, i, i)
          
          if char == '"' then
            -- Start of quoted value
            local quote_start = i
            i = i + 1
            while i <= #slot_content do
              local quote_char = string.sub(slot_content, i, i)
              if quote_char == '"' then
                local prev_char = i > 1 and string.sub(slot_content, i-1, i-1) or ""
                if prev_char ~= "\\" then
                  -- End of quoted string
                  local quoted_value = string.sub(slot_content, quote_start, i)
                  if current_part == "" then
                    table.insert(slot_parts, quoted_value)
                  else
                    current_part = current_part .. quoted_value
                    table.insert(slot_parts, current_part)
                    current_part = ""
                  end
                  break
                end
              end
              i = i + 1
            end
          elseif char == " " or char == "\t" then
            if current_part ~= "" then
              table.insert(slot_parts, current_part)
              current_part = ""
            end
            -- Skip whitespace
          else
            current_part = current_part .. char
          end
          i = i + 1
        end
        
        -- Add any remaining part
        if current_part ~= "" then
          table.insert(slot_parts, current_part)
        end
        
        if #slot_parts >= 2 then
          local slot = slot_parts[1]
          -- For multi-value slots, preserve all values
          if #slot_parts == 2 then
            local value = slot_parts[2]
            -- Clean up quotes from single values
            value = string.gsub(value, '^"(.*)"$', '%1')
            value = string.gsub(value, "^'(.*)'$", '%1')
            structure.slots[slot] = value
          else
            -- Multiple values - create a formatted string showing all values
            local values = {}
            for j = 2, #slot_parts do
              local value = slot_parts[j]
              -- Clean up quotes
              value = string.gsub(value, '^"(.*)"$', '%1')
              value = string.gsub(value, "^'(.*)'$", '%1')
              table.insert(values, value)
            end
            -- Store as a formatted string showing all values
            structure.slots[slot] = table.concat(values, ", ")
          end
        elseif #slot_parts == 1 then
          -- Single word slot (boolean or flag)
          structure.slots[slot_parts[1]] = true
        end
        
        pos = end_paren + 1
      else
        -- Malformed parentheses, skip
        pos = start_paren + 1
      end
    end
  end
  
  return structure
end

-- Advanced search function for CLIPS facts
local function search_fact_structure(fact, query_type, query_value)
  local structure = parse_fact_structure(fact.content)
  
  if query_type == "template" then
    return structure.template and string.find(structure.template:lower(), query_value:lower(), 1, true)
  elseif query_type == "slot" then
    for slot, _ in pairs(structure.slots) do
      if string.find(slot:lower(), query_value:lower(), 1, true) then
        return true
      end
    end
  elseif query_type == "value" then
    for _, value in pairs(structure.slots) do
      if type(value) == "string" and string.find(value:lower(), query_value:lower(), 1, true) then
        return true
      end
    end
  elseif query_type == "slot_value" then
    -- Query format: "slot:value" or "slot=value"
    local slot_name, slot_value = string.match(query_value, "([^:=]+)[:%=](.+)")
    if slot_name and slot_value then
      slot_name = slot_name:lower():gsub("^%s+", ""):gsub("%s+$", "")
      slot_value = slot_value:lower():gsub("^%s+", ""):gsub("%s+$", "")
      
      for slot, value in pairs(structure.slots) do
        if string.find(slot:lower(), slot_name, 1, true) then
          if type(value) == "string" and string.find(value:lower(), slot_value, 1, true) then
            return true
          end
        end
      end
    end
  end
  
  return false
end

-- Check if a line represents a fact assertion
local function is_fact_assertion(line)
  return string.match(line, "%] %[main%] %[info%] ==> f%-") ~= nil
end

-- Check if a line represents a fact retraction
local function is_fact_retraction(line)
  return string.match(line, "%] %[main%] %[info%] <== f%-") ~= nil
end

-- Check if a line represents a FIRE event
local function is_fire_event(line)
  return string.match(line, "%] %[main%] %[info%] FIRE") ~= nil
end

-- Parse FIRE events for rule execution tracking
local function parse_fire_event(line)
  local fire_num = string.match(line, "FIRE%s+(%d+)")
  local rule_name = string.match(line, "FIRE%s+%d+%s+([^:]+):")
  return {
    fire_number = fire_num and tonumber(fire_num) or nil,
    rule_name = rule_name and string.gsub(rule_name, "%s+$", "") or nil,
    timestamp = parse_timestamp(line)
  }
end

-- Group facts by their ID to track state changes
local function group_facts_by_id(facts)
  local grouped = {}
  for _, fact in ipairs(facts) do
    if not grouped[fact.id] then
      grouped[fact.id] = {}
    end
    table.insert(grouped[fact.id], fact)
  end
  
  -- Sort each group by line number
  for _, group in pairs(grouped) do
    table.sort(group, function(a, b) return a.line_num < b.line_num end)
  end
  
  return grouped
end

-- Analyze fact lifecycle (creation, modifications, deletion)
local function analyze_fact_lifecycle(grouped_facts)
  local lifecycle = {}
  
  for fact_id, facts in pairs(grouped_facts) do
    local life = {
      id = fact_id,
      created_at = nil,
      deleted_at = nil,
      modifications = {},
      current_state = "unknown"
    }
    
    for _, fact in ipairs(facts) do
      if not fact.retracted then
        if not life.created_at then
          life.created_at = fact.timestamp
        end
        table.insert(life.modifications, {
          timestamp = fact.timestamp,
          line_num = fact.line_num,
          content = fact.content,
          action = "asserted"
        })
        life.current_state = "active"
      else
        life.deleted_at = fact.timestamp
        table.insert(life.modifications, {
          timestamp = fact.timestamp,
          line_num = fact.line_num,
          content = fact.content,
          action = "retracted"
        })
        life.current_state = "retracted"
      end
    end
    
    lifecycle[fact_id] = life
  end
  
  return lifecycle
end

-- Main parsing function
function M.parse_clips_log(file_path)
  local file = io.open(file_path, "r")
  if not file then
    error("Could not open file: " .. file_path)
  end
  
  local facts = {}
  local fire_events = {}
  local line_num = 0
  
  for line in file:lines() do
    line_num = line_num + 1
    
    -- Parse fact assertions and retractions
    if is_fact_assertion(line) or is_fact_retraction(line) then
      local fact_id = parse_fact_id(line)
      if fact_id then
        local content = extract_fact_content(line)
        local fact = {
          id = fact_id,
          content = content,
          timestamp = parse_timestamp(line),
          line_num = line_num,
          retracted = is_fact_retraction(line),
          raw_line = line
        }
        table.insert(facts, fact)
      end
    elseif is_fire_event(line) then
      local fire_event = parse_fire_event(line)
      if fire_event then
        fire_event.line_num = line_num
        fire_event.raw_line = line
        table.insert(fire_events, fire_event)
      end
    end
  end
  
  file:close()
  
  return facts, fire_events
end

-- Get all unique fact types from the parsed facts
function M.get_fact_types(facts)
  local types = {}
  local type_counts = {}
  
  for _, fact in ipairs(facts) do
    -- Extract fact type (first word in parentheses)
    local fact_type = string.match(fact.content, "%(([^%s%)]+)")
    if fact_type then
      if not types[fact_type] then
        types[fact_type] = true
        type_counts[fact_type] = 0
      end
      type_counts[fact_type] = type_counts[fact_type] + 1
    end
  end
  
  -- Convert to sorted list
  local sorted_types = {}
  for fact_type, _ in pairs(types) do
    table.insert(sorted_types, {
      name = fact_type,
      count = type_counts[fact_type]
    })
  end
  
  table.sort(sorted_types, function(a, b) return a.count > b.count end)
  
  return sorted_types
end

-- Parse template list from patterns like "[a,b,c]"
local function parse_template_list(list_str)
  local templates = {}
  -- Remove brackets and split by comma
  local content = string.match(list_str, "%[(.+)%]")
  if content then
    for template in string.gmatch(content, "([^,]+)") do
      table.insert(templates, string.match(template, "^%s*(.-)%s*$")) -- trim whitespace
    end
  end
  return templates
end

-- Check if fact matches any of the given templates
local function matches_template_list(fact, templates)
  local structure = parse_fact_structure(fact.content)
  if not structure.template then return false end
  
  for _, template in ipairs(templates) do
    if string.find(structure.template:lower(), template:lower(), 1, true) then
      return true
    end
  end
  return false
end

-- Parse fact history constraint pattern like "fact:{template:name, slot:!value}"
local function parse_fact_constraint(pattern)
  local content = string.match(pattern, "^fact:%{(.+)%}")
  if not content then return nil end
  
  local constraints = {}
  
  -- Parse template constraint
  local template = string.match(content, "template:([^,}]+)")
  if template then
    constraints.template = string.match(template, "^%s*(.-)%s*$") -- trim whitespace
  end
  
  -- Parse slot constraints (can be slot:value or slot:!value for negation)
  for slot_constraint in string.gmatch(content, "([^,]+)") do
    if not string.match(slot_constraint, "template:") then
      local slot, value = string.match(slot_constraint, "^%s*([^:]+):%s*(.-)%s*$")
      if slot and value then
        local negated = false
        if string.sub(value, 1, 1) == "!" then
          negated = true
          value = string.sub(value, 2)
          value = string.match(value, "^%s*(.-)%s*$") -- trim whitespace after !
        end
        
        if not constraints.slots then
          constraints.slots = {}
        end
        
        table.insert(constraints.slots, {
          name = slot,
          value = value,
          negated = negated
        })
      end
    end
  end
  
  return constraints
end

-- Check if a fact matches fact history constraints
local function matches_fact_constraint(facts, fact_id, constraints)
  -- Get all history for this fact ID
  local fact_history = {}
  for _, fact in ipairs(facts) do
    if fact.id == fact_id then
      table.insert(fact_history, fact)
    end
  end
  
  if #fact_history == 0 then return false end
  
  -- Check template constraint on latest version
  table.sort(fact_history, function(a, b) return a.line_num < b.line_num end)
  local latest_fact = fact_history[#fact_history]
  local latest_structure = parse_fact_structure(latest_fact.content)
  
  if constraints.template then
    if not latest_structure.template or 
       not string.find(latest_structure.template:lower(), constraints.template:lower(), 1, true) then
      return false
    end
  end
  
  -- Check slot constraints across entire history
  if constraints.slots then
    for _, slot_constraint in ipairs(constraints.slots) do
      local found_value = false
      
      -- Check all versions of this fact in history
      for _, historical_fact in ipairs(fact_history) do
        local structure = parse_fact_structure(historical_fact.content)
        local slot_value = structure.slots[slot_constraint.name]
        
        if slot_value and type(slot_value) == "string" then
          if string.find(slot_value:lower(), slot_constraint.value:lower(), 1, true) then
            found_value = true
            break
          end
        end
      end
      
      -- Apply negation logic
      if slot_constraint.negated then
        -- For negated constraints (!value), fail if we found the value
        if found_value then
          return false
        end
      else
        -- For positive constraints (value), fail if we didn't find the value
        if not found_value then
          return false
        end
      end
    end
  end
  
  return true
end

-- Search facts by pattern
function M.search_facts(facts, pattern, case_sensitive)
  local results = {}
  
  -- Check for fact history constraint pattern first
  if string.match(pattern, "^fact:%{.+%}") then
    -- Fact history constraint: "fact:{template:name, slot:!value}"
    local constraints = parse_fact_constraint(pattern)
    if constraints then
      -- Get unique fact IDs first
      local fact_ids = {}
      for _, fact in ipairs(facts) do
        fact_ids[fact.id] = true
      end
      
      -- Check each unique fact ID against constraints
      for fact_id, _ in pairs(fact_ids) do
        if matches_fact_constraint(facts, fact_id, constraints) then
          -- Add the latest version of this fact to results
          local fact_history = {}
          for _, fact in ipairs(facts) do
            if fact.id == fact_id then
              table.insert(fact_history, fact)
            end
          end
          
          if #fact_history > 0 then
            table.sort(fact_history, function(a, b) return a.line_num < b.line_num end)
            table.insert(results, fact_history[#fact_history])
          end
        end
      end
    end
  elseif string.match(pattern, "^template:%[.+%],(.+)") then
    -- Combined template filter with additional search: "template:[a,b,c],gen46"
    local template_part, search_part = string.match(pattern, "^template:(%[.+%]),(.+)")
    local templates = parse_template_list(template_part)
    
    for _, fact in ipairs(facts) do
      if matches_template_list(fact, templates) then
        -- Also check if it matches the additional search criteria
        local search_pattern = case_sensitive and search_part or search_part:lower()
        local search_text = case_sensitive and fact.content or fact.content:lower()
        if string.find(search_text, search_pattern, 1, true) then
          table.insert(results, fact)
        end
      end
    end
  elseif string.match(pattern, "^:%[.+%]") then
    -- Template list filter: ":[a,b,c]"
    local template_part = string.match(pattern, "^:(%[.+%])")
    local templates = parse_template_list(template_part)
    
    for _, fact in ipairs(facts) do
      if matches_template_list(fact, templates) then
        table.insert(results, fact)
      end
    end
  elseif string.match(pattern, "^template:(.+)") then
    -- Template search: "template:task"
    local template_name = string.match(pattern, "^template:(.+)")
    for _, fact in ipairs(facts) do
      if search_fact_structure(fact, "template", template_name) then
        table.insert(results, fact)
      end
    end
  elseif string.match(pattern, "^slot:(.+)") then
    -- Slot search: "slot:robot"
    local slot_name = string.match(pattern, "^slot:(.+)")
    for _, fact in ipairs(facts) do
      if search_fact_structure(fact, "slot", slot_name) then
        table.insert(results, fact)
      end
    end
  elseif string.match(pattern, "^value:(.+)") then
    -- Value search: "value:ROBOT3"
    local value_name = string.match(pattern, "^value:(.+)")
    for _, fact in ipairs(facts) do
      if search_fact_structure(fact, "value", value_name) then
        table.insert(results, fact)
      end
    end
  elseif string.find(pattern, ":") or string.find(pattern, "=") then
    -- Structured search: "slot:value" or "slot=value" (only if not template/slot/value prefix)
    for _, fact in ipairs(facts) do
      if search_fact_structure(fact, "slot_value", pattern) then
        table.insert(results, fact)
      end
    end
  else
    -- Fallback to original text search
    local search_pattern = case_sensitive and pattern or pattern:lower()
    
    for _, fact in ipairs(facts) do
      local search_text = case_sensitive and fact.content or fact.content:lower()
      if string.find(search_text, search_pattern, 1, true) then
        table.insert(results, fact)
      end
    end
  end
  
  return results
end

-- Get structured fact information
function M.get_fact_structure(fact)
  return parse_fact_structure(fact.content)
end

-- Get all slot names from facts
function M.get_all_slots(facts)
  local slots = {}
  local slot_counts = {}
  
  for _, fact in ipairs(facts) do
    local structure = parse_fact_structure(fact.content)
    for slot, _ in pairs(structure.slots) do
      if not slots[slot] then
        slots[slot] = true
        slot_counts[slot] = 0
      end
      slot_counts[slot] = slot_counts[slot] + 1
    end
  end
  
  -- Convert to sorted list
  local sorted_slots = {}
  for slot, _ in pairs(slots) do
    table.insert(sorted_slots, {
      name = slot,
      count = slot_counts[slot]
    })
  end
  
  table.sort(sorted_slots, function(a, b) return a.count > b.count end)
  
  return sorted_slots
end

-- Get all unique values for a specific slot
function M.get_slot_values(facts, slot_name)
  local values = {}
  local value_counts = {}
  
  for _, fact in ipairs(facts) do
    local structure = parse_fact_structure(fact.content)
    for slot, value in pairs(structure.slots) do
      if slot:lower() == slot_name:lower() and type(value) == "string" then
        if not values[value] then
          values[value] = true
          value_counts[value] = 0
        end
        value_counts[value] = value_counts[value] + 1
      end
    end
  end
  
  -- Convert to sorted list
  local sorted_values = {}
  for value, _ in pairs(values) do
    table.insert(sorted_values, {
      value = value,
      count = value_counts[value]
    })
  end
  
  table.sort(sorted_values, function(a, b) return a.count > b.count end)
  
  return sorted_values
end

-- Get fact statistics
function M.get_statistics(facts, fire_events)
  local stats = {
    total_facts = #facts,
    total_fire_events = #fire_events,
    assertions = 0,
    retractions = 0,
    unique_fact_ids = {},
    fact_types = {},
    timeline_span = {
      start = nil,
      end_time = nil
    }
  }
  
  -- Count assertions and retractions
  for _, fact in ipairs(facts) do
    if fact.retracted then
      stats.retractions = stats.retractions + 1
    else
      stats.assertions = stats.assertions + 1
    end
    
    -- Track unique fact IDs
    stats.unique_fact_ids[fact.id] = true
    
    -- Track timeline
    if not stats.timeline_span.start or fact.timestamp < stats.timeline_span.start then
      stats.timeline_span.start = fact.timestamp
    end
    if not stats.timeline_span.end_time or fact.timestamp > stats.timeline_span.end_time then
      stats.timeline_span.end_time = fact.timestamp
    end
  end
  
  -- Count unique fact IDs
  local unique_count = 0
  for _ in pairs(stats.unique_fact_ids) do
    unique_count = unique_count + 1
  end
  stats.unique_fact_count = unique_count
  
  -- Get fact types
  stats.fact_types = M.get_fact_types(facts)
  
  return stats
end

-- Advanced analysis functions
M.group_facts_by_id = group_facts_by_id
M.analyze_fact_lifecycle = analyze_fact_lifecycle

return M
