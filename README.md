# fzf-navigator

`fzf-navigator` is an interactive file system navigator that uses [fzf](https://github.com/junegunn/fzf). It provides a speedy alternative to `cd` + `ls` with previews, toggles, history navigation and contextual command-line insertion.

![](fzf-navigator.png)

## Installation

Download `fzf-navigator.sh` and source it in your shell rc file.

Example:

```bash
curl -o ~/.config/fzf-navigator.sh https://raw.githubusercontent.com/benward2301/fzf-navigator/main/fzf-navigator.sh
echo 'source ~/.config/fzf-navigator.sh' >> ~/.${SHELL##*/}rc
```

### Dependencies

- [fzf](https://github.com/junegunn/fzf) ≥ 0.45.0
- [eza](https://github.com/eza-community/eza) - Optional (required for icons), falls back to ls
- [bat](https://github.com/sharkdp/bat) - Optional (required for colorized file previews), falls back to cat for file previews

## Usage

Press `Ctrl+Space` (default) to open the navigator.

### Bindings

| Key | Action | Description |
|-----|--------|-------------|
| `space` | `open` | Enter directory / edit file |
| `ctrl-o` | `open_and_exit` | Enter directory / edit file and exit navigator |
| `ctrl-space` | `exit` | Exit navigator (cd to current directory if locked) |
| `enter` | `insert_selection` | Insert path(s) at cursor |
| `ctrl-y` | `copy_selection` | Copy path(s) to clipboard |
| `esc` | `cancel` | Exit, or reset path if locked |
| `ctrl-d` | `go_to_parent` | Go to parent directory |
| `ctrl-alt-o` | `go_back` | Go back in history |
| `ctrl-alt-i` | `go_forward` | Go forward in history |
| `[` | `go_to_session_start` | Go to session start |
| `;` | `go_home` | Go to home |
| `/` | `go_to_root` | Go to root |
| `ctrl-l` | `toggle_locked` | Toggle locked mode (navigation doesn't change shell CWD) |
| `alt-h` | `toggle_hidden_files` | Toggle hidden files |
| `ctrl-g` | `toggle_file_details` | Toggle file details (`-l`) |
| `ctrl-r` | `toggle_recent_first` | Toggle recent-first sort |
| `?` | `toggle_this_help` | Toggle help |

## Configuration

| Variable | Description |
|----------|-------------|
| `FZF_NAVIGATOR_KEY` | Keybinding to launch navigator (default: `ctrl-space`) |
| `FZF_NAVIGATOR_SHOW_HIDDEN` | Show hidden files by default if set |
| `FZF_NAVIGATOR_LOCK_CWD` | Start in locked mode if set (navigation doesn't change shell CWD) |
| `FZF_NAVIGATOR_HIDE_HELP` | Hide the "? for help" hint if set |
| `FZF_NAVIGATOR_LS_FORMAT` | Comma-separated: `icons`, `color`, `classify`, or `plain` (default: `icons,color`) |
| `FZF_NAVIGATOR_BINDINGS` | Custom keybindings: `"key:action,key:action,..."` |
| `FZF_NAVIGATOR_OPTIONS` | Additional fzf options |
| `FZF_NAVIGATOR_FILE_PREVIEW_COMMAND` | Custom file preview command (receives path as `$1`) |
| `FZF_NAVIGATOR_DIR_PREVIEW_COMMAND` | Custom directory preview command (receives path as `$1`) |

## Compatibility

- **Shells**: zsh, bash ≥ 5.0
- **Platforms**: Linux, macOS
- **ls variants**: eza, GNU ls, BSD ls
