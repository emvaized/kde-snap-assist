import QtQuick 2.12
import QtQuick.Window 2.12
import QtGraphicalEffects 1.12
import org.kde.kwin 2.0 as KWinComponents

Item {
    y: - ((immersiveMode ? mainWindow.y : main.y) - minDy)
    x: - ((immersiveMode ? mainWindow.x : main.x) - minDx)
    height: Screen.height
    width: currentScreenWidth
    visible: showDesktopBackground && activated

    KWinComponents.ThumbnailItem {
        wId: desktopWindowId
        id: desktopBackground
        anchors.fill: parent
    }

    /// configurable blur
    FastBlur {
        id: blurBackground
        anchors.fill: parent
        source: desktopBackground
        radius: desktopBackgroundBlur
        cached: false
        visible: desktopBackgroundBlur > 0
    }
}
