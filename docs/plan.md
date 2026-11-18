# Rizoma — plan

Status: draft, 2026-11-18. Pace: slow, no deadline.

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

| Service | What | Size |
|---|---|---|
| `files` | **operations**: copy, move, link, rename, mkdir, delete; a queue of jobs with progress (bytes, files, rate), pause, cancel, and conflicts asked back to Luau (replace / skip / keep both / for all). Rules in §6. | large |
| `trash` | freedesktop Trash spec: `$XDG_DATA_HOME/Trash` and per-mount `.Trash-$uid`, `.trashinfo`, list, restore, empty | medium |
| `mime` | type of a file from shared-mime-info (globs, then magic for the ambiguous), its icon name, its default and other applications from `mimeapps.list` + desktop entries, set default | medium |
| `thumbnails` | freedesktop thumbnail spec: shared cache `~/.cache/thumbnails` (normal / large / x-large, `fail/`), images done in-process, others by the system's `.thumbnailer` files with a time limit; a queue that serves visible items first | medium |
| D-Bus export | serve `org.freedesktop.FileManager1` (ShowFolders, ShowItems) so "show in folder" from Firefox etc. opens Rizoma. `g.dbus` is a client only today: either a general `g.dbus.serve`, or this one interface in Rust | small–medium |
| `g.folder` at scale | check with 50 000 entries: time to first paint, memory; sort and filter in Rust if Luau is the bottleneck | measure first |
| Shared theme file | as for the other apps | (shared) |

## 5. Interface

Window layout (wide):

```
┌──────────┬───────────────────────────────────────────┬──────────┐
│ places   │ ‹ › ⌂  Home / Documents / Development   ⌕ │          │
│ drives   ├───────────────────────────────────────────┤ preview  │
│ bookmarks│   grid or list                            │ (toggle) │
│ trash    │                                           │          │
│          │                                           │          │
└──────────┴───────────────────────────────────────────┴──────────┘
                    operations indicator → panel (grows from it)
```

Responsive by `on_size` breakpoints: the preview goes first, then the
sidebar collapses to a button; the grid's columns are computed from the
width (as in OBS Touch Control). Touch (HDMI-A-1 is a touchscreen): long
press = context menu, a drag past a threshold moves, a tap selects.

Keys: the usual set — Ctrl+C/X/V, F2, Delete (trash), Shift+Delete
(confirmed), Ctrl+H, Ctrl+L, Alt+←/→, Backspace, Ctrl+T/W, Ctrl+F, Enter,
Ctrl+Shift+N.

## 6. Safety rules for `files`

- Never overwrite without an explicit answer; "replace" of a folder merges
  only when asked.
- Same filesystem: `rename(2)`. Across filesystems: copy to a temporary name
  in the destination, fsync, rename into place, and only then remove the
  source.
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
