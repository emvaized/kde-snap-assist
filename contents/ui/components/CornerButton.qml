import QtQuick 2.12
import QtQuick.Controls 2.12
import org.kde.plasma.components 3.0 as PlasmaComponents

PlasmaComponents.Button {
        x: mainWindow.width - 50
        height: 30
        width: 30
        visible: true
        flat: false
        focusPolicy: Qt.NoFocus
        icon.height: 30
        icon.width: 30

        ToolTip.delay: 1000
        ToolTip.visible: hovered

        background: Rectangle {
            color: "#31363B"
            radius: 3
            border.width: 1
            border.color: parent.hovered ? activePalette.highlight : "gray"
        }
}
