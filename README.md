# diegeltheme.bar.tasks — Taskleiste

Offene Fenster als Icons, nach Workspace gruppiert, mit Trennlinien und einem
Highlight, das beim Workspace-Wechsel zur neuen Gruppe gleitet.

## Installation

```bash
omarchy plugin add https://github.com/lukasdiegelmann/omarchy-diegeltheme-tasks.git
```

## Verwendung

```jsonc
{ "id": "diegeltheme.bar.tasks", "scope": "all", "iconSize": 22, "showWorkspace": false }
```

| Einstellung | Bedeutung |
|---|---|
| `scope` | `workspace` = nur der aktive, `all` = alle Fenster |
| `iconSize` | Icon-Groesse in px |
| `showWorkspace` | Workspace-Nummer vor jeder Gruppe |

Klick fokussiert das Fenster, mittlere Maustaste schliesst es.
