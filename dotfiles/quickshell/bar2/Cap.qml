import QtQuick

// One half-circle-ended pill holding a row of modules.
Rectangle {
    default property alias content: capRow.data

    y: 4
    height: 22
    radius: 11
    color: Theme.c("base")
    width: capRow.width + 10

    Row {
        id: capRow
        x: 5
        height: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
    }
}
