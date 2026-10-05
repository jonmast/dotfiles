pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The Google TV bridge, as seen from QML.
//
// One `googletv-remote` process (nix/home/scripts/googletv-remote.py) lives
// for the whole session. Commands go down its stdin as lines; it answers
// with one JSON state record per line on stdout, every time anything changes.
// This singleton is that record, plus the handful of verbs the widget and
// panel need. Neither of them ever sees the process.
//
// A singleton, like Osd/Brightness, because the pill and the panel both read
// the same state and only one of them may own the process — two bridges
// would be two TLS sessions the TV has to hold open, and two sets of state
// callbacks disagreeing about which one is current.
//
// The shape is deliberately different from DwtWidget's spawn-per-click: the
// remote protocol is a paired TLS session that costs a handshake to set up
// and carries power/app updates only while it stays up. See the script's
// docstring for the wire format and the status vocabulary echoed below.
Singleton {
    id: root

    // Mirrors the bridge's `status`: unconfigured, connecting, unreachable,
    // unpaired, pairing, connected, reconnecting. Plus one of our own —
    // `down` — for the bridge process itself not running.
    property string status: "down"
    property string host: ""
    // null until the TV has said; a bare `false` would draw "off" for a TV we
    // have not reached yet.
    property var powered: null
    property string app: ""
    // Packages the bridge has seen in front, most recent first. Learned, not
    // configured: the protocol will not say what is installed, so this is the
    // only list that can be both accurate and unattended. Empty on a fresh
    // state dir and fills in as the TV gets used.
    property var apps: []
    property var volume: null
    property string error: ""
    // The TV set, which is a different device from the streamer everything
    // else here describes — see the bridge's docstring. `powered` is true
    // whenever the streamer is awake, including with the screen off, so it is
    // the wrong thing to hang a power control on; this is the right one.
    property var tvPowered: null

    readonly property bool connected: status === "connected"
    readonly property bool isOn: connected && powered === true
    readonly property bool tvIsOn: tvPowered === true

    // A dark set explains a dead link, and is not a fault worth reporting.
    // The streamer sleeps when the set does and takes the TLS session with
    // it, so an off TV rests at `reconnecting` — or `unreachable`, if the
    // bridge started after the TV went off. Strictly false, never merely
    // unknown: a set we have not reached says nothing about the link.
    readonly property bool standby: tvPowered === false && (connected || status === "reconnecting" || status === "unreachable")

    // Package → what a person calls it. Purely cosmetic, and membership gates
    // nothing: an unlisted package falls back to its last dotted segment, so
    // a newly installed app shows up named, just less gracefully. The entries
    // here are the ones where that fallback embarrasses itself ("ninja",
    // "livingroom", "launcherx").
    readonly property var appNames: ({
        "com.google.android.apps.tv.launcherx": "Home",
        "com.google.android.tvlauncher": "Home",
        "com.google.android.youtube.tv": "YouTube",
        "com.google.android.youtube.tvkids": "YouTube Kids",
        "com.google.android.videos": "Google TV",
        "com.netflix.ninja": "Netflix",
        "com.amazon.amazonvideo.livingroom": "Prime Video",
        "com.disney.disneyplus": "Disney+",
        "com.plexapp.android": "Plex",
        "org.jellyfin.androidtv": "Jellyfin",
        "com.spotify.tv.android": "Spotify",
        "com.apple.atve.androidtv.appletv": "Apple TV",
        "com.wbd.stream": "Max",
        "com.hbo.hbonow": "Max",
        "tv.twitch.android.app": "Twitch",
        "com.google.android.tvrecommendations": "Home",
        "com.android.tv.settings": "Settings"
    })

    function label(pkg) {
        if (!pkg)
            return "";
        if (root.appNames[pkg])
            return root.appNames[pkg];
        const parts = pkg.split(".");
        return parts[parts.length - 1];
    }

    readonly property string appName: root.label(root.app)

    // One line for a tooltip or a panel header.
    readonly property string summary: {
        // Outranks the whole status vocabulary: the link's business is not
        // worth narrating for a TV that is off.
        if (root.standby)
            return "Standby";
        switch (root.status) {
        case "down":
            return "Bridge not running";
        case "unconfigured":
            return "No TV address set";
        case "connecting":
            return "Connecting…";
        case "unreachable":
            return "Unreachable";
        case "unpaired":
            return "Not paired";
        case "pairing":
            return "Enter the code shown on the TV";
        case "reconnecting":
            return "Reconnecting…";
        case "connected":
            // Naming an app for a screen you cannot see is the confusion this
            // whole widget used to create.
            if (root.powered === false)
                return "Standby";
            return root.appName ? root.appName : "On";
        }
        return root.status;
    }

    function send(line) {
        if (!bridge.running)
            return;
        bridge.write(line + "\n");
    }

    function key(code) {
        send("key " + code);
    }

    function launch(pkg) {
        send("launch " + pkg);
    }

    // "on" or "off". Not a key: the two directions take different routes to
    // different devices, which is the bridge's problem, not ours.
    function power(state) {
        send("power " + state);
    }

    function setHost(addr) {
        send("host " + addr);
    }

    function pair() {
        send("pair");
    }

    function finishPairing(pin) {
        send("pin " + pin);
    }

    function retry() {
        send("retry");
    }

    Process {
        id: bridge

        command: ["googletv-remote"]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => {
                let rec;
                try {
                    rec = JSON.parse(data);
                } catch (e) {
                    console.warn("googletv: bad record from bridge:", data);
                    return;
                }
                root.status = rec.status;
                root.host = rec.host || "";
                root.powered = rec.powered;
                root.app = rec.app || "";
                root.apps = rec.apps || [];
                root.volume = rec.volume;
                root.error = rec.error || "";
                root.tvPowered = rec.tv_powered;
            }
        }

        stderr: SplitParser {
            onRead: data => console.warn("googletv-remote:", data)
        }

        onExited: (code, status) => {
            root.status = "down";
            root.powered = null;
            root.app = "";
            root.error = "bridge exited (" + code + ")";
            respawn.start();
        }
    }

    // The bridge is not expected to die, but if it is missing from PATH
    // (fresh checkout, no rebuild yet) or the library throws, a tight
    // restart loop would spawn a python every few milliseconds forever.
    Timer {
        id: respawn

        interval: 10000
        repeat: false
        onTriggered: bridge.running = true
    }
}
