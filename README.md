# clips-analyzer.nvim

A powerful Neovim plugin for analyzing CLIPS expert system logs. Provides advanced search capabilities, fact relationship analysis, timeline visualization, and fact combination features.

## Features

- 🔍 **Advanced Search**: Multiple search syntax including template filters, slot searches, and fact history queries
- 📊 **Fact Analysis**: Detailed fact history with modification tracking and lifecycle visualization  
- 🔗 **Relationship Detection**: Automatic detection of relationships between facts
- 📈 **Timeline Views**: Visual timeline of fact assertions, retractions, and modifications
- 🎯 **Multi-Fact Selection**: Select and analyze multiple facts together
- 🚀 **Performance**: Fast parsing and search across large CLIPS logs

## Installation

### Using vim-plug

Add this to your `init.vim` or `init.lua`:

```vim
Plug 'timwendt/clips-analyzer.nvim'
```

Then run:
```vim
:PlugInstall
```

### Using packer.nvim

```lua
use 'timwendt/clips-analyzer.nvim'
```

### Using lazy.nvim

```lua
{
  'timwendt/clips-analyzer.nvim',
  config = function()
    require('clips-analyzer').setup()
  end
}
```

## Quick Start

1. Open a CLIPS log file
2. Run `:ClipsSearch` to open the search interface
3. Use the search examples or press `?` for help

## Commands

| Command | Description |
|---------|-------------|
| `:ClipsSearch` | Open the main search interface |
| `:ClipsAnalyze` | Alias for `:ClipsSearch` |
| `:ClipsDetails` | Show details for fact under cursor |

## Default Key Mappings

| Key | Mode | Action |
|-----|------|--------|
| `<leader>cs` | Normal | Open search window |
| `<leader>ca` | Normal | Open analyzer window |
| `gd` | Normal (CLIPS files) | Show fact details under cursor |

To disable default mappings, add to your config:
```vim
let g:clips_analyzer_no_mappings = 1
```

## Search Syntax

### Basic Searches
- `robot:ROBOT3` - Find facts where slot 'robot' contains 'ROBOT3'
- `state=WAITING` - Find facts where slot 'state' contains 'WAITING'
- `template:task` - Find all facts of template 'task'

### Advanced Searches
- `:[task,worker,goal]` - Find facts of multiple templates
- `template:[a,b],gen46` - Find templates a,b that contain 'gen46'
- `fact:{template:task, state:!DONE}` - Tasks never marked DONE

### Fact History Searches
The most powerful feature - search across entire fact lifecycles:

- `fact:{template:pddl-action-precondition, state:PRECONDITION-SAT}` - Facts that were ever satisfied
- `fact:{template:pddl-action-precondition, state:!PRECONDITION-SAT}` - Facts that were **never** satisfied
- `fact:{template:action, status:!FAILED}` - Actions that never failed

### Component Searches
- `slot:name` - Find facts that have a 'name' slot
- `value:failed` - Find facts with any slot containing 'failed'

## Interface Controls

### Search Window
- `<Enter>` - View fact details
- `<Space>` - Select/deselect fact for combination
- `c` - View combined details of selected facts
- `x` - Clear all selections
- `/` - Start new search
- `?` - Show help
- `<Esc>` - Close window

### Detail Windows
- `<Esc>` - Close window
- `t` - View timeline
- `s` - Search for similar facts
- `<Enter>` - Jump to line in original file
- `1-9` - Quick access to individual facts (combined view)

## Examples

### Finding Failed Preconditions
```
fact:{template:pddl-action-precondition, state:!PRECONDITION-SAT}
```
Finds all action preconditions that never became satisfied during their entire lifecycle.

### Multi-Template Analysis
```
:[task,goal,action]
```
Shows all facts that are tasks, goals, or actions.

### Combined Template + Content Search
```
template:[task,goal],robot3
```
Finds task or goal facts that contain 'robot3' anywhere.

## Configuration

```lua
require('clips-analyzer').setup({
  -- Configuration options will be added in future versions
})
```

## File Type Detection

The plugin automatically detects CLIPS log files with extensions:
- `.clips`
- `.log` 
- `.clips-log`

## Requirements

- Neovim 0.5+
- Lua support

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

MIT License - see LICENSE file for details.
