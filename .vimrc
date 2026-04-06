


" =============================================================================
" Netrw QuickOpen (Custom) plugin
" =============================================================================
"
" Search UX
set hlsearch
set incsearch

" Netrw relies on recursive <Plug> mappings; keep 'remap' enabled (default).
set remap

" Auto-open in netrw when your / search becomes unique.
let g:netrw_quickopen_enable = 1
let g:netrw_quickopen_show_count = 1
let g:netrw_quickopen_idle_ms = 60
let g:netrw_quickopen_open_delay_ms = 10
" After auto-entering a directory, immediately prompt for the next / search.
let g:netrw_quickopen_chain_search = 1
let g:netrw_quickopen_chain_delay_ms = 20
" When the unique match is a file, open it in a right-side vsplit.
let g:netrw_quickopen_file_vsplit = 1

let s:netrw_qo_timer = -1
let s:netrw_qo_pending_open = 0
let s:netrw_qo_pending_winid = 0
let s:netrw_qo_pending_bufnr = 0
let s:netrw_qo_pending_pat = ''
let s:netrw_qo_saved_cmdheight = -1

function! s:NetrwQo_FirstListLnum() abort
  if exists('w:netrw_bannercnt') && type(w:netrw_bannercnt) == v:t_number && w:netrw_bannercnt > 0
    return w:netrw_bannercnt
  endif
  return 1
endfunction

function! s:NetrwQo_IsBannerLnum(lnum) abort
  if exists('w:netrw_bannercnt') && type(w:netrw_bannercnt) == v:t_number && w:netrw_bannercnt > 0
    return a:lnum < w:netrw_bannercnt
  endif
  " Fallback: banner lines usually start with a double-quote.
  return getline(a:lnum) =~# '^"'
endfunction

function! s:NetrwQo_IsActive() abort
  return get(g:, 'netrw_quickopen_enable', 1) && &filetype ==# 'netrw'
endfunction

function! s:NetrwQo_Count(pat) abort
  if empty(a:pat)
    return {}
  endif

  " Fast/low-risk: count matching *entries* (skip the banner); only distinguish 0 / 1 / 2+.
  if !s:NetrwQo_IsActive()
    return {}
  endif
  try
    let l:total = 0
    let l:start = s:NetrwQo_FirstListLnum()
    for l:lnum in range(l:start, line('$'))
      if s:NetrwQo_IsBannerLnum(l:lnum)
        continue
      endif
      if getline(l:lnum) =~ a:pat
        let l:total += 1
        if l:total > 2
          let l:total = 3
          break
        endif
      endif
    endfor
    let l:res = #{total: l:total, incomplete: 0}
  catch
    let l:res = {}
  endtry
  return l:res
endfunction

function! s:NetrwQo_EchoCount(res) abort
  if !get(g:, 'netrw_quickopen_show_count', 1)
    return
  endif
  if empty(a:res)
    echo '[netrw matches: ?]'
    return
  endif
  let l:total = get(a:res, 'total', 0)
  let l:incomplete = get(a:res, 'incomplete', 0)
  if l:incomplete ==# 2 || l:total ==# 3
    echo '[netrw matches: 2+]'
  else
    echo printf('[netrw matches: %d]', l:total)
  endif
endfunction

function! s:NetrwQo_OpenUnderCursor() abort
  if &filetype !=# 'netrw'
    return
  endif
  if s:NetrwQo_IsBannerLnum(line('.'))
    return
  endif

  let l:islocal = !exists('b:netrw_method') || b:netrw_method == 0
  try
    let l:word = netrw#Call('NetrwGetWord')
    if empty(l:word)
      return
    endif

    " Determine if the entry is a directory (symlinked directories may not end with '/').
    let l:isdir = (l:word =~# '/$')
    if !l:isdir && l:islocal
      let l:isdir = isdirectory(netrw#Call('NetrwFile', l:word))
    endif

    " Files: open in a right-side vsplit; Dirs: open normally.
    if !l:isdir && get(g:, 'netrw_quickopen_file_vsplit', 1)
      let l:had_altv = exists('g:netrw_altv')
      let l:save_altv = l:had_altv ? g:netrw_altv : 0
      try
        let g:netrw_altv = 1
        call netrw#Call('NetrwSplit', l:islocal ? 5 : 2)
      finally
        if l:had_altv
          let g:netrw_altv = l:save_altv
        else
          unlet g:netrw_altv
        endif
      endtry
      return
    endif

    let l:target = netrw#Call('NetrwBrowseChgDir', l:islocal ? 1 : 0, l:word)
    if l:islocal
      call netrw#LocalBrowseCheck(l:target)
    else
      call netrw#Call('NetrwBrowse', 0, l:target)
    endif

    if l:isdir && get(g:, 'netrw_quickopen_chain_search', 1) && &filetype ==# 'netrw'
      call timer_start(get(g:, 'netrw_quickopen_chain_delay_ms', 20), function('s:NetrwQo_StartSearch'))
    endif
  catch
    " Keep failures non-fatal while typing.
  endtry
endfunction

function! s:NetrwQo_StartSearch(timer) abort
  if !s:NetrwQo_IsActive() || mode() ==# 'c'
    return
  endif
  " Avoid starting a search in the banner area.
  let l:start = s:NetrwQo_FirstListLnum()
  if l:start > 1 && line('.') < l:start
    call cursor(l:start, 1)
  endif
  call feedkeys('/', 'nt')
endfunction

function! s:NetrwQo_OpenPending(timer) abort
  if !s:netrw_qo_pending_open
    return
  endif

  if mode() ==# 'c'
    " Still in cmdline mode; try again shortly.
    call timer_start(get(g:, 'netrw_quickopen_open_delay_ms', 10), function('s:NetrwQo_OpenPending'))
    return
  endif
  let l:winid = s:netrw_qo_pending_winid
  let l:bufnr = s:netrw_qo_pending_bufnr
  let s:netrw_qo_pending_open = 0
  let s:netrw_qo_pending_winid = 0
  let s:netrw_qo_pending_bufnr = 0

  if l:winid != 0
    call win_gotoid(l:winid)
  endif
  if l:bufnr != 0 && bufnr('%') != l:bufnr
    return
  endif

  let l:pat = s:netrw_qo_pending_pat
  let s:netrw_qo_pending_pat = ''
  if !empty(l:pat)
    " Move to the unique matching entry (ignoring the banner) before opening.
    let l:start = s:NetrwQo_FirstListLnum()
    let l:found = 0
    try
      for l:lnum in range(l:start, line('$'))
        if s:NetrwQo_IsBannerLnum(l:lnum)
          continue
        endif
        if getline(l:lnum) =~ l:pat
          if l:found != 0
            return
          endif
          let l:found = l:lnum
        endif
      endfor
    catch
      return
    endtry
    if l:found == 0
      return
    endif
    call cursor(l:found, 1)
  endif

  call s:NetrwQo_OpenUnderCursor()
endfunction

function! s:NetrwQo_Tick(timer) abort
  if getcmdtype() !=# '/' || !s:NetrwQo_IsActive()
    return
  endif

  let l:pat = getcmdline()
  let l:res = s:NetrwQo_Count(l:pat)
  call s:NetrwQo_EchoCount(l:res)

  if !empty(l:res) && get(l:res, 'incomplete', 0) ==# 0 && get(l:res, 'total', 0) ==# 1 && !s:netrw_qo_pending_open
    let s:netrw_qo_pending_open = 1
    let s:netrw_qo_pending_winid = win_getid()
    let s:netrw_qo_pending_bufnr = bufnr('%')
    let s:netrw_qo_pending_pat = l:pat
    " Accept the search; open happens on CmdlineLeave.
    call feedkeys("\<CR>", 'nt')
  endif
endfunction

function! s:NetrwQo_OnCmdlineEnter() abort
  if getcmdtype() !=# '/' || !s:NetrwQo_IsActive()
    return
  endif

  let s:netrw_qo_saved_cmdheight = &cmdheight
  if &cmdheight < 2
    set cmdheight=2
  endif
endfunction

function! s:NetrwQo_OnCmdlineChanged() abort
  if getcmdtype() !=# '/' || !s:NetrwQo_IsActive()
    return
  endif

  if s:netrw_qo_timer != -1
    call timer_stop(s:netrw_qo_timer)
  endif
  let s:netrw_qo_timer = timer_start(get(g:, 'netrw_quickopen_idle_ms', 60), function('s:NetrwQo_Tick'))
endfunction

function! s:NetrwQo_OnCmdlineLeave() abort
  if s:netrw_qo_timer != -1
    call timer_stop(s:netrw_qo_timer)
    let s:netrw_qo_timer = -1
  endif

  if s:netrw_qo_saved_cmdheight >= 0
    let &cmdheight = s:netrw_qo_saved_cmdheight
    let s:netrw_qo_saved_cmdheight = -1
  endif

  if s:netrw_qo_pending_open
    call timer_start(get(g:, 'netrw_quickopen_open_delay_ms', 10), function('s:NetrwQo_OpenPending'))
  endif
endfunction

augroup netrw_quickopen
  autocmd!
  autocmd CmdlineEnter / call s:NetrwQo_OnCmdlineEnter()
  autocmd CmdlineChanged / call s:NetrwQo_OnCmdlineChanged()
  autocmd CmdlineLeave / call s:NetrwQo_OnCmdlineLeave()
augroup END

" =============================================================================
" Netrw QuickOpen (Custom) Documentation
" =============================================================================
"
" **What this does**
" - While you type a `/pattern` search inside a netrw directory listing, it shows
"   how many *file/dir entries* match (excluding the netrw banner/menu at top).
" - When the match becomes unique (exactly 1 entry), it automatically:
"   1. accepts the search
"   2. moves to the unique matching entry
"   3. opens it
"   4. if it was a directory: immediately prompts for a new `/` search
"      if it was a file: opens it in a right-side vertical split (optional)
"
" **How to use**
" 1. Open netrw with `:e .`, `:Explore`, `:Lexplore`, etc.
" 2. Press `/` and type.
" 3. Watch the command-line message: `[netrw matches: 0|1|2+]`.
" 4. When it reaches `1`, the entry opens automatically.
"
" **User settings (globals)**
" - `g:netrw_quickopen_enable` (default 1)
"   Master toggle for this behavior.
" - `g:netrw_quickopen_show_count` (default 1)
"   Echo `[netrw matches: ...]` while typing.
" - `g:netrw_quickopen_idle_ms` (default 60)
"   Debounce delay (ms) after each keystroke before recomputing match count.
" - `g:netrw_quickopen_open_delay_ms` (default 10)
"   Delay (ms) between accepting the search and performing the open.
" - `g:netrw_quickopen_chain_search` (default 1)
"   After auto-entering a directory, automatically start a fresh `/` prompt.
" - `g:netrw_quickopen_chain_delay_ms` (default 20)
"   Delay (ms) before starting that next `/` prompt.
" - `g:netrw_quickopen_file_vsplit` (default 1)
"   If the unique match is a file, open it in a vsplit to the right.
"
" **How it works (high-level)**
" - Uses Vim command-line autocommands limited to `/` searches:
"   - `CmdlineEnter`  : ensures enough cmdline space (cmdheight) for the counter
"   - `CmdlineChanged`: starts/restarts a short timer (debounce)
"   - `CmdlineLeave`  : if a unique match was detected, schedules the open
" - The timer callback (`s:NetrwQo_Tick`) reads the in-progress search text with
"   `getcmdline()` and counts matches by scanning the netrw buffer lines.
" - Banner/menu lines are ignored via `w:netrw_bannercnt` when available.
"   Fallback banner detection: line starts with `"`.
" - For speed, the count intentionally caps at `2+`.
" - When it detects exactly one matching entry:
"   - it stores the pattern and window/buffer identity
"   - it feeds `<CR>` to accept the search
"   - after leaving cmdline mode it moves the cursor to the unique match and
"     opens it using netrw internals.
"
" **Open behavior details**
" - Directory open:
"   - local: `netrw#LocalBrowseCheck(...)`
"   - remote: `netrw#Call('NetrwBrowse', ...)`
" - File open (when `g:netrw_quickopen_file_vsplit=1`):
"   - uses `netrw#Call('NetrwSplit', ...)` and temporarily sets `g:netrw_altv=1`
"     to force a right-side vertical split.
"   - see `:help g:netrw_altv` and `:help netrw-v`
"
" **Notes / limitations**
" - Matching is line-based (`getline() =~ pattern`) against whatever netrw is
"   displaying. In long/wide list styles, your pattern can match metadata too.
"   If you want the most "filename-only" behavior, use thin listing (`i` key):
"   `:help netrw-i`.
" - Remote directory detection is best-effort (often relies on trailing `/`).
"
" **Troubleshooting**
" - If `<CR>` stops opening items in netrw, make sure you did not globally set
"   `set noremap`. Netrw depends on recursive `<Plug>` mappings.
"   See `:help 'remap'` and `:help netrw-cr`.
" - Disable quickly with: `:let g:netrw_quickopen_enable = 0`
"
" **Read more (Vim help)**
" - Netrw user docs:          `:help pi_netrw.txt`  (also `:help netrw-cr`)
" - Netrw internals bridge:   `:help netrw-call`    (netrw#Call/Expose/Modify)
" - Cmdline events:           `:help CmdlineEnter` `:help CmdlineChanged`
"                             `:help CmdlineLeave`
" - Timers:                   `:help timer_start()` `:help timer_stop()`
" - Feeding keys:             `:help feedkeys()`
" - Command-line access:      `:help getcmdline()` `:help getcmdtype()`
" - Window identity helpers:  `:help win_getid()` `:help win_gotoid()`
"
" **Relevant paths on this machine**
" - Your config:              ~/.vimrc
" - Netrw implementation:     /usr/share/vim/vim91/autoload/netrw.vim
" - Netrw documentation:      /usr/share/vim/vim91/doc/pi_netrw.txt
