# diegeltheme.bar.tasks — taskbar

Open windows as icons, grouped by workspace, separated by hairlines, with a
highlight that glides to the new group when you switch workspaces.

## Install

```bash
omarchy plugin add https://github.com/lukasdiegelmann/omarchy-diegeltheme-tasks.git
```

## Usage

```jsonc
{ "id": "diegeltheme.bar.tasks", "scope": "all", "iconSize": 22, "showWorkspace": false }
```

| Setting | Meaning |
|---|---|
| `scope` | `workspace` = active workspace only, `all` = every window |
| `iconSize` | icon size in px |
| `showWorkspace` | show the workspace number in front of each group |

Left click focuses a window, middle click closes it. Adding or removing a window grows
or shrinks the pill instead of making it jump.
