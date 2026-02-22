__fzf_navigator_detect_dir() {
  if [[ -n "$ZSH_VERSION" ]]; then
    echo "${${(%):-%x}:A:h}"
  elif [[ -n "$BASH_VERSION" ]]; then
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
  fi
}

if [[ -z "${FZF_NAVIGATOR_DIR:-}" ]] || [[ ! -f "${FZF_NAVIGATOR_DIR}/fzf-navigator.sh" ]]; then
  FZF_NAVIGATOR_DIR="$(__fzf_navigator_detect_dir)"
fi

if [[ ! -f "${FZF_NAVIGATOR_DIR}/fzf-navigator.sh" ]]; then
  echo "fzf-navigator: Could not detect script location" >&2
  return 1 2>/dev/null || exit 1
fi
export FZF_NAVIGATOR_DIR

: "${FZF_NAVIGATOR_KEY:=ctrl-space}"

__fzf_navigator_abspath() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  elif [[ -f "$path" ]]; then
    local dir="${path%/*}"
    local base="${path##*/}"
    [[ "$dir" == "$path" ]] && dir="."
    echo "$(cd "$dir" && pwd)/$base"
  else
    local dir="${path%/*}"
    local base="${path##*/}"
    [[ "$dir" == "$path" ]] && dir="."
    if [[ -d "$dir" ]]; then
      echo "$(cd "$dir" && pwd)/$base"
    else
      echo "$path"
    fi
  fi
}

__fzf_navigator_relpath() {
  local target="$1"
  local base="${2:-$PWD}"
  local abs_target=$(__fzf_navigator_abspath "$target")
  local abs_base=$(__fzf_navigator_abspath "$base")
  perl -e 'use File::Spec; print File::Spec->abs2rel($ARGV[0], $ARGV[1])' "$abs_target" "$abs_base"
}

__fzf_navigator_tildify() {
  local path="$1"
  if [[ "$path" == "$HOME" ]]; then
    echo "~"
  elif [[ "$path" == "$HOME"/* ]]; then
    echo "~${path#$HOME}"
  else
    echo "$path"
  fi
}

__fzf_navigator_common_parent() {
  local path1="$1"
  local path2="$2"
  local IFS='/'
  local -a parts1=($path1)
  local -a parts2=($path2)
  local common=""
  local i=0
  while [[ $i -lt ${#parts1[@]} && $i -lt ${#parts2[@]} ]]; do
    if [[ "${parts1[$i]}" == "${parts2[$i]}" ]]; then
      [[ -n "${parts1[$i]}" ]] && common="$common/${parts1[$i]}"
    else
      break
    fi
    ((i++))
  done
  [[ -z "$common" ]] && common="/"
  echo "$common"
}

__fzf_navigator_nav_action() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  if [[ -f "$tmpdir/locked" ]]; then
    echo "disable-search+reload(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_reload')+rebind(result)+first"
  else
    echo "become(echo //cd)"
  fi
}

__fzf_navigator_is_gnu_ls() {
  ls --version 2>/dev/null | grep -q GNU
}

__fzf_navigator_has_feature() {
  local feature="$1"
  local format="${FZF_NAVIGATOR_LS_FORMAT:-icons,color}"
  [[ "$format" == "plain" ]] && return 1
  [[ ",$format," == *",$feature,"* ]]
}

__fzf_navigator_detect_ls_command() {
  if command -v eza &>/dev/null; then
    echo "eza"
  else
    echo "ls"
  fi
}

__fzf_navigator_has_icons() {
  local cmd=$(__fzf_navigator_detect_ls_command)
  [[ "$cmd" == "eza" ]] && __fzf_navigator_has_feature "icons"
}

__fzf_navigator_extract_filename() {
  local line="$1"
  local clean_line=$(printf '%s' "$line" | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g')

  # Field offsets differ by command:
  #   eza -l: 7 (without icons) or 8 (with icons)
  #   ls -l:  9
  # Detect long listing by checking for Unix permission string (e.g., drwxr-xr-x)
  if printf '%s' "$clean_line" | grep -qE '^[.dlcbspDw-][-rwxsStTlL]{9}[@.+]?[[:space:]]'; then
    local field_start
    if [[ "$(__fzf_navigator_detect_ls_command)" == "eza" ]]; then
      if __fzf_navigator_has_icons; then
        field_start=8
      else
        field_start=7
      fi
    else
      field_start=9
    fi

    local filename=$(printf '%s' "$clean_line" | awk -v start="$field_start" '{for(i=start;i<=NF;i++) printf "%s%s", $i, (i<NF ? OFS : ""); print ""}')
  else
    if __fzf_navigator_has_icons; then
      filename=$(printf '%s' "$clean_line" | awk '{for(i=2;i<=NF;i++) printf "%s%s", $i, (i<NF ? " " : "")}')
    else
      filename="$clean_line"
    fi
  fi

  filename="${filename%% ->*}"
  __fzf_navigator_has_feature "classify" && filename="${filename%/}"

  echo "$filename"
}

__fzf_navigator_build_ls_cmd() {
  local ls_cmd=$(__fzf_navigator_detect_ls_command)
  local cmd=""
  if [[ "$ls_cmd" == "eza" ]]; then
    cmd="eza --no-quotes"
    if __fzf_navigator_has_feature "color"; then
      cmd="$cmd --color=always"
    else
      cmd="$cmd --color=never"
    fi
    if __fzf_navigator_has_feature "icons"; then
      cmd="$cmd --icons=always"
    else
      cmd="$cmd --icons=never"
    fi
    __fzf_navigator_has_feature "classify" && cmd="$cmd --classify=always"
  else
    cmd="ls"
    if __fzf_navigator_has_feature "color"; then
      if __fzf_navigator_is_gnu_ls; then
        cmd="$cmd --color=always"
      else
        cmd="$cmd -G"
      fi
    else
      __fzf_navigator_is_gnu_ls && cmd="$cmd --color=never"
    fi
    __fzf_navigator_has_feature "classify" && cmd="$cmd -p"
  fi
  echo "$cmd"
}

__fzf_navigator_reload() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local ls_cmd=$(__fzf_navigator_detect_ls_command)
  local cmd=$(__fzf_navigator_build_ls_cmd)

  if [[ "$ls_cmd" == "eza" ]]; then
    if [[ -f "$tmpdir/recent_first" ]]; then
      cmd="$cmd --sort=modified --reverse"
    else
      cmd="$cmd --group-directories-first"
    fi
    [[ -f "$tmpdir/show_details" ]] && cmd="$cmd -l" || cmd="$cmd -1"
    [[ -f "$tmpdir/show_hidden" ]] && cmd="$cmd -a"
  else
    if [[ -f "$tmpdir/recent_first" ]]; then
      cmd="$cmd -t"
    elif __fzf_navigator_is_gnu_ls; then
      cmd="$cmd -v"
    fi
    [[ -f "$tmpdir/show_details" ]] && cmd="$cmd -l" || cmd="$cmd -1"
    [[ -f "$tmpdir/show_hidden" ]] && cmd="$cmd -A"
  fi

  if [[ "$ls_cmd" != "eza" && -f "$tmpdir/show_details" ]]; then
    cd "$current_dir" && eval "$cmd" . | grep -v '^total '
  else
    cd "$current_dir" && eval "$cmd" .
  fi
}

__fzf_navigator_is_binary() {
  local path="$1"
  local mime
  mime=$(file -bL --mime-encoding "$path" 2>/dev/null)
  [[ "$mime" == "binary" ]]
}

__fzf_navigator_default_preview_file() {
  local path="$1"
  if __fzf_navigator_is_binary "$path"; then
    if command -v xxd &>/dev/null; then
      xxd "$path" | head -500
    elif command -v hexdump &>/dev/null; then
      hexdump -C "$path" | head -500
    else
      od -A x -t x1z -v "$path" | head -500
    fi
  elif command -v bat &>/dev/null; then
    bat --color=always --style=plain "$path"
  else
    cat "$path"
  fi
}

__fzf_navigator_default_preview_directory() {
  local path="$1"
  local ls_cmd=$(__fzf_navigator_detect_ls_command)
  local cmd=$(__fzf_navigator_build_ls_cmd)
  if [[ "$ls_cmd" == "eza" ]]; then
    cmd="$cmd --group-directories-first -1"
  else
    cmd="$cmd -1"
  fi
  eval "$cmd" '"$path"'
}

__fzf_navigator_preview() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local filename=$(__fzf_navigator_extract_filename "$1")
  local full_path="${current_dir%/}/$filename"

  if [[ -d "$full_path" ]]; then
    if [[ -n "$FZF_NAVIGATOR_DIR_PREVIEW_COMMAND" ]]; then
      eval "$FZF_NAVIGATOR_DIR_PREVIEW_COMMAND \"\$full_path\""
    else
      __fzf_navigator_default_preview_directory "$full_path"
    fi
  elif [[ -f "$full_path" ]]; then
    if [[ -n "$FZF_NAVIGATOR_FILE_PREVIEW_COMMAND" ]]; then
      eval "$FZF_NAVIGATOR_FILE_PREVIEW_COMMAND \"\$full_path\""
    else
      __fzf_navigator_default_preview_file "$full_path"
    fi
  fi
}

__fzf_navigator_prompt() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local initial_dir=$(cat "$tmpdir/lock_initial_dir")

  if [[ "$current_dir" == "$initial_dir" ]]; then
    printf $'\e[1;36m%s\e[0m \e[1;36m>\e[0m ' "$(__fzf_navigator_tildify "$initial_dir")"
    return
  fi

  local common_parent=$(__fzf_navigator_common_parent "$initial_dir" "$current_dir")
  local is_current_child=false
  local is_current_parent=false
  local is_forked=false

  if [[ "$common_parent" == "$initial_dir" ]]; then
    is_current_child=true
  elif [[ "$common_parent" == "$current_dir" ]]; then
    is_current_parent=true
  else
    is_forked=true
  fi

  local subpath=""
  if $is_current_child; then
    if [[ "$initial_dir" == "/" ]]; then
      subpath="${current_dir#/}"
    else
      subpath="${current_dir#$initial_dir/}"
    fi
  elif $is_current_parent; then
    subpath="${initial_dir#$current_dir/}"
  else
    if [[ "$common_parent" == "/" ]]; then
      subpath="${current_dir#/}"
    else
      subpath="${current_dir#$common_parent/}"
    fi
  fi

  local cyan_bold=$'\e[1;36m'
  local magenta_bold=$'\e[1;35m'
  local white_bold=$'\e[1;37m'
  local grey=$'\e[0;90m'
  local reset=$'\e[0m'

  local display_dir=""
  local common_parent_color=""
  local subpath_color=""
  local separator="/"

  if $is_current_child; then
    display_dir="$common_parent"
    subpath="${subpath//\/>}"
    common_parent_color="$cyan_bold"
    subpath_color="$white_bold"
    separator=" ${cyan_bold}>${reset} "
  elif $is_current_parent; then
    display_dir="$current_dir"
    subpath="*"
    common_parent_color="$cyan_bold"
    subpath_color="$cyan_bold"
    separator=""
  else
    display_dir="$common_parent"
    common_parent_color="$cyan_bold"
    subpath_color="$white_bold"
    separator="${cyan_bold}*${reset} ${cyan_bold}>${reset} "
  fi

  if $is_forked && [[ "$common_parent" == "/" ]]; then
    separator="${cyan_bold}*${reset} ${cyan_bold}>${reset} "
  fi
  printf '%s%s%s%s%s%s%s %s>%s ' \
    "$common_parent_color" "$(__fzf_navigator_tildify "$display_dir")" "$reset" \
    "$separator" \
    "$subpath_color" "$subpath" "$reset" \
    "$common_parent_color" "$reset"
}

__fzf_navigator_footer() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local footer_content=""

  if [[ -f "$tmpdir/show_help" ]]; then
    local help_lines=()
    local action_order=(
      "open"
      "open_and_exit"
      "exit"
      "insert_selection"
      "copy_selection"
      "cancel"
      "go_to_parent"
      "go_back"
      "go_forward"
      "go_to_session_start"
      "go_home"
      "go_to_root"
      "toggle_hidden_files"
      "toggle_locked"
      "toggle_file_details"
      "toggle_recent_first"
      "toggle_help"
    )

    local bindings_list=$(bash -c 'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_parse_bindings')

    for action in "${action_order[@]}"; do
      local keys=$(echo "$bindings_list" | grep "^$action:" | cut -d: -f2)
      local display_action=$(echo "$action" | tr '_' ' ')
      for key in $keys; do
        local line=$(printf "%-18s%s" "$key" "$display_action")
        help_lines+=("$line")
      done
    done
    footer_content=$(IFS=$'\n'; echo "${help_lines[*]}")
  elif [[ -z "${FZF_NAVIGATOR_HIDE_HELP:-}" ]]; then
    local bindings_list=$(bash -c 'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_parse_bindings')
    local help_key=$(echo "$bindings_list" | grep "^toggle_help:" | cut -d: -f2 | head -n1)
    footer_content="$help_key for help"
  fi

  echo -e "$footer_content"
}

__fzf_navigator_info() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local initial_dir=$(cat "$tmpdir/lock_initial_dir")
  local indicators=""
  [[ -f "$tmpdir/show_hidden" ]] && indicators+="H"
  [[ -f "$tmpdir/locked" ]] && indicators+="L"
  [[ -f "$tmpdir/recent_first" ]] && indicators+="R"

  local initial_ref=""
  if [[ "$current_dir" != "$initial_dir" ]]; then
    if [[ "$initial_dir" == "$current_dir"/* ]] || [[ "$current_dir" == "/" && "$initial_dir" == /* ]]; then
      local rel_path
      if [[ "$current_dir" == "/" ]]; then
        rel_path="${initial_dir#/}"
      else
        rel_path="${initial_dir#$current_dir/}"
      fi
      initial_ref="*/$rel_path"
    elif [[ "$current_dir" == "$initial_dir"/* ]] || [[ "$initial_dir" == "/" && "$current_dir" != "/" ]]; then
      :
    else
      local common=$(__fzf_navigator_common_parent "$initial_dir" "$current_dir")
      local rel_path
      if [[ "$common" == "/" ]]; then
        rel_path="${initial_dir#/}"
      else
        rel_path="${initial_dir#$common/}"
      fi
      initial_ref="*/$rel_path"
    fi
  fi

  local suffix=""
  if [[ -n "$indicators" && -n "$initial_ref" ]]; then
    suffix="$indicators $initial_ref"
  elif [[ -n "$indicators" ]]; then
    suffix="$indicators"
  elif [[ -n "$initial_ref" ]]; then
    suffix="$initial_ref"
  fi

  if [[ -n "$suffix" ]]; then
    echo "$FZF_INFO $suffix"
  else
    echo "$FZF_INFO"
  fi
}

__fzf_navigator_transform_open() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")

  local history=()
  while IFS= read -r line; do
    history+=("$line")
  done < "$tmpdir/history"
  local history_index=$(cat "$tmpdir/history_index")
  local selections=()
  while IFS= read -r line; do
    selections+=("$line")
  done

  local filenames=()
  for line in "${selections[@]}"; do
    local filename=$(__fzf_navigator_extract_filename "$line")
    filenames+=("$filename")
  done

  if [[ ${#filenames[@]} -eq 0 || -z "${filenames[0]}" ]]; then
    echo "ignore"
    return
  fi

  if [[ ${#filenames[@]} -eq 1 ]]; then
    filename="${filenames[0]}"
    local full_path="${current_dir%/}/$filename"

    if [[ -d "$full_path" ]]; then
      echo "$full_path" > "$tmpdir/lock_current_dir"
      printf '%s\n' "${history[@]:0:$((history_index+1))}" > "$tmpdir/history"
      echo "$full_path" >> "$tmpdir/history"
      echo "$((history_index + 1))" > "$tmpdir/history_index"
      __fzf_navigator_nav_action
      return
    fi
  fi

  local paths=()
  for filename in "${filenames[@]}"; do
    local full_path="${current_dir%/}/$filename"
    paths+=("$full_path")
  done

  local cmd="${EDITOR:-vi}"
  for path in "${paths[@]}"; do
    cmd="$cmd $(printf %q "$path")"
  done

  echo "execute(printf '\\033[2J\\033[H' > /dev/tty; $cmd < /dev/tty > /dev/tty)+refresh-preview"
}

__fzf_navigator_transform_parent() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")

  local history=()
  while IFS= read -r line; do
    history+=("$line")
  done < "$tmpdir/history"
  local history_index=$(cat "$tmpdir/history_index")

  local parent=$(dirname "$current_dir")
  parent=$(__fzf_navigator_abspath "$parent")

  if [[ "$parent" != "$current_dir" ]]; then
    echo "$parent" > "$tmpdir/lock_current_dir"
    printf '%s\n' "${history[@]:0:$((history_index+1))}" > "$tmpdir/history"
    echo "$parent" >> "$tmpdir/history"
    echo "$((history_index + 1))" > "$tmpdir/history_index"
    __fzf_navigator_nav_action
  else
    echo "ignore"
  fi
}

__fzf_navigator_transform_back() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local history_index=$(cat "$tmpdir/history_index")

  if [[ $history_index -gt 0 ]]; then
    history_index=$((history_index - 1))
    local new_dir=$(sed -n "$((history_index + 1))p" "$tmpdir/history")

    echo "$new_dir" > "$tmpdir/lock_current_dir"
    echo "$history_index" > "$tmpdir/history_index"

    __fzf_navigator_nav_action
  else
    echo "ignore"
  fi
}

__fzf_navigator_transform_forward() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local history_index=$(cat "$tmpdir/history_index")
  local history_count=$(wc -l < "$tmpdir/history")

  if [[ $history_index -lt $((history_count - 1)) ]]; then
    history_index=$((history_index + 1))
    local new_dir=$(sed -n "$((history_index + 1))p" "$tmpdir/history")

    echo "$new_dir" > "$tmpdir/lock_current_dir"
    echo "$history_index" > "$tmpdir/history_index"

    __fzf_navigator_nav_action
  else
    echo "ignore"
  fi
}

__fzf_navigator_transform_session_start() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local session_start_dir=$(cat "$tmpdir/session_start_dir")

  if [[ "$session_start_dir" != "$current_dir" ]]; then
    local history=()
    while IFS= read -r line; do
      history+=("$line")
    done < "$tmpdir/history"
    local history_index=$(cat "$tmpdir/history_index")
    echo "$session_start_dir" > "$tmpdir/lock_current_dir"
    printf '%s\n' "${history[@]:0:$((history_index+1))}" > "$tmpdir/history"
    echo "$session_start_dir" >> "$tmpdir/history"
    echo "$((history_index + 1))" > "$tmpdir/history_index"
    __fzf_navigator_nav_action
  else
    echo "ignore"
  fi
}

__fzf_navigator_transform_go_home() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local history=()
  while IFS= read -r line; do
    history+=("$line")
  done < "$tmpdir/history"
  local history_index=$(cat "$tmpdir/history_index")
  local home_dir="$HOME"

  if [[ "$home_dir" != "$current_dir" ]]; then
    echo "$home_dir" > "$tmpdir/lock_current_dir"
    printf '%s\n' "${history[@]:0:$((history_index+1))}" > "$tmpdir/history"
    echo "$home_dir" >> "$tmpdir/history"
    echo "$((history_index + 1))" > "$tmpdir/history_index"
    __fzf_navigator_nav_action
  else
    echo "ignore"
  fi
}

__fzf_navigator_transform_go_to_root() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local history=()
  while IFS= read -r line; do
    history+=("$line")
  done < "$tmpdir/history"
  local history_index=$(cat "$tmpdir/history_index")
  local root_dir="/"

  if [[ "$root_dir" != "$current_dir" ]]; then
    echo "$root_dir" > "$tmpdir/lock_current_dir"
    printf '%s\n' "${history[@]:0:$((history_index+1))}" > "$tmpdir/history"
    echo "$root_dir" >> "$tmpdir/history"
    echo "$((history_index + 1))" > "$tmpdir/history_index"
    __fzf_navigator_nav_action
  else
    echo "ignore"
  fi
}

__fzf_navigator_transform_toggle_hidden() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local flag_file="$tmpdir/show_hidden"

  if [[ -f "$flag_file" ]]; then
    rm "$flag_file"
  else
    touch "$flag_file"
  fi

  echo "reload-sync(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_reload')"
}

__fzf_navigator_transform_toggle_details() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local flag_file="$tmpdir/show_details"

  if [[ -f "$flag_file" ]]; then
    rm "$flag_file"
  else
    touch "$flag_file"
  fi

  echo "reload-sync(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_reload')"
}

__fzf_navigator_transform_toggle_recent_first() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local flag_file="$tmpdir/recent_first"

  if [[ -f "$flag_file" ]]; then
    rm "$flag_file"
  else
    touch "$flag_file"
  fi

  echo "reload-sync(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_reload')"
}

__fzf_navigator_transform_toggle_locked() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local flag_file="$tmpdir/locked"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local initial_dir=$(cat "$tmpdir/lock_initial_dir")

  if [[ -f "$flag_file" ]]; then
    rm "$flag_file"
    if [[ "$current_dir" != "$initial_dir" ]]; then
      echo "become(echo //cd)"
    else
      echo "transform-prompt(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_prompt')+transform-footer(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_footer')+reload-sync(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_reload')"
    fi
  else
    touch "$flag_file"
    echo "transform-prompt(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_prompt')+transform-footer(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_footer')+reload-sync(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_reload')"
  fi
}

__fzf_navigator_transform_cancel() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local initial_dir=$(cat "$tmpdir/lock_initial_dir")

  if [[ "$current_dir" != "$initial_dir" ]]; then
    local history=()
    while IFS= read -r line; do
      history+=("$line")
    done < "$tmpdir/history"
    local history_index=$(cat "$tmpdir/history_index")
    echo "$initial_dir" > "$tmpdir/lock_current_dir"
    printf '%s\n' "${history[@]:0:$((history_index+1))}" > "$tmpdir/history"
    echo "$initial_dir" >> "$tmpdir/history"
    echo "$((history_index + 1))" > "$tmpdir/history_index"
    __fzf_navigator_nav_action
  else
    echo "become(echo //esc)"
  fi
}

__fzf_navigator_transform_open_and_exit() {
  local tmpdir="$FZF_NAVIGATOR_TMPDIR"
  local current_dir=$(cat "$tmpdir/lock_current_dir")
  local selections=()
  while IFS= read -r line; do
    selections+=("$line")
  done

  local filenames=()
  for line in "${selections[@]}"; do
    local filename=$(__fzf_navigator_extract_filename "$line")
    filenames+=("$filename")
  done

  if [[ ${#filenames[@]} -eq 0 || -z "${filenames[0]}" ]]; then
    echo "ignore"
    return
  fi

  if [[ ${#filenames[@]} -eq 1 ]]; then
    local filename="${filenames[0]}"
    local full_path="${current_dir%/}/$filename"
    if [[ -d "$full_path" ]]; then
      echo "$full_path" > "$tmpdir/lock_current_dir"
      echo "become(echo //exit)"
    else
      echo "become(echo //open; cat {+f})"
    fi
  else
    echo "become(echo //open; cat {+f})"
  fi
}

__fzf_navigator_parse_bindings() {
  # Store bindings as newline-delimited "action:key" pairs
  local bindings="open:space
open_and_exit:ctrl-o
exit:ctrl-space
insert_selection:enter
copy_selection:ctrl-y
cancel:esc
go_to_parent:ctrl-d
go_back:ctrl-alt-o
go_forward:ctrl-alt-i
go_to_session_start:[
go_home:\\
go_to_root:/
toggle_locked:ctrl-l
toggle_hidden_files:alt-h
toggle_file_details:ctrl-g
toggle_recent_first:ctrl-r
toggle_help:?"

  local valid_actions="open open_and_exit exit insert_selection copy_selection cancel go_to_parent go_back go_forward go_to_session_start go_home go_to_root toggle_locked toggle_hidden_files toggle_file_details toggle_recent_first toggle_help"

  if [[ -n "${FZF_NAVIGATOR_BINDINGS:-}" ]]; then
    # Collect actions that have user-specified bindings
    local user_actions=""
    local saved_ifs="$IFS"
    IFS=','
    for user_binding in $FZF_NAVIGATOR_BINDINGS; do
      IFS="$saved_ifs"
      user_binding="${user_binding#"${user_binding%%[![:space:]]*}"}"
      user_binding="${user_binding%"${user_binding##*[![:space:]]}"}"
      [[ -z "$user_binding" ]] && continue
      local action="${user_binding#*:}"
      user_actions="${user_actions}${action}"$'\n'
    done
    IFS="$saved_ifs"

    # Remove default bindings for actions that have user overrides
    local new_bindings=""
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local line_action="${line%%:*}"
      local found=false
      while IFS= read -r ua; do
        [[ -n "$ua" && "$ua" == "$line_action" ]] && { found=true; break; }
      done <<< "$user_actions"
      $found || new_bindings="${new_bindings}${line}"$'\n'
    done <<< "$bindings"
    bindings="$new_bindings"

    # Add user bindings
    IFS=','
    for user_binding in $FZF_NAVIGATOR_BINDINGS; do
      IFS="$saved_ifs"
      user_binding="${user_binding#"${user_binding%%[![:space:]]*}"}"
      user_binding="${user_binding%"${user_binding##*[![:space:]]}"}"
      [[ -z "$user_binding" ]] && continue

      local key="${user_binding%%:*}"
      local new_action="${user_binding#*:}"

      # Validate action exists
      local action_valid=false
      for valid in $valid_actions; do
        if [[ "$valid" == "$new_action" ]]; then
          action_valid=true
          break
        fi
      done
      $action_valid || continue

      # Remove this key from other actions, add new binding
      new_bindings=""
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local line_key="${line#*:}"
        [[ "$line_key" != "$key" ]] && new_bindings="${new_bindings}${line}"$'\n'
      done <<< "$bindings"
      bindings="${new_bindings}${new_action}:${key}"
    done
    IFS="$saved_ifs"
  fi

  # Output all non-empty bindings
  while IFS= read -r line; do
    [[ -n "$line" ]] && printf '%s\n' "$line"
  done <<< "$bindings"
}

__fzf_navigator_save_state() {
  READLINE_LINE_SAVED="$READLINE_LINE"
  READLINE_POINT_SAVED="$READLINE_POINT"
  READLINE_LINE=""
  READLINE_POINT=0
}

__fzf_navigator_restore_state() {
  READLINE_LINE="$READLINE_LINE_SAVED"
  READLINE_POINT="$READLINE_POINT_SAVED"
}

__fzf_navigator_final_restore() {
  if [[ "${__FZF_NAV_PATHS_INSERTED:-0}" -eq 1 ]]; then
    if [[ "${__FZF_NAV_PWD_CHANGED:-0}" -eq 1 ]]; then
      local escaped=$(printf '%s' "$READLINE_LINE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g')
      local cursor_move=""
      if [[ "$READLINE_POINT" -eq 0 ]]; then
        cursor_move='\C-a'
      else
        local move_back=$((${#READLINE_LINE} - READLINE_POINT))
        if [[ "$move_back" -gt 0 ]]; then
          cursor_move=$(printf '\\C-b%.0s' $(seq 1 $move_back))
        fi
      fi
      bind '"\305":"\C-m'"$escaped$cursor_move"'"'
      READLINE_LINE=""
      READLINE_POINT=0
    else
      bind '"\305":""'
    fi
  elif [[ "${__FZF_NAV_PWD_CHANGED:-0}" -eq 1 ]]; then
    bind '"\305":"\C-m"'
    READLINE_LINE=""
    READLINE_POINT=0
  else
    bind '"\305":""'
    READLINE_LINE="$READLINE_LINE_SAVED"
    READLINE_POINT="$READLINE_POINT_SAVED"
  fi
  __FZF_NAV_PWD_CHANGED=0
  __FZF_NAV_PATHS_INSERTED=0
}

__fzf_navigator() {
  local is_zsh=false
  local is_bash=false
  if [ -n "$ZSH_VERSION" ]; then
    is_zsh=true
  elif [ -n "$BASH_VERSION" ]; then
    is_bash=true
  fi

  local selection filename dir
  local is_top_level=false
  if [[ -z "$__FZF_NAV_ORIGINAL_PWD" ]]; then
    export __FZF_NAV_ORIGINAL_PWD="$PWD"
    is_top_level=true
  fi

  local tmpdir="/tmp/fzf-navigator/$$"
  mkdir -p "$tmpdir" || { echo "fzf-navigator: failed to create $tmpdir" >&2; return 1; }

  if [[ -n "${__FZF_NAV_RESET_CURRENT_DIR:-}" ]]; then
    [[ -n "$__FZF_NAV_RESET_SHOW_HIDDEN" ]] && touch "$tmpdir/show_hidden"
    [[ -n "$__FZF_NAV_RESET_SHOW_DETAILS" ]] && touch "$tmpdir/show_details"
    [[ -n "$__FZF_NAV_RESET_RECENT_FIRST" ]] && touch "$tmpdir/recent_first"
    [[ -n "$__FZF_NAV_RESET_SHOW_HELP" ]] && touch "$tmpdir/show_help"
    [[ -n "$__FZF_NAV_RESET_LOCKED" ]] && touch "$tmpdir/locked"
    printf '%s' "$__FZF_NAV_RESET_HISTORY" | tr $'\x1E' '\n' > "$tmpdir/history"
    echo "$__FZF_NAV_RESET_HISTORY_INDEX" > "$tmpdir/history_index"
    echo "$__FZF_NAV_RESET_CURRENT_DIR" > "$tmpdir/lock_current_dir"
    echo "$PWD" > "$tmpdir/lock_initial_dir"
    echo "$__FZF_NAV_RESET_SESSION_START_DIR" > "$tmpdir/session_start_dir"
    unset __FZF_NAV_RESET_SHOW_HIDDEN
    unset __FZF_NAV_RESET_SHOW_DETAILS
    unset __FZF_NAV_RESET_RECENT_FIRST
    unset __FZF_NAV_RESET_SHOW_HELP
    unset __FZF_NAV_RESET_LOCKED
    unset __FZF_NAV_RESET_HISTORY
    unset __FZF_NAV_RESET_HISTORY_INDEX
    unset __FZF_NAV_RESET_CURRENT_DIR
    unset __FZF_NAV_RESET_SESSION_START_DIR
  else
    if [[ ! -f "$tmpdir/history" ]]; then
      echo "$PWD" > "$tmpdir/history"
      echo "0" > "$tmpdir/history_index"
      echo "$PWD" > "$tmpdir/lock_current_dir"
      rm -f "$tmpdir/show_hidden"
      [[ -n "${FZF_NAVIGATOR_SHOW_HIDDEN:-}" ]] && touch "$tmpdir/show_hidden"
      [[ -n "${FZF_NAVIGATOR_LOCK_CWD:-}" ]] && touch "$tmpdir/locked"
    else
      local history_index=$(cat "$tmpdir/history_index")
      local last_line=$(sed -n "$((history_index + 1))p" "$tmpdir/history")
      if [[ "$last_line" != "$PWD" ]]; then
        echo "$PWD" >> "$tmpdir/history"
        history_index=$((history_index + 1))
        echo "$history_index" > "$tmpdir/history_index"
      fi
    fi
    echo "$PWD" > "$tmpdir/lock_current_dir"
    echo "$PWD" > "$tmpdir/lock_initial_dir"
    echo "$PWD" > "$tmpdir/session_start_dir"
    rm -f "$tmpdir/locked"
    [[ -n "${FZF_NAVIGATOR_LOCK_CWD:-}" ]] && touch "$tmpdir/locked"
    rm -f "$tmpdir/show_hidden"
    [[ -n "${FZF_NAVIGATOR_SHOW_HIDDEN:-}" ]] && touch "$tmpdir/show_hidden"
    rm -f "$tmpdir/show_help"
    rm -f "$tmpdir/show_details"
    rm -f "$tmpdir/recent_first"
  fi

  export FZF_NAVIGATOR_TMPDIR="$tmpdir"

  local preview_cmd="bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_preview \"\$1\"' _ {}"
  local fzf_bindings=()
  local help_key=""
  local bind_str=""

  while IFS=: read -r action key; do
    bind_str=""
    case "$action" in
      open)
        bind_str="${key}:transform(printf '%s\\n' {+} | bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_open')"
        ;;
      open_and_exit)
        bind_str="${key}:transform(printf '%s\\n' {+} | bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_open_and_exit')"
        ;;
      go_to_parent)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_parent')"
        ;;
      go_back)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_back')"
        ;;
      go_forward)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_forward')"
        ;;
      go_to_session_start)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_session_start')"
        ;;
      go_home)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_go_home')"
        ;;
      go_to_root)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_go_to_root')"
        ;;
      toggle_locked)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_toggle_locked')"
        ;;
      toggle_hidden_files)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_toggle_hidden')"
        ;;
      toggle_file_details)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_toggle_details')"
        ;;
      toggle_recent_first)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_toggle_recent_first')"
        ;;
      cancel)
        bind_str="${key}:transform(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_transform_cancel')"
        ;;
      copy_selection)
        bind_str="${key}:become(echo //copy; cat {+f})"
        ;;
      insert_selection)
        bind_str="${key}:become(echo //insert; cat {+f})"
        ;;
      exit)
        bind_str="${key}:become(echo //exit)"
        ;;
      toggle_help)
        help_key="${key}"
        ;;
    esac
    [[ -n "$bind_str" ]] && fzf_bindings+=("--bind" "$bind_str")
  done < <(bash -c 'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_parse_bindings')

  local help_binding=""
  if [[ -n "$help_key" ]]; then
    help_binding="${help_key}"':transform-footer:
    if [[ ! -f '"$tmpdir"'/show_help ]]; then
      touch '"$tmpdir"'/show_help
    else
      rm '"$tmpdir"'/show_help
    fi
    bash -c '"'"'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_footer'"'"
    fzf_bindings+=("--bind" "$help_binding")
  fi

  local initial_footer=$(bash -c 'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_footer')
  local fzf_custom_opts=()
  if [[ -n "$FZF_NAVIGATOR_OPTIONS" ]]; then
    if $is_zsh; then
      read -A fzf_custom_opts <<< "$FZF_NAVIGATOR_OPTIONS"
    else
      read -ra fzf_custom_opts <<< "$FZF_NAVIGATOR_OPTIONS"
    fi
  fi

  selection=$(bash -c 'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_reload' | fzf \
    --no-bold \
    --multi \
    --tiebreak=begin \
    --footer-border none \
    --color 'query::bold' \
    --preview "$preview_cmd" \
    --preview-window '60%,<80(down,50%)' \
    "${fzf_custom_opts[@]}" \
    --ansi \
    --no-clear \
    --height 100% \
    --delimiter='[[:space:]]+' \
    --prompt="$(bash -c 'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_prompt')" \
    --footer="$initial_footer" \
    --info-command='bash -c '"'"'source "$FZF_NAVIGATOR_DIR/fzf-navigator.sh"; __fzf_navigator_info'"'"'' \
    --bind "result:enable-search+clear-query+transform-prompt(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_prompt')+transform-footer(bash -c 'source \"\$FZF_NAVIGATOR_DIR/fzf-navigator.sh\"; __fzf_navigator_footer')+unbind(result)" \
    --bind 'start:unbind(result)' \
    "${fzf_bindings[@]}")

  if [[ -z "$selection" || "$selection" == "//esc" ]]; then
    :
  elif [[ "$selection" == "//cd" ]]; then
    dir=$(cat "$tmpdir/lock_current_dir")
    export __FZF_NAV_RESET_SHOW_HIDDEN=""
    [[ -f "$tmpdir/show_hidden" ]] && export __FZF_NAV_RESET_SHOW_HIDDEN="1"
    export __FZF_NAV_RESET_SHOW_DETAILS=""
    [[ -f "$tmpdir/show_details" ]] && export __FZF_NAV_RESET_SHOW_DETAILS="1"
    export __FZF_NAV_RESET_RECENT_FIRST=""
    [[ -f "$tmpdir/recent_first" ]] && export __FZF_NAV_RESET_RECENT_FIRST="1"
    export __FZF_NAV_RESET_SHOW_HELP=""
    [[ -f "$tmpdir/show_help" ]] && export __FZF_NAV_RESET_SHOW_HELP="1"
    export __FZF_NAV_RESET_LOCKED=""
    [[ -f "$tmpdir/locked" ]] && export __FZF_NAV_RESET_LOCKED="1"
    export __FZF_NAV_RESET_HISTORY=$(cat "$tmpdir/history" | tr '\n' $'\x1E')
    export __FZF_NAV_RESET_HISTORY_INDEX=$(cat "$tmpdir/history_index")
    export __FZF_NAV_RESET_CURRENT_DIR="$dir"
    export __FZF_NAV_RESET_SESSION_START_DIR=$(cat "$tmpdir/session_start_dir")
    cd "$dir"
    [[ "$dir" != "$tmpdir"/* && "$dir" != "$tmpdir" ]] && rm -rf "$tmpdir"
    __fzf_navigator
  elif [[ "$selection" == "//exit" ]]; then
    dir=$(cat "$tmpdir/lock_current_dir")
    cd "$dir"
  elif [[ "$selection" == //open* ]]; then
    local selections="${selection#//open$'\n'}"
    local dir=$(cat "$tmpdir/lock_current_dir")
    local paths=()
    while IFS= read -r line; do
      local filename=$(__fzf_navigator_extract_filename "$line")
      local full_path="$dir/$filename"
      paths+=("$full_path")
    done <<< "$selections"
    printf '\033[2J\033[H'
    ${EDITOR:-vi} "${paths[@]}"
    __FZF_NAV_SCREEN_CLEARED=1
  elif [[ "$selection" == //copy* ]]; then
    local selections="${selection#//copy$'\n'}"
    local dir=$(cat "$tmpdir/lock_current_dir")
    local paths=()
    while IFS= read -r line; do
      local filename=$(__fzf_navigator_extract_filename "$line")
      local abs_path=$(__fzf_navigator_abspath "$dir/$filename")
      paths+=("$(printf '%q' "$abs_path")")
    done <<< "$selections"
    local all_paths="${paths[*]}"
    if command -v wl-copy &> /dev/null; then
      printf '%s' "$all_paths" | wl-copy
    elif command -v xclip &> /dev/null; then
      printf '%s' "$all_paths" | xclip -selection clipboard
    elif command -v pbcopy &> /dev/null; then
      printf '%s' "$all_paths" | pbcopy
    fi
  elif [[ "$selection" == //insert* ]]; then
    local selections="${selection#//insert$'\n'}"
    local dir=$(cat "$tmpdir/lock_current_dir")
    local paths=()
    while IFS= read -r line; do
      local filename=$(__fzf_navigator_extract_filename "$line")
      local rel_path=$(__fzf_navigator_relpath "$dir/$filename" "$PWD")
      paths+=("$(printf '%q' "$rel_path")")
    done <<< "$selections"
    local all_paths="${paths[*]}"
    export __FZF_NAV_PATHS_INSERTED_SESSION=1
    if $is_zsh; then
      if [[ -z "$LBUFFER" ]]; then
        RBUFFER=" ${all_paths}$RBUFFER"
      else
        [[ "${LBUFFER: -1}" != " " ]] && LBUFFER="$LBUFFER "
        LBUFFER="$LBUFFER${all_paths} "
      fi
    else
      if [[ -z "$READLINE_LINE_SAVED" ]]; then
        READLINE_LINE=" ${all_paths}"
        READLINE_POINT=0
      else
        local left="${READLINE_LINE_SAVED:0:$READLINE_POINT_SAVED}"
        local right="${READLINE_LINE_SAVED:$READLINE_POINT_SAVED}"
        [[ "${left: -1}" != " " ]] && left="$left "
        READLINE_LINE="${left}${all_paths} ${right}"
        READLINE_POINT=${#left}
        READLINE_POINT=$((READLINE_POINT + ${#all_paths} + 1))
      fi
    fi
  fi

  if $is_top_level; then
    tput rmcup
    local paths_inserted=false
    if [[ "$selection" == //insert* ]] || [[ "${__FZF_NAV_PATHS_INSERTED_SESSION:-0}" -eq 1 ]]; then
      paths_inserted=true
    fi
    if $is_zsh; then
      zle autosuggest-clear 2>/dev/null
      if [[ "$PWD" != "$__FZF_NAV_ORIGINAL_PWD" ]]; then
        if $paths_inserted; then
          __FZF_NAV_RESTORE_CURSOR=$CURSOR
          print -rz -- "$BUFFER"
        fi
        BUFFER=""
        zle accept-line
      else
        zle reset-prompt
      fi
    else
      if [[ "$PWD" != "$__FZF_NAV_ORIGINAL_PWD" ]]; then
        __FZF_NAV_PWD_CHANGED=1
      else
        __FZF_NAV_PWD_CHANGED=0
      fi
      if $paths_inserted; then
        __FZF_NAV_PATHS_INSERTED=1
      else
        __FZF_NAV_PATHS_INSERTED=0
      fi
    fi
    unset __FZF_NAV_ORIGINAL_PWD
    unset __FZF_NAV_PATHS_INSERTED_SESSION
  fi
}

if [[ $- == *i* ]]; then
  __fzf_navigator_translate_key() {
    local key="$1"
    case "$key" in
      ctrl-space) [[ -n "$ZSH_VERSION" ]] && echo '^ ' || echo '\C- ' ;;
      ctrl-*)
        local char="${key#ctrl-}"
        [[ -n "$ZSH_VERSION" ]] && echo "^${char}" || echo "\\C-${char}"
        ;;
      alt-space) echo $'\e ' ;;
      alt-*)
        local char="${key#alt-}"
        echo $'\e'"${char}"
        ;;
      *) echo "$key" ;;
    esac
  }

  __fzf_nav_key=$(__fzf_navigator_translate_key "$FZF_NAVIGATOR_KEY")

  if [[ -n "$ZSH_VERSION" ]]; then
    __fzf_navigator_zle_line_init() {
      if [[ -n "$__FZF_NAV_RESTORE_CURSOR" ]]; then
        CURSOR=$__FZF_NAV_RESTORE_CURSOR
        unset __FZF_NAV_RESTORE_CURSOR
      fi
    }
    autoload -Uz add-zle-hook-widget
    add-zle-hook-widget line-init __fzf_navigator_zle_line_init
    zle -N __fzf_navigator
    bindkey "$__fzf_nav_key" __fzf_navigator
  elif [[ -n "$BASH_VERSION" ]]; then
    bind -x '"\300": __fzf_navigator_save_state'
    bind -x '"\301": __fzf_navigator_final_restore'
    bind -x '"\302": __fzf_navigator'
    bind "\"$__fzf_nav_key\":\"\300\302\301\305\""
  fi
fi
