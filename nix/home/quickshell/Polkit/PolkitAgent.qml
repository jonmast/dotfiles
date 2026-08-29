import Quickshell
// Namespaced deliberately. This file IS `qs.Polkit`'s `PolkitAgent`, and
// `Quickshell.Services.Polkit` exports a type of the same name — imported
// plainly, the name below would be ambiguous with the component being defined.
import Quickshell.Services.Polkit as PolkitService

// The polkit authentication agent (issue 06), and the last hole ADR 0002 left
// open: plasma-workspace used to register one, the old Hyprland session never
// did, so under Hyprland a GUI privilege prompt had nowhere to go and the
// caller just failed. `pkexec`, KDE's date/time module, and anything else that
// asks polkit for an admin action now get a dialog.
//
// Registration happens on the SESSION subject (the agent registers itself for
// the session it is running in), which is why this belongs in The Shell rather
// than in a unit of its own: the agent's lifetime should be exactly the
// session's, and quickshell.service is already `PartOf=graphical-session.target`
// (nix/home/hyprland.nix).
//
// No `path:` override — the default `/org/quickshell/Polkit` is fine, and is
// only ever seen over DBus.
//
// The password path is PAM's, not ours: `security.pam.services.polkit-1` on
// diogenes carries `fprintAuth = true` (nix/nixos/diogenes.nix), so a prompt
// here can be a fingerprint stage rather than a password one. The dialog is
// written against `AuthFlow`'s prompts rather than against "type a password",
// which is what makes that work without special-casing it.
// `flow.identities` is left alone: polkit preselects the first identity, and
// on diogenes an admin action resolves to exactly one (the single wheel user).
// A picker would be dead UI. If this shell ever runs somewhere with several
// admins, that is the property to grow a combo box against.
Scope {
    id: root

    PolkitService.PolkitAgent {
        id: agent
    }

    PolkitDialog {
        // `flow` is null whenever no request is in progress; the dialog maps
        // itself on exactly that condition, so there is no separate open/close
        // state to keep in sync (contrast the Menu, which has an IPC surface
        // and therefore needs one).
        flow: agent.flow
    }
}
