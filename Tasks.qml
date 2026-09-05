import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Taskbar: open windows as icons, centred in a pill on the bar background —
// the same construction as the earlier AGS dock.
//
// The window source is Hyprland's toplevel list rather than ToplevelManager,
// because only that one carries the workspace a window sits on; both the
// "workspace" scope and the stable ordering need it.
BarWidget {
  id: root
  moduleName: "diegeltheme.bar.tasks"

  // "workspace" = the active workspace only (a classic taskbar),
  // "all" = every window across all workspaces.
  readonly property string scope: String(setting("scope", "workspace"))
  readonly property int iconSize: Number(setting("iconSize", 20))
  // Workspace number in front of each group. A divider alone only shows WHERE
  // a group ends, not WHICH workspace it is — the number answers that.
  // Switchable, in case it is too much.
  readonly property bool showWorkspace: setting("showWorkspace", false) === true

  // Foreground colour of the carrying bar; `bar` is injected by BarWidget and
  // is still undefined on the first evaluation.
  readonly property color fg: root.bar ? root.bar.barForeground : Color.bar.text

  // Quickshell fills Hyprland.toplevels lazily — without a refresh the list
  // stays empty at startup. After that the IPC connection keeps it current.
  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    // First fill of the ListModel: onGroupsSourceChanged only fires on CHANGES,
    // so the initial state would never arrive.
    root.syncGroups()
  }

  function toplevelByAddress(address) {
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].address) === String(address)) return values[i]
    }
    return null
  }

  // The model deliberately carries only ADDRESSES and workspace ids, never
  // toplevel objects — like Omarchy's own workspaces widget. A delegate thus
  // survives a window disappearing instead of binding to a dead QObject on
  // teardown. Grouped by workspace so the dividers have something to divide:
  // [{ workspace: 1, addresses: [...] }, ...], ascending by workspace.
  function windowGroups() {
    var buckets = ({})
    var ids = []
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var focused = Hyprland.focusedWorkspace

    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      // Special workspaces (id <= 0) do not belong in a taskbar.
      if (!t || !t.workspace || t.workspace.id <= 0) continue
      if (root.scope !== "all" && (!focused || t.workspace.id !== focused.id)) continue
      var ws = t.workspace.id
      if (!buckets[ws]) { buckets[ws] = []; ids.push(ws) }
      buckets[ws].push(String(t.address))
    }

    ids.sort(function(a, b) { return a - b })

    var out = []
    for (var j = 0; j < ids.length; j++) {
      // Sorted by address: arbitrary, but STABLE per window — otherwise the
      // icons would jump on every refresh.
      buckets[ids[j]].sort()
      out.push({ workspace: ids[j], addresses: buckets[ids[j]] })
    }
    return out
  }

  function appId(t) {
    if (t && t.wayland && t.wayland.appId) return String(t.wayland.appId)
    // Fall back to the Hyprland class: XWayland windows often have no appId.
    if (t && t.lastIpcObject && t.lastIpcObject["class"]) return String(t.lastIpcObject["class"])
    return ""
  }

  // Index appId/WM class -> desktop entry via StartupWMClass. Anything whose
  // window class is not named like its desktop entry needs this — Electron
  // apps and most Chrome web apps. Built once and rebuilt only when the app
  // list changes: a scan per icon lookup would be far too expensive inside a
  // binding.
  // The cache lives INSIDE an object rather than in two properties:
  // `startupClassEntry` is called from the iconSource binding, and assigning
  // to a property there would change a dependency of that same binding — Qt
  // reports it as a binding loop. Mutating a field of an existing object
  // raises no change signal.
  readonly property var startupClassCache: ({ index: null, count: -1 })

  function startupClassEntry(id) {
    var apps = DesktopEntries.applications ? DesktopEntries.applications.values : []
    var cache = root.startupClassCache
    if (cache.count !== apps.length || !cache.index) {
      var map = {}
      for (var i = 0; i < apps.length; i++) {
        var sc = apps[i].startupClass
        if (sc) map[String(sc).toLowerCase()] = apps[i]
      }
      cache.index = map
      cache.count = apps.length
    }
    return cache.index[id.toLowerCase()] || null
  }

  function iconFor(t) {
    var id = root.appId(t)
    if (id !== "") {
      var byClass = root.startupClassEntry(id)
      if (byClass && byClass.icon) {
        var viaClass = Quickshell.iconPath(String(byClass.icon), true)
        if (viaClass) return viaClass
      }
      // heuristicLookup misses many apps (null for "foot", for instance), but the
      // appId itself is often already a valid icon name in the theme — so try
      // both paths in turn.
      var entry = DesktopEntries.heuristicLookup(id)
      if (entry && entry.icon) {
        var viaEntry = Quickshell.iconPath(String(entry.icon), true)
        if (viaEntry) return viaEntry
      }
      var direct = Quickshell.iconPath(id, true)
      if (direct) return direct
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  function label(t) {
    var title = t && t.title ? String(t.title) : ""
    return title !== "" ? title : root.appId(t)
  }

  // The travelling highlight may only exist while the active workspace really
  // has a group — otherwise it would linger at the old position after the
  // last window closed.
  readonly property bool hasFocusedGroup: {
    var groups = root.windowGroups()
    var f = Hyprland.focusedWorkspace
    if (!f) return false
    for (var i = 0; i < groups.length; i++) if (groups[i].workspace === f.id) return true
    return false
  }

  // The Repeater must NOT hang off windowGroups() directly: that function
  // returns a new array on every evaluation, and a Repeater rebuilds all its
  // delegates on that. Everything then jumps to its new place at once
  // instead of gliding there. This ListModel is updated differentially
  // instead — vanished groups out, new ones in, existing ones keep their
  // item and therefore the position they animate from.
  ListModel {
    id: groupModel
    dynamicRoles: true   // needed so `addresses` may be a JS array
  }

  readonly property var groupsSource: root.windowGroups()
  onGroupsSourceChanged: root.syncGroups()

  function indexOfWorkspace(ws) {
    for (var i = 0; i < groupModel.count; i++)
      if (groupModel.get(i).workspace === ws) return i
    return -1
  }

  function syncGroups() {
    var groups = root.groupsSource

    // 1. Remove groups that are gone.
    var i = 0
    while (i < groupModel.count) {
      var stillThere = false
      for (var j = 0; j < groups.length; j++)
        if (groups[j].workspace === groupModel.get(i).workspace) { stillThere = true; break }
      if (stillThere) i++
      else groupModel.remove(i)
    }

    // 2. Insert new ones, move existing ones into place, and only touch them
    //    when their window list actually changed — a setProperty with equal
    //    content would rebuild the inner Repeater for nothing.
    for (var k = 0; k < groups.length; k++) {
      var g = groups[k]
      var idx = root.indexOfWorkspace(g.workspace)
      if (idx === -1) {
        groupModel.insert(Math.min(k, groupModel.count),
                          { workspace: g.workspace, addresses: g.addresses })
      } else {
        if (idx !== k) groupModel.move(idx, k, 1)
        var cur = groupModel.get(k).addresses
        if (String(cur) !== String(g.addresses))
          groupModel.setProperty(k, "addresses", g.addresses)
      }
    }
  }

  visible: !vertical && root.windowGroups().length > 0
  implicitWidth: pill.implicitWidth
  implicitHeight: barSize

  // The pill lifts the window list off the continuous bar background.
  // It is tinted from the bar's own colour rather than a fixed grey, so it
  // suits the bar in light and dark themes alike.
  Rectangle {
    id: pill
    anchors.centerIn: parent
    // NO padding at all — neither vertical nor horizontal. Not vertical, so the
    // active group has exactly the height of this pill and both get the same
    // cap radius at radius = height/2. Not horizontal, so the first and last
    // group start and end exactly at the outer edge: any padding here would
    // push the inner pill inwards and the two curves would drift apart. The
    // air around the icons is set by the group itself (the content Row inside
    // groupPill).
    implicitWidth: row.implicitWidth
    // Grows and shrinks along instead of snapping. Same duration and curve as
    // the Row transitions below, so pill and icons travel together.
    Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    implicitHeight: Math.max(1, root.barSize - Style.space(4))
    radius: height / 2       // radius = half the height gives a true pill cap
    // Lighter than the bar, not a tinted shade of the text colour: in the AGS
    // bar the pill (#666666) was the lighter element in front of the darker
    // bar (#4a4a4a). Derived from the colour of the CARRYING bar rather than
    // Color.bar.background: diegeltheme.bar sets its background itself and
    // deliberately departs from the theme. `bar` is injected by BarWidget and
    // is undefined on the first evaluation — hence the fallback.
    // Qt.lighter scales the HSV value; #4a4a4a * 1.4 lands at #686868.
    color: Qt.lighter(root.bar && root.bar.background ? root.bar.background : Color.bar.background, 1.4)

    // The highlight is deliberately ONE rectangle outside the Row, not the fill
    // of the respective group: only a single, continuously existing item can
    // glide from one position to the next. Two group fills would instead fade
    // one out and the other in — there is nothing to animate in that.
    //
    // Hyprland 0.56 does NOT report the progress of a swipe gesture over IPC
    // (only the finished workspace change). The bar therefore cannot follow
    // the finger; it runs to the new position after the switch. Duration and
    // curve are modelled on the feel of the gesture, not coupled to it.
    Rectangle {
      id: highlight
      readonly property Item target: row.focusedPill

      // NOT tied to `target`: during a delegate swap the reference is null for a
      // moment, and an invisible highlight switches its animation off through
      // `enabled` — it would then sit at the new place without a transition. As
      // long as a focused group EXISTS it stays visible and holds its last
      // geometry meanwhile.
      visible: root.hasFocusedGroup
      property real lastX: 0
      property real lastWidth: 0
      onXChanged: if (highlight.target) highlight.lastX = highlight.x
      onWidthChanged: if (highlight.target) highlight.lastWidth = highlight.width
      // target.parent is the group Row, whose x lies inside `row`.
      x: highlight.target ? row.x + highlight.target.parent.x + highlight.target.x : highlight.lastX
      anchors.verticalCenter: parent.verticalCenter
      width: highlight.target ? highlight.target.width : highlight.lastWidth
      height: pill.implicitHeight
      radius: height / 2
      color: Qt.lighter(pill.color, 1.5)

      // Only animate while the highlight already stands — when it appears anew
      // it should show up in place instead of flying in from the left.
      Behavior on x     { enabled: highlight.visible; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      Behavior on width { enabled: highlight.visible; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    Row {
      id: row

      // Only effective because the model above is stable: while a delegate stays
      // alive, its new position can be travelled to instead of assigned.
      add: Transition { NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.OutCubic } }
      move: Transition { NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.OutCubic } }
      anchors.centerIn: parent
      spacing: 0

      // The focused group registers itself as an OBJECT, not as numbers. Pushing
      // numbers broke as soon as the window list changed: the Repeater rebuilds
      // every delegate, and one that was just dying still pushed its old
      // geometry along during teardown — the highlight jumped to a position
      // that no longer existed. Through a reference, x and width are ordinary
      // bindings: they follow the layout by themselves, and a torn-down object
      // is simply null.
      property Item focusedPill: null

      Repeater {
        model: groupModel

        // One group = one workspace. The divider belongs to the LEFT edge of a
        // group and is dropped on the first one — otherwise it would hang in mid
        // air at the start of the pill. The AGS dock solved it the same way
        // (.dock-group { border-left } / &:first-child { border-none }).
        Row {
          id: group
          // ListModel roles instead of modelData: `workspace` is the workspace id,
          // `addresses` the window list of this group.
          required property int workspace
          required property var addresses
          required property int index

          height: pill.implicitHeight
          spacing: Style.space(1)

          readonly property bool isFocused: Hyprland.focusedWorkspace
            && Hyprland.focusedWorkspace.id === group.workspace

          // A hairline instead of a separator widget: a 1px rectangle inside a
          // spacer, so there is equal air left and right. A Row skips invisible
          // children, so the width falls away with it.
          Item {
            visible: group.index > 0
            width: Style.space(7)
            height: group.height

            Rectangle {
              anchors.centerIn: parent
              width: 1
              // Full height of the pill instead of a short mark in the middle: the
              // line then visibly separates two areas rather than just setting a
              // point between them.
              height: parent.height
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22)
            }
          }

          // Inner pill: marks the open workspace. Congruent with the outer one —
          // same height, same radius, and because the outer has no padding the
          // curves coincide at the first and last group too. The same
          // construction as the AGS dock (.dock-group.active). The colour is
          // lightened from the outer pill rather than hard-wired: #686868 * 1.5
          // lands near #9c9c9c, the AGS value rgba(160,160,160).
          Rectangle {
            id: groupPill
            anchors.verticalCenter: parent.verticalCenter
            height: pill.implicitHeight
            width: content.implicitWidth + Style.space(5)
            radius: height / 2
            // No fill of its own any more — the travelling highlight paints that.
            // This rectangle stays as the carrier of the geometry and reports it
            // for as long as it is the focused group.
            color: "transparent"

            // Registering runs through an identity comparison: when the model is
            // rebuilt, QML does not define whether the old delegate is torn down
            // before or after the new one. Only whoever is registered may
            // deregister — otherwise the dying one deletes its successor.
            // And it ONLY registers, never deregisters on losing focus. On a
            // switch both groups re-evaluate their isFocused binding in an
            // unspecified order: if the old one cleans up first, focusedPill is
            // null for a moment — the highlight turns invisible, its Behavior is
            // switched off with it, and it JUMPS to the new place instead of
            // gliding. In the other direction the new one registered first and the
            // animation ran. Exactly that asymmetry. The successor overwrites the
            // entry anyway; the case of no focused group at all is covered by
            // root.hasFocusedGroup.
            function claim() {
              if (group.isFocused) row.focusedPill = groupPill
            }

            Component.onCompleted: claim()
            Component.onDestruction: if (row.focusedPill === groupPill) row.focusedPill = null

            Connections {
              target: group
              function onIsFocusedChanged() { groupPill.claim() }
            }

            Row {
              id: content
              anchors.centerIn: parent
              spacing: Style.space(1)

          // Workspace number. Dimmed except in the focused workspace — so the bar
          // answers both questions at a glance: which windows belong together,
          // and where am I right now. On the light fill the light type would be
          // unreadable, so the contrast colour is used there.
          Text {
            visible: root.showWorkspace
            anchors.verticalCenter: parent.verticalCenter
            text: String(group.workspace)
            color: group.isFocused && root.bar ? root.bar.themeContrastForeground : root.fg
            opacity: group.isFocused ? 1 : 0.45
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            rightPadding: Style.space(2)
          }

          Repeater {
            model: group.addresses

            // NOT `id: item`: BarIconButton loads iconComponent through a Loader,
            // and Loader has a property `item` of its own that would shadow the id
            // in the component scope.
            BarIconButton {
              id: task
              required property string modelData

              // Truthiness instead of `!== null`: a var property is `undefined`
              // before its first binding evaluation, and `undefined !== null` is
              // true — the guard would have let it through.
              readonly property var win: root.toplevelByAddress(modelData)
              readonly property bool focused: !!win && win.activated === true
              readonly property string iconSource: win ? root.iconFor(win) : ""

              bar: root.bar
              active: task.focused
              tooltipText: task.win ? root.label(task.win) : ""
              // Tighter than the bar's default slot, so the pill does not sprawl.
              slotSize: root.iconSize + Style.space(6)
              fixedHeight: groupPill.height
              // The drawing area of BarIconButton is otherwise pinned to
              // Style.bar.iconCanvas (16) — a larger icon would stick out of it
              // instead of sitting centred.
              opticalSize: root.iconSize

              iconComponent: Image {
                source: task.iconSource
                // Decode in physical pixels, otherwise the icons are soft on the
                // HiDPI panel.
                sourceSize.width: root.iconSize * 2
                sourceSize.height: root.iconSize * 2
                width: root.iconSize
                height: root.iconSize
                anchors.centerIn: parent
                fillMode: Image.PreserveAspectFit
                opacity: task.focused ? 1 : 0.7
              }

              onPressed: function(button) {
                if (!task.win || !task.win.wayland) return
                if (button === Qt.MiddleButton) {
                  task.win.wayland.close()
                } else {
                  // activate() also switches the workspace along, under Hyprland.
                  task.win.wayland.activate()
                }
              }
            }
          }
            }
          }
        }
      }
    }
  }
}
