import Quickshell

// PLACEHOLDER — filled in by issue 05 (notifications + OSDs).
//
// Deliberately does NOT construct a NotificationServer yet. mako is still the
// notification daemon until issue 05 retires it, and two processes claiming
// `org.freedesktop.Notifications` means whichever loses the race silently
// stops receiving notifications.
Scope {}
