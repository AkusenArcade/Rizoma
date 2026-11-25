# Rizoma — plan

Status: phases 1 to 3 built, 2026-11-25 (`genoma/`). Pace: slow, no deadline.

## 1. What it is

A file manager written in Luau on Genoma, opened as a `g.window`
(`app_id = "dev.akusen.rizoma"`). It has
Bioma's look and follows Bioma's theme live, through the shared theme file
the kit follows (`$XDG_CONFIG_HOME/genoma/theme.json`, see the OBS and
Sinestesia plans). It is an app, not a cell: Bioma's launcher, downloads
cell and "show in folder" open it.

Principles carried over from Bioma, where they make sense in an app:

- **Movement means something.** A progress bar moves at the rate bytes
  move; nothing animates without a value behind it.
- **Expanded forms grow from their origin.** A context menu opens from the
  pressed item, the operations panel from its indicator, a preview from the
  thumbnail.
- **Nothing is lost by accident** (Rizoma's own rule, the first one): no
  silent overwrite, deleting goes to the trash, an interrupted copy leaves
  the source intact.

## 2. Scope

**v1 — local files:**

- Navigate: places sidebar, path bar (steps, and typed with Ctrl+L), back /
  forward / up, tabs.
- Views: grid with thumbnails, list with columns (name, size, modified,
  type), sorting, hidden files (Ctrl+H), a filter typed over the view.
- Open: default application by MIME type, "Open with", run nothing by a
  double click without asking.
- Select: click, Ctrl/Shift, rubber band, keyboard, long press on touch.
- Operate: copy, cut, paste, move by drag, rename (F2, and batch later),
  new folder, trash, restore, empty trash, delete permanently (confirmed),
  properties (size of a folder computed, permissions read).
- Exchange: drag to and from other programs, copy/paste files with other
  file managers (`text/uri-list`, `x-special/gnome-copied-files`).
- Drives: mount, unmount, eject (Bioma's drives cell does this already).
- Bookmarks: the GTK file (`~/.config/gtk-3.0/bookmarks`), shared with
  every GTK dialog.
- Search: recursive by name below the current folder (`fd`, as Bioma's
  launcher does).
- Preview: images, text, PDF first page, video frame (from thumbnails).

**Later:** split view, batch rename, archives (open as folders, compress),
undo of the last operation, network places through gvfs mounts, the
`xdg-desktop-portal` FileChooser backend (every app's Open dialog drawn by
Rizoma), tags/colours.

**Not planned:** an indexer of its own, cloud accounts.

## 3. What Genoma already gives

| Need | Genoma |
|---|---|
| A folder's entries, watched, with size and mtime | `g.folder { path, watch, hidden, details }` |
| Long lists | `g.list` (virtualised), `tree` in the kit |
| A starting point | the kit's `file_picker` (folders, places, path steps, filter, picture preview) |
| Drag files to other programs | `drag_files` (text/uri-list) |
| Drops from other programs | the drop input on any node |
| Clipboard with types | `clipboard:set(types, path)` |
| Launch an app with files | `apps:launch(id, action, files, token)` |
| Drives, mounts, free space | the `drives` service (udisks2) |
| Icons | icon theme lookup (`g.icon`, `g.icon_path`) |
| Pictures | `g.image` (also animated GIF/WebP/PNG) |
| Fields, menus, dialogs, tabs, tooltips | the kit |
| Processes (search with `fd`, thumbnailers) | `g.process` |

## 4. What Genoma needs

These are general services — Bioma uses them too (thumbnails and types in
the launcher's file search, the downloads cell) — so they live in Genoma's
Rust crates, not in Rizoma. Rizoma stays pure Luau.

All of it is built and tested (2026-11-25; Genoma's CHANGELOG, Unreleased):

| Service | What Rizoma uses |
|---|---|
| `g.directory` | a folder read, sorted, filtered and typed off the loop, followed; `count`, `at`, `slice`, `paths`, `index`. `path`, `sort`, `descending`, `filter`, `hidden`, `folders_first` are followed functions |
| `g.list { count, item }` | only what is in view is asked for; a grid is a list of rows |
| `@genoma/mime` | type, description, icon, applications, `set_default` |
| `@genoma/thumbnails` | the shared freedesktop cache; other programs' thumbnailers in bubblewrap |
| `@genoma/files` | jobs with progress, pause, cancel and questions; rename, new folder, new file, measure |
| `@genoma/trash` | list, restore, erase, empty, on every disk |
| `clipboard:offer` / `:read` | `text/uri-list` and `x-special/gnome-copied-files` both ways |
| `drag_actions`, `drop_action`, `drop.action` | copy or move by dragging |
| `on_click` count | double click |
| `g.dbus.serve` | `org.freedesktop.FileManager1` |
| shared theme file | the desktop's look, live |

Measured with 50 000 files (warm cache): `g.folder` and a sort in Luau
stalled the loop 230 ms, and 50 ms more at each reading; `g.directory` shows
the first rows after 45 ms, none of them on the loop, sorts again in 7 ms,
and hands out 40 entries in 0.1 ms. At rest: no CPU, no wake-up.

Not there yet, wanted later: a picture under the pointer while dragging, the
files a drag holds before it is dropped, EXIF orientation in `g.image`
(thumbnails have it), reading the beginning of a large text for the preview,
files with names that are not UTF-8 in `apps:launch`.

## 5. Interface

As built (2026-11-25). No title bar, as every Genoma app:

```
┌──────────┐ (‹)(›)(^) (Home)─(Documents)─(Development)
│ places   │
│ bookmarks│   grid or list, straight on the window's ground
│ computer │
│          │
└──────────┘ (what is stood on · a notice · the filter)   (view)
```

- **The path is a rhizome**: each folder a capsule, a thread between them.
  Going into a folder buds a shoot out of the last capsule, its neck thinning
  to the thread that stays; coming out, the last one is taken back first. The
  current one, pressed, becomes a field (Ctrl+L), and the folders it may be
  going to bud out of its foot: Tab completes, the arrows choose. A path that
  is a file's is its folder, standing on it. A deep path keeps its start and as
  many of its last steps as fit.
- **Places**: the user's folders, the GTK bookmarks (read, not written yet),
  the computer; in Orbitron, as a menu is. Pinned beside the folder at 800
  wide and more; under that, or
  put away (F9), a button they grow from and float over the folder.
- **View**: a button at the foot's right, and the cell that grows from it:
  grid or list, order, reversed, folders first, hidden files, places, size.
- **Foot**: nothing at rest. What is stood on (the grid only: the list says it
  in its columns), a notice, the filter typed over the folder.
- **Preview** (space, or the view cell): a pane that grows from the entry stood
  on and goes back to it. Pinned beside the folder where both have room (660),
  floating on the side the entry is not where they do not. Pictures (moving
  ones move), the first page or frame of what has a thumbnailer, the head of a
  text, a folder's first names; below, name, type, size, date, what opens it.
  With nothing stood on, the folder's own. Read 0.12 s after the last step, so
  walking with the arrows reads nothing on the way.

- **Lists longer than their room** fade at the foot while there is more, and
  show a mark down their side while they move, as Bioma's do.
- **Selection**: a click, Ctrl and Shift, the rubber band (from the ground
  between the pictures, or a row's beside its name; past an edge the view goes on), the keys (Shift
  reaches, Ctrl walks without choosing, Ctrl+Space, Ctrl+A, Ctrl+Shift+I), a
  finger held on an entry, then taps. By path: it keeps through another order,
  and what is no longer shown is no longer selected.
- **Exchange**: Ctrl+C offers `text/uri-list`, `x-special/gnome-copied-files`
  and the paths as text; dragged out, what is selected is given to be copied,
  never to be moved. 50 000 selected in 30 ms, copied in 75.

Responsive by the window's size: the sidebar collapses to a button, the list
loses its type, then its date, then its size; the grid's columns are computed
from the width. Touch (HDMI-A-1 is a touchscreen): long press = context menu,
a drag past a threshold moves, a tap selects.

Keys: arrows, Home/End, Page Up/Down, Enter, BackSpace and Alt+↑ (up),
Alt+←/→, Alt+Home, Ctrl+H, Ctrl+L, Ctrl+F or just typing (filter), Ctrl+1/2
(grid, list), F5 or Ctrl+R, F9 (places),
space (preview), Ctrl+C, Escape. With their phases: Ctrl+X/V,
F2, Delete (trash), Shift+Delete (confirmed), Ctrl+T/W, Ctrl+Shift+N.

What runs a program (executables, `.desktop`, AppImage, Windows programs,
Java archives) is asked before, whatever opens it; a shell script opens as the
text it is.

## 6. Safety rules for `files`

- Never overwrite without an explicit answer; "replace" of a folder merges
  only when asked.
- Same filesystem: `rename(2)`, refusing a name taken. Across filesystems:
  copy into a file with no name (`O_TMPFILE`; a hidden one where there are
  none), put in place whole, `syncfs`, and only then remove the source, if
  it is still what was copied.
- Symlinks are copied as links, never followed into a loop; special files
  are skipped with a report.
- Keep mtime and permissions; report what could not be kept.
- Disk full, permission denied, a vanished source: the job stops on that
  item and asks, the rest of the queue waits.
- Delete defaults to trash; permanent delete only from Shift+Delete or the
  trash itself, always confirmed.
- Tested on scratch trees (tmpfs, a second filesystem for cross-device)
  with cancel at every stage, before any UI calls it. Development never
  runs operations against the real home.

## 7. Phases

0. **Prerequisite**: the shared theme file (with the other apps).
1. **Browser, read-only**: window, sidebar, path bar, grid and list,
   sorting, hidden, open with the default app. No operation can change a
   file yet. Measure `g.folder` on big folders here.
2. **Types and pictures**: `mime` and `thumbnails` in Genoma; icons by
   type, thumbnails in the grid, preview pane.
3. **Selection and exchange**: selection in every form, copy/paste and
   drag with other programs (Rizoma only *gives* files out at this stage).
4. **`files` in Genoma**: the operations service and its test suite —
   alone, headless, until it passes. Then Rizoma's paste, drop, rename,
   new folder and the operations panel.
5. **Trash**: service, delete to trash, the trash place with restore and
   empty.
6. **Comfort**: tabs, bookmarks, search, properties, drives.
7. **Desktop integration**: `FileManager1`, Rizoma as the default for
   `inode/directory` (today it is Nautilus), Bioma's launcher reveal and
   downloads cell pointing to it.
8. **Packaging**: AUR, `arch=any`, depends on `genoma`.

Verification: `genoma snapshot --mock` with a fake folder for the views;
Rust tests for the services; live runs on scratch folders.

## 8. Decisions (2026-11-18)

- `app_id`: `dev.akusen.rizoma`.
- Repository: `AkusenArcade/Rizoma` on GitHub, created now, private until
  there is something to show.
- View: one global choice (grid or list, sort, hidden), as Nautilus does,
  not remembered per folder.
