import QtQuick 2.12
import QtQuick.Window 2.12
import QtGraphicalEffects 1.12
import org.kde.plasma.core 2.0 as PlasmaCore

PlasmaCore.WindowThumbnail {
        winId: desktopWindowId
        id: desktopBackground
        y: - (mainWindow.y - minDy)
        x: - (mainWindow.x - minDx)
        //height: currentScreenHeight
        height: Screen.height
        width: currentScreenWidth
        opacity: 1
        visible: showDesktopBackground

        /// configurable blur
        FastBlur {
            id: blurBackground
            anchors.fill: parent
            source: desktopBackground
            radius: desktopBackgroundBlur
            visible: true
            cached: true
        }
    }
