import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import "AppSearch.js" as AppSearch

// The launcher surface: one full-screen layer-shell overlay holding a centred
// card, a query line, and the matching applications.
//
// Keyboard focus is Exclusive, which is what makes this a launcher rather than
// a widget: the compositor routes every key here while it is mapped, so typing
// never leaks into whatever was focused before. Hyprland still processes its
// own binds first, so `$mod D` can close what it opened.
//
// Only mapped while open. An unmapped layer surface holds no focus at all,
// which is the whole of "ESC dismisses without focus residue" — there is no
// residue to clean up because the surface is gone.
PanelWindow {
    id: root

    property bool opened: false

    signal dismissed

    visible: root.opened

    // No `screen:` binding. Diogenes has one output, and picking the focused
    // one would mean tracking Hyprland's focused monitor for a case that does
    // not exist here yet. If a second monitor ever shows up, this is the line
    // that needs to grow.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.namespace: "the-shell-menu"
    // Overlay, not Top: the menu must draw over fullscreen windows, which is
    // where a launcher is most often summoned from.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // A full-screen surface that reserved space would push every tiled window
    // off the monitor.
    exclusionMode: ExclusionMode.Ignore

    // ---- model ---------------------------------------------------------

    // Plain-JS candidates, rebuilt when the desktop entry scan changes. The
    // conversion happens here rather than in AppSearch.js so the matcher never
    // touches a Quickshell type.
    //
    // `noDisplay` entries are the ones the spec says never to show in a menu
    // (mimetype handlers, session pieces); walker hid them too.
    readonly property var candidates: {
        const out = [];
        for (const entry of DesktopEntries.applications.values) {
            if (entry.noDisplay)
                continue;

            out.push({
                entry: entry,
                name: entry.name,
                generic: entry.genericName,
                comment: entry.comment,
                // QStringList arrives as a JS array, but a malformed entry can
                // leave it unset — hence the guard rather than a bare join.
                keywords: entry.keywords ? Array.prototype.join.call(entry.keywords, " ") : "",
                icon: entry.icon
            });
        }
        return out;
    }

    readonly property string query: input.text
    readonly property var results: AppSearch.search(root.candidates, root.query)

    // ---- pointer gate --------------------------------------------------
    //
    // The menu appears under wherever the pointer happens to be resting, and a
    // MouseArea that is already under the cursor emits `entered` the moment it
    // is created. Left alone, that hands the selection to whichever row the
    // mouse landed on — open the launcher, press Enter, and something you did
    // not choose starts. Same again after every keystroke, since the rows move
    // under a stationary pointer.
    //
    // So hover selection is disabled until the pointer genuinely moves: the
    // first sample is only remembered, and it takes a few pixels of real
    // movement to arm. Anything that changes the list disarms it again.
    property bool pointerArmed: false
    property point pointerOrigin: Qt.point(-1, -1)

    function disarmPointer() {
        root.pointerArmed = false;
        root.pointerOrigin = Qt.point(-1, -1);
    }

    // True once the pointer has moved far enough to be believed.
    function pointerMoved(position) {
        if (root.pointerArmed)
            return true;

        if (root.pointerOrigin.x < 0) {
            root.pointerOrigin = position;
            return false;
        }

        if (Math.abs(position.x - root.pointerOrigin.x) < 3 && Math.abs(position.y - root.pointerOrigin.y) < 3)
            return false;

        root.pointerArmed = true;
        return true;
    }

    // Launch the row at `index`, if there is one.
    //
    // Order matters: the surface is dismissed BEFORE the process starts. The
    // menu gives up keyboard focus while the app is still launching, so the
    // window that appears is focused by Hyprland's normal new-window path
    // instead of arriving behind a layer surface that still owns the keyboard.
    function activate(index) {
        if (index < 0 || index >= root.results.length)
            return;

        const entry = root.results[index].entry;
        root.dismissed();

        // `uwsm-app`, not DesktopEntry.execute(). execute() is
        // QProcess::startDetached, which leaves the child in
        // quickshell.service's cgroup: every app launched from the menu would
        // die with `systemctl --user restart quickshell`. uwsm-app hands the
        // entry to the session's app daemon, which starts it in its own
        // app-*.scope under app.slice — the same place apps launched by any
        // other well-behaved launcher land (ADR 0003 put the session under
        // uwsm; this is the launcher half of that decision).
        //
        // It also means Terminal= and DBusActivatable entries are uwsm's
        // problem rather than ours, which execute() would have got wrong.
        //
        // The argument is a Desktop Entry ID: uwsm only treats an argument as
        // an entry when it ends in `.desktop`, otherwise it looks for an
        // executable of that name. DesktopEntry.id is the basename without the
        // extension, so the suffix goes back on here.
        //
        // In the non-uwsm escape-hatch session there is no app daemon and this
        // degrades to plain `uwsm app`; if that fails too, nothing launches.
        // Acceptable — that session exists to get a shell up and rebuild.
        Quickshell.execDetached(["uwsm-app", "--", entry.id + ".desktop"]);
    }

    onVisibleChanged: {
        if (!root.visible)
            return;

        // Every open starts empty. A launcher that remembers the last query is
        // a launcher you have to clear before you can use it.
        input.text = "";
        list.currentIndex = 0;
        root.disarmPointer();
        input.forceActiveFocus();
    }

    // ---- surface -------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: Theme.menuScrim

        // Clicking off the card is the pointer's version of ESC.
        MouseArea {
            anchors.fill: parent
            onClicked: root.dismissed()
        }
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * Theme.menuTopFraction)

        width: Math.min(Theme.menuWidth, root.width - Theme.menuPadding * 2)
        implicitHeight: content.implicitHeight + Theme.menuPadding * 2

        radius: Theme.menuRadius
        color: Theme.menuBackground
        border.width: 1
        border.color: Theme.menuBorder

        // Swallows clicks that would otherwise reach the dismiss handler
        // underneath.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content

            anchors.fill: parent
            anchors.margins: Theme.menuPadding
            spacing: Theme.menuPadding

            // The query line is a real TextInput, so text editing (selection,
            // word-delete, IME) behaves the way it does everywhere else rather
            // than being reimplemented one key at a time.
            Item {
                width: parent.width
                height: input.implicitHeight

                TextInput {
                    id: input

                    anchors.fill: parent
                    color: Theme.foreground
                    font.pixelSize: Theme.menuQueryFontSize
                    selectionColor: Theme.menuSelectedBackground
                    selectedTextColor: Theme.menuSelectedForeground
                    clip: true
                    focus: true

                    // Any edit invalidates the old cursor position: the row it
                    // pointed at is not the row it points at now.
                    onTextChanged: {
                        list.currentIndex = 0;
                        root.disarmPointer();
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Escape:
                            // Unconditional close, including with a query
                            // typed. "ESC dismisses" should not depend on what
                            // is in the box.
                            root.dismissed();
                            event.accepted = true;
                            break;
                        case Qt.Key_Down:
                        case Qt.Key_Tab:
                            list.step(1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Up:
                        case Qt.Key_Backtab:
                            list.step(-1);
                            event.accepted = true;
                            break;
                        case Qt.Key_PageDown:
                            list.step(Theme.menuMaxRows);
                            event.accepted = true;
                            break;
                        case Qt.Key_PageUp:
                            list.step(-Theme.menuMaxRows);
                            event.accepted = true;
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.activate(list.currentIndex);
                            event.accepted = true;
                            break;
                        }
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    text: "Search applications…"
                    color: Theme.menuDetailForeground
                    font.pixelSize: Theme.menuQueryFontSize
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.menuBorder
            }

            Text {
                width: parent.width
                visible: root.results.length === 0
                text: "No matching applications"
                color: Theme.menuDetailForeground
                font.pixelSize: Theme.fontSize
                height: visible ? Theme.menuRowHeight : 0
                verticalAlignment: Text.AlignVCenter
            }

            ListView {
                id: list

                // The card is sized by its content up to the row cap, so a
                // two-result search draws a two-row card instead of a mostly
                // empty one.
                width: parent.width
                height: Math.min(root.results.length, Theme.menuMaxRows) * Theme.menuRowHeight
                visible: root.results.length > 0

                model: root.results
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Selection is driven from the query line's key handler; the
                // view must not also react to arrows or the two fight.
                keyNavigationEnabled: false
                highlightMoveDuration: 0

                // Cursor movement clamps rather than wraps. Wrapping from the
                // last row back to the first reads as "the list reset" when
                // you are holding Down to scan a long list.
                function step(delta) {
                    if (root.results.length === 0)
                        return;

                    const next = Math.max(0, Math.min(root.results.length - 1, list.currentIndex + delta));
                    list.currentIndex = next;
                    list.positionViewAtIndex(next, ListView.Contain);
                    // Scrolling drags rows past a stationary pointer, which
                    // would otherwise read as hovering and yank the selection
                    // back.
                    root.disarmPointer();
                }

                delegate: Rectangle {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property bool selected: row.index === list.currentIndex

                    // Entries that set GenericName to their own name (Handy,
                    // several KDE apps) would otherwise print it twice across
                    // the row for no information.
                    readonly property string detailText: {
                        const candidate = row.modelData.generic || row.modelData.comment || "";
                        return candidate.toLowerCase() === String(row.modelData.name || "").toLowerCase() ? "" : candidate;
                    }

                    width: list.width
                    height: Theme.menuRowHeight
                    radius: Theme.menuRowRadius
                    color: row.selected ? Theme.menuSelectedBackground : "transparent"

                    IconImage {
                        id: icon

                        anchors.left: parent.left
                        anchors.leftMargin: Theme.menuPadding / 2
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: Theme.menuIconSize
                        // The fallback matters: plenty of entries name an icon
                        // no installed theme carries, and IconImage on an empty
                        // source leaves a hole where the column should be.
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }

                    Text {
                        id: name

                        anchors.left: icon.right
                        anchors.leftMargin: Theme.menuPadding / 2
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: detail.left
                        anchors.rightMargin: Theme.menuPadding / 2

                        text: row.modelData.name
                        color: row.selected ? Theme.menuSelectedForeground : Theme.foreground
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }

                    // Trailing, dimmed, and first to be squeezed: it is context
                    // for an ambiguous name ("Files", "Console"), not the row's
                    // identity.
                    Text {
                        id: detail

                        anchors.right: parent.right
                        anchors.rightMargin: Theme.menuPadding / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, list.width / 3)

                        text: row.detailText
                        color: row.selected ? Theme.menuSelectedForeground : Theme.menuDetailForeground
                        opacity: row.selected ? 0.7 : 1
                        font.pixelSize: Theme.menuDetailFontSize
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: rowPointer

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onEntered: {
                            if (root.pointerArmed)
                                list.currentIndex = row.index;
                        }

                        onPositionChanged: {
                            // Compared in the card's coordinates, not the
                            // row's: a row sliding under the pointer changes
                            // the row-local position without the pointer
                            // having moved at all.
                            if (root.pointerMoved(rowPointer.mapToItem(card, rowPointer.mouseX, rowPointer.mouseY)))
                                list.currentIndex = row.index;
                        }

                        // A click is unambiguous intent, gate or no gate.
                        onClicked: root.activate(row.index)
                    }
                }
            }
        }
    }
}
