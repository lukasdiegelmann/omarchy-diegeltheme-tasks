import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Taskleiste: offene Fenster als Icons, mittig in einer Pille auf dem Bar-
// Hintergrund — derselbe Aufbau wie im früheren AGS-Dock.
//
// Fensterquelle ist Hyprlands Toplevel-Liste statt ToplevelManager, weil nur sie
// die Workspace-Zugehörigkeit mitliefert; die braucht sowohl der "workspace"-
// Umfang als auch die stabile Sortierung.
BarWidget {
  id: root
  moduleName: "diegel.tasks"

  // "workspace" = nur der aktive Workspace (klassische Taskleiste),
  // "all" = alle Fenster über alle Workspaces.
  readonly property string scope: String(setting("scope", "workspace"))
  readonly property int iconSize: Number(setting("iconSize", 20))
  // Nummer des Workspaces vor jeder Gruppe. Die Trennlinie allein zeigt nur, WO
  // eine Gruppe endet, nicht WELCHER Workspace es ist — erst die Nummer
  // beantwortet das. Abschaltbar, falls es zu viel wird.
  readonly property bool showWorkspace: setting("showWorkspace", false) === true

  // Vordergrundfarbe der tragenden Bar; `bar` wird von BarWidget injiziert und
  // ist beim ersten Auswerten noch undefiniert.
  readonly property color fg: root.bar ? root.bar.barForeground : Color.bar.text

  // Quickshell befüllt Hyprland.toplevels faul — ohne Refresh bleibt die Liste
  // beim Start leer. Danach hält die IPC-Verbindung sie aktuell.
  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    // Erstbefuellung des ListModels: onGroupsSourceChanged feuert nur bei
    // AENDERUNGEN, der Anfangszustand kaeme sonst nie an.
    root.syncGroups()
  }

  function toplevelByAddress(address) {
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].address) === String(address)) return values[i]
    }
    return null
  }

  // Das Modell trägt bewusst nur ADRESSEN und Workspace-Ids, keine Toplevel-
  // Objekte — wie Omarchys Workspaces-Widget. Ein Delegate überlebt so das
  // Verschwinden eines Fensters, statt beim Abbau auf ein totes QObject zu binden.
  // Gruppiert wird nach Workspace, damit die Trennlinien etwas zu trennen haben:
  // [{ workspace: 1, addresses: [...] }, ...], aufsteigend nach Workspace.
  function windowGroups() {
    var buckets = ({})
    var ids = []
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var focused = Hyprland.focusedWorkspace

    for (var i = 0; i < values.length; i++) {
      var t = values[i]
      // Special-Workspaces (id <= 0) gehören nicht in die Taskleiste.
      if (!t || !t.workspace || t.workspace.id <= 0) continue
      if (root.scope !== "all" && (!focused || t.workspace.id !== focused.id)) continue
      var ws = t.workspace.id
      if (!buckets[ws]) { buckets[ws] = []; ids.push(ws) }
      buckets[ws].push(String(t.address))
    }

    ids.sort(function(a, b) { return a - b })

    var out = []
    for (var j = 0; j < ids.length; j++) {
      // Nach Adresse sortiert: die ist willkürlich, aber pro Fenster STABIL —
      // sonst springen die Icons bei jeder Aktualisierung.
      buckets[ids[j]].sort()
      out.push({ workspace: ids[j], addresses: buckets[ids[j]] })
    }
    return out
  }

  function appId(t) {
    if (t && t.wayland && t.wayland.appId) return String(t.wayland.appId)
    // Fallback auf die Hyprland-Klasse: XWayland-Fenster haben oft keine appId.
    if (t && t.lastIpcObject && t.lastIpcObject["class"]) return String(t.lastIpcObject["class"])
    return ""
  }

  // Index appId/WM-Klasse -> Desktop-Eintrag über StartupWMClass. Den braucht
  // alles, dessen Fensterklasse nicht wie der Desktop-Eintrag heißt — Electron-
  // Apps und die meisten Chrome-Webapps. Einmal aufgebaut und nur neu erzeugt,
  // wenn sich die App-Liste ändert: ein Scan pro Icon-Auflösung wäre in einer
  // Bindung deutlich zu teuer.
  // Der Cache liegt IM Objekt, nicht in zwei Properties: `startupClassEntry`
  // wird aus der iconSource-Bindung heraus aufgerufen, und eine Zuweisung an
  // eine Property waere dort eine Aenderung an einer Abhaengigkeit derselben
  // Bindung — Qt meldet das als Binding loop. Ein Feld eines bestehenden
  // Objekts zu mutieren loest dagegen kein Aenderungssignal aus.
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
      // heuristicLookup findet viele Apps nicht (für "foot" z.B. null), der
      // appId selbst ist dann aber oft schon ein gültiger Icon-Name im Theme —
      // deshalb beide Wege nacheinander probieren.
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

  // Der wandernde Highlight darf nur existieren, wenn der aktive Workspace auch
  // wirklich eine Gruppe hat — sonst bliebe er nach dem Schliessen des letzten
  // Fensters auf der alten Position stehen.
  readonly property bool hasFocusedGroup: {
    var groups = root.windowGroups()
    var f = Hyprland.focusedWorkspace
    if (!f) return false
    for (var i = 0; i < groups.length; i++) if (groups[i].workspace === f.id) return true
    return false
  }

  // Der Repeater darf NICHT direkt an windowGroups() haengen: die Funktion
  // liefert bei jeder Auswertung ein neues Array, und darauf baut ein Repeater
  // saemtliche Delegates neu auf. Alles springt dann gleichzeitig an seinen
  // neuen Platz, statt dorthin zu gleiten. Dieses ListModel wird stattdessen
  // nur nachgezogen — verschwundene Gruppen raus, neue rein, bestehende
  // behalten ihr Item und damit ihre Position, von der aus sie animieren.
  ListModel {
    id: groupModel
    dynamicRoles: true   // noetig, damit `addresses` ein JS-Array sein darf
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

    // 1. Verschwundene Gruppen entfernen.
    var i = 0
    while (i < groupModel.count) {
      var stillThere = false
      for (var j = 0; j < groups.length; j++)
        if (groups[j].workspace === groupModel.get(i).workspace) { stillThere = true; break }
      if (stillThere) i++
      else groupModel.remove(i)
    }

    // 2. Neue einfuegen, vorhandene an die richtige Stelle schieben und nur
    //    dann anfassen, wenn sich ihre Fensterliste wirklich geaendert hat —
    //    ein setProperty auf gleichem Inhalt wuerde den inneren Repeater
    //    unnoetig neu bauen.
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

  // Die Pille hebt die Fensterliste vom durchgehenden Bar-Hintergrund ab.
  // Eingefärbt wird mit der Textfarbe bei niedriger Deckkraft statt mit einem
  // festen Grauwert — so passt sie in hellen wie in dunklen Themes zum Balken.
  Rectangle {
    id: pill
    anchors.centerIn: parent
    // GAR KEIN Innenabstand — weder vertikal noch horizontal. Vertikal nicht,
    // damit die aktive Gruppe exakt die Hoehe dieser Pille hat und beide bei
    // radius = height/2 denselben Kappenradius bekommen. Horizontal nicht, damit
    // die erste und letzte Gruppe genau an der Aussenkante beginnt bzw. endet:
    // jedes Padding hier schoebe die innere Pille nach innen, und die beiden
    // Kurven liefen auseinander. Die Luft um die Icons setzt stattdessen die
    // Gruppe selbst (die content-Row in groupPill).
    implicitWidth: row.implicitWidth
    // Waechst und schrumpft mit, statt umzuspringen. Dieselbe Dauer und Kurve
    // wie die Row-Uebergaenge darunter, damit Pille und Icons zusammen laufen.
    Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    implicitHeight: Math.max(1, root.barSize - Style.space(4))
    radius: height / 2       // Radius = halbe Höhe ergibt die echte Pillenform
    // Heller als der Balken, nicht als getönter Textfarbton: in der AGS-Bar war
    // die Pille (#666666) das hellere Element vor dem dunkleren Balken (#4a4a4a).
    // Von der Farbe der TRAGENDEN Bar abgeleitet, nicht von Color.bar.background:
    // die eigene Bar (diegel.bar) setzt ihren Hintergrund selbst und
    // weicht damit bewusst vom Theme ab. `bar` wird von BarWidget injiziert und
    // ist beim ersten Auswerten noch undefiniert — daher der Fallback.
    // Qt.lighter skaliert den HSV-Wert; #4a4a4a * 1.4 landet bei #686868.
    color: Qt.lighter(root.bar && root.bar.background ? root.bar.background : Color.bar.background, 1.4)

    // Der Highlight ist bewusst EIN Rechteck ausserhalb der Row, nicht die
    // Fuellung der jeweiligen Gruppe: nur ein einzelnes, durchgehend
    // existierendes Item kann von einer Position zur naechsten gleiten. Zwei
    // Gruppenfuellungen wuerden stattdessen die eine aus- und die andere
    // einblenden — da gibt es nichts zu animieren.
    //
    // Hyprland 0.56 meldet den Fortschritt einer Wischgeste NICHT ueber IPC
    // (nur den fertigen Workspace-Wechsel). Der Balken kann dem Finger also
    // nicht folgen; er laeuft nach dem Umschalten in die neue Position. Dauer
    // und Kurve sind an das Gefuehl der Geste angelehnt, nicht daran gekoppelt.
    Rectangle {
      id: highlight
      readonly property Item target: row.focusedPill

      // NICHT an `target` gekoppelt: waehrend eines Delegate-Wechsels ist die
      // Referenz einen Moment null, und ein unsichtbarer Highlight schaltet
      // ueber `enabled` seine Animation ab — er saesse danach ohne Uebergang
      // an der neuen Stelle. Solange es eine fokussierte Gruppe GIBT, bleibt er
      // sichtbar und haelt so lange seine letzte Geometrie.
      visible: root.hasFocusedGroup
      property real lastX: 0
      property real lastWidth: 0
      onXChanged: if (highlight.target) highlight.lastX = highlight.x
      onWidthChanged: if (highlight.target) highlight.lastWidth = highlight.width
      // target.parent ist die Gruppen-Row, deren x innerhalb von `row` liegt.
      x: highlight.target ? row.x + highlight.target.parent.x + highlight.target.x : highlight.lastX
      anchors.verticalCenter: parent.verticalCenter
      width: highlight.target ? highlight.target.width : highlight.lastWidth
      height: pill.implicitHeight
      radius: height / 2
      color: Qt.lighter(pill.color, 1.5)

      // Nur animieren, solange der Highlight schon steht — taucht er neu auf,
      // soll er an seiner Position erscheinen und nicht von links hereinfahren.
      Behavior on x     { enabled: highlight.visible; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      Behavior on width { enabled: highlight.visible; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    Row {
      id: row

      // Nur wirksam, weil das Modell oben stabil ist: bleibt ein Delegate am
      // Leben, laesst sich seine neue Position anfahren statt zuzuweisen.
      add: Transition { NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.OutCubic } }
      move: Transition { NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.OutCubic } }
      anchors.centerIn: parent
      spacing: 0

      // Die fokussierte Gruppe meldet sich als OBJEKT an, nicht mit Zahlen.
      // Zahlen zu pushen ging schief, sobald sich die Fensterliste aenderte:
      // dann baut der Repeater alle Delegates neu, und ein gerade sterbender
      // schob beim Abbau noch seine alte Geometrie hinterher — der Highlight
      // sprang auf eine Position, die es nicht mehr gab. Ueber eine Referenz
      // sind x und width normale Bindungen: sie folgen dem Layout von selbst,
      // und ein abgebautes Objekt ist schlicht null.
      property Item focusedPill: null

      Repeater {
        model: groupModel

        // Eine Gruppe = ein Workspace. Die Trennlinie gehoert zum LINKEN Rand
        // der Gruppe und entfaellt bei der ersten — sonst haengt sie am Anfang
        // der Pille in der Luft. Genau so war es im AGS-Dock geloest
        // (.dock-group { border-left } / &:first-child { border-none }).
        Row {
          id: group
          // Rollen des ListModels statt modelData: `workspace` ist die
          // Workspace-Id, `addresses` die Fensterliste dieser Gruppe.
          required property int workspace
          required property var addresses
          required property int index

          height: pill.implicitHeight
          spacing: Style.space(1)

          readonly property bool isFocused: Hyprland.focusedWorkspace
            && Hyprland.focusedWorkspace.id === group.workspace

          // Haarlinie statt Separator-Widget: ein 1px-Rechteck in einem
          // Abstandhalter, damit links und rechts gleich viel Luft bleibt.
          // Row ueberspringt unsichtbare Kinder, die Breite faellt also mit weg.
          Item {
            visible: group.index > 0
            width: Style.space(7)
            height: group.height

            Rectangle {
              anchors.centerIn: parent
              width: 1
              // Volle Hoehe der Pille statt einer kurzen Marke in der Mitte:
              // die Linie trennt damit sichtbar zwei Flaechen, statt nur einen
              // Punkt zwischen ihnen zu setzen.
              height: parent.height
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22)
            }
          }

          // Innere Pille: markiert den offenen Workspace. Deckungsgleich mit der
          // aeusseren — gleiche Hoehe, gleicher Radius, und weil die aeussere kein
          // Padding hat, fallen an der ersten und letzten Gruppe auch die Kurven
          // zusammen. Dieselbe Konstruktion wie im AGS-Dock (.dock-group.active).
          // Farbe aus der aeusseren Pille aufgehellt statt fest verdrahtet:
          // #686868 * 1.5 landet bei ~#9c9c9c, dem AGS-Wert rgba(160,160,160).
          Rectangle {
            id: groupPill
            anchors.verticalCenter: parent.verticalCenter
            height: pill.implicitHeight
            width: content.implicitWidth + Style.space(5)
            radius: height / 2
            // Keine eigene Fuellung mehr — die malt der wandernde Highlight.
            // Dieses Rechteck bleibt als Traeger der Geometrie stehen und
            // meldet sie, solange es die fokussierte Gruppe ist.
            color: "transparent"

            // An- und Abmelden laufen ueber Identitaetsvergleich: beim Neuaufbau
            // des Modells ist nicht festgelegt, ob der alte Delegate vor oder
            // nach dem neuen abgebaut wird. Nur wer selbst eingetragen ist,
            // darf sich austragen — sonst loescht der Sterbende den Nachfolger.
            // NUR anmelden, niemals beim Fokusverlust abmelden. Beim Wechsel
            // werten beide Gruppen ihre isFocused-Bindung neu aus, und die
            // Reihenfolge ist nicht festgelegt: raeumt die alte zuerst auf,
            // steht focusedPill kurz auf null — der Highlight wird unsichtbar,
            // die Behavior ist damit abgeschaltet, und er SPRINGT an die neue
            // Stelle statt zu gleiten. In der anderen Richtung meldete sich die
            // neue zuerst an, dort lief die Animation. Genau diese Asymmetrie.
            // Der Nachfolger ueberschreibt den Eintrag ohnehin; fuer den Fall
            // "gar keine fokussierte Gruppe" sorgt root.hasFocusedGroup.
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

          // Workspace-Nummer. Gedimmt, ausser im fokussierten Workspace — so
          // beantwortet die Leiste beide Fragen auf einen Blick: welche Fenster
          // gehoeren zusammen, und wo bin ich gerade. Auf der hellen Fuellung
          // waere die helle Schrift unlesbar, dort also die Kontrastfarbe.
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

            // NICHT `id: item`: BarIconButton laedt iconComponent ueber einen
            // Loader, und Loader hat selbst eine Property `item`, die die id im
            // Component-Scope ueberschatten wuerde.
            BarIconButton {
              id: task
              required property string modelData

              // Truthiness statt `!== null`: eine var-Property ist vor der
              // ersten Bindungsauswertung `undefined`, und `undefined !== null`
              // ist true — der Guard haette durchgelassen.
              readonly property var win: root.toplevelByAddress(modelData)
              readonly property bool focused: !!win && win.activated === true
              readonly property string iconSource: win ? root.iconFor(win) : ""

              bar: root.bar
              active: task.focused
              tooltipText: task.win ? root.label(task.win) : ""
              // Enger als der Bar-Standardslot, damit die Pille nicht ausufert.
              slotSize: root.iconSize + Style.space(6)
              fixedHeight: groupPill.height
              // Die Zeichenflaeche von BarIconButton ist sonst auf
              // Style.bar.iconCanvas (16) festgenagelt — ein groesseres Icon
              // wuerde darueber hinausragen statt mittig zu sitzen.
              opticalSize: root.iconSize

              iconComponent: Image {
                source: task.iconSource
                // In physischen Pixeln dekodieren, sonst sind die Icons auf dem
                // HiDPI-Panel weich.
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
                  // activate() wechselt bei Hyprland auch den Workspace mit.
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
