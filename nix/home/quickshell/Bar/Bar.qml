import Quickshell

// The Bar plugin: one BarPanel per connected monitor.
//
// Variants tracks `Quickshell.screens`, so hotplugging a monitor creates and
// destroys bar surfaces without a shell restart. waybar achieved the same by
// spawning a surface per output from a single process.
Scope {
    Variants {
        model: Quickshell.screens

        BarPanel {}
    }
}
