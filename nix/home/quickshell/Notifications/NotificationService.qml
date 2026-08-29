pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import qs.Common

// The notification daemon. This is the thing that replaced mako (issue 05):
// `NotificationServer` claims `org.freedesktop.Notifications` on the session
// bus, so notify-send, libnotify applications and Chromium web apps all land
// here.
//
// Exactly ONE process may own that bus name. mako was removed from
// nix/home/hyprland.nix in the same commit that added this file, and the two
// halves must not be separated: with both running, whichever loses the race
// silently receives nothing, and the symptom is "notifications sometimes stop
// working after a reboot" rather than an error anywhere. ADR 0001 recorded
// this as the reason the stub stayed empty through issues 03-04.
//
// A singleton rather than state inside the Scope, because two subtrees need
// it: the surfaces in Notifications.qml, and the Bar's DND indicator. QML's
// implicit directory import does not cross directories, so the Bar imports
// `qs.Notifications` for this.
Singleton {
    id: root

    // ---- do not disturb -------------------------------------------------
    //
    // Suppresses banners only. Every notification still reaches the history
    // below, which is the whole point — a DND that drops notifications on the
    // floor is a DND that costs you a 2FA code.
    //
    // Deliberately NOT persisted across a shell restart. The failure mode of
    // persistence is silent and open-ended: DND left on from last week, no
    // banners, and no reason to suspect the shell. Restarting the shell (or
    // logging in) starting in the "notifications work" state is the safer
    // default, and matches what a stateless mako did.
    property bool dnd: false

    function toggleDnd(): bool {
        root.dnd = !root.dnd;
        return root.dnd;
    }

    // ---- history --------------------------------------------------------
    //
    // Plain JS snapshots, not Notification objects. A Notification is
    // destroyed as soon as it is dismissed or expires, so anything that
    // outlives the banner has to be a copy. That copy is deliberately
    // read-only: no actions, no inline reply.
    //
    // The alternative — keeping every notification `tracked` so the history
    // could still invoke its actions — means holding a DBus-visible object
    // for every notification of the session and telling the sending
    // application the notification is still open forever. Reading back what
    // you missed is the requirement; acting on it an hour later is not.
    property var history: []

    function clearHistory() {
        root.history = [];
    }

    function record(notification) {
        // `transient` is the sender saying "do not put this in a notification
        // area" — the spec's own opt-out, used by things like volume applets
        // that would otherwise fill the history with noise. Honour it.
        if (notification.transient)
            return;

        const entry = {
            appName: notification.appName,
            appIcon: notification.appIcon,
            image: notification.image,
            summary: notification.summary,
            body: notification.body,
            urgency: notification.urgency,
            time: new Date()
        };

        // Newest first: the history is read top-down looking for what just
        // happened, unlike the banner column which grows downward so that
        // existing banners never move.
        const next = [entry].concat(root.history);
        root.history = next.slice(0, Theme.notifHistoryMax);
    }

    // ---- lifetimes ------------------------------------------------------

    // Milliseconds a banner should stay up, or 0 for "until dismissed".
    //
    // The sender's own timeout wins where it gave one, per the spec: -1 means
    // "server decides", 0 means "never expire". Honouring an explicit 0 means
    // a badly-behaved application can pin a banner until it is clicked — that
    // is the spec's bargain, and the click is right there.
    function timeoutFor(notification): int {
        // Critical outranks the sender. A notification the system considers
        // critical (low battery, a failing disk) should not vanish while you
        // are looking away.
        if (notification.urgency === NotificationUrgency.Critical)
            return 0;

        if (notification.expireTimeout === 0)
            return 0;

        if (notification.expireTimeout > 0)
            return Math.round(notification.expireTimeout * 1000);

        return notification.urgency === NotificationUrgency.Low ? Theme.notifTimeoutLow : Theme.notifTimeoutNormal;
    }

    function accentFor(urgency): color {
        switch (urgency) {
        case NotificationUrgency.Critical:
            return Theme.notifAccentCritical;
        case NotificationUrgency.Low:
            return Theme.notifAccentLow;
        default:
            return Theme.notifAccentNormal;
        }
    }

    // ---- server ---------------------------------------------------------

    readonly property NotificationServer server: NotificationServer {
        // Capabilities are advertised over DBus, and applications adapt to
        // them — claiming one we do not honour is how you get a notification
        // whose body is a wall of raw markup.
        //
        // Not claimed: bodyMarkup/bodyHyperlinks/bodyImages (the body is
        // rendered as plain text, see NotificationCard), actionIcons (actions
        // are drawn as text buttons), inlineReply (no reply field), and
        // persistence (the history is in-memory only and does not survive a
        // shell restart — claiming it would be a lie to the sender).
        actionsSupported: true
        imageSupported: true
        bodySupported: true

        // Survives a QML config reload, which is what happens constantly
        // during development (`quickshell -p ...` and file watching). A full
        // process restart still clears everything; nothing here is on disk.
        keepOnReload: true

        onNotification: notification => {
            root.record(notification);

            // Critical bypasses DND. The standard behaviour across desktops,
            // and the reason is the same as the timeout rule above: DND means
            // "stop interrupting me about chat messages", not "hide the
            // battery warning".
            if (root.dnd && notification.urgency !== NotificationUrgency.Critical)
                return;

            // Tracking is opt-in: a notification not marked tracked here is
            // dropped the moment this handler returns. So this line is what
            // decides there is a banner at all, and the suppressed path above
            // needs no further work.
            notification.tracked = true;
        }
    }

    // The live banner set, oldest first, capped so a burst cannot run the
    // column off the bottom of the screen. Over the cap the OLDEST are hidden
    // rather than the newest dropped — they are still tracked, still counting
    // down their own timers, and still in the history.
    readonly property var banners: {
        const all = root.server.trackedNotifications.values;
        return all.slice(Math.max(0, all.length - Theme.notifMaxBanners));
    }

    function dismissAllBanners() {
        // Copied before iterating: dismiss() destroys the object, which
        // mutates the model this list came from.
        const live = root.server.trackedNotifications.values.slice();
        for (const notification of live)
            notification.dismiss();
    }
}
