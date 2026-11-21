//@ pragma UseQApplication
import QtQuick
import Quickshell

// Capsule bar preview, a second bar under the live one. Start with: qs -c bar2
ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {}
    }
}
