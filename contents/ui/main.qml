/// Ideas:
/// - refactor all complex height/width calculations to use simple 12x12 virtual grid
/// - "skip layout" button, which would allow to skip to next assist position from the quatersToShowNext
/// - support for Krunner text field to launch new apps
/// - restore previous size on un-snapping of programatically snapped window
/// - create task switcher widget which will visually show windows tiled using this assist, allowing to minimize/restore them at once

import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import org.kde.kwin 2.0 as KWinComponents
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQml.Models 2.2
import org.kde.plasma.components 3.0 as PlasmaComponents

import "components"
import "./code/assist.js" as AssistManager
import "./code/keyboard.js" as KeyboardManager
import "./code/windows.js" as WindowManager

Window {
    id: mainWindow
    flags: Qt.FramelessWindowHint | Qt.X11BypassWindowManagerHint
    visible: true
    color: "transparent"
    x: mainWindow.width * 2
    y: mainWindow.height * 2
    height: 1
    width: 1

    /// service variables
    property bool activated: false
    property var clients: null
    property var lastActiveClient: null /// last active client to focus if cancelled
    property int focusedIndex: 0 /// selection by keyboard
    property var activationTime: ({}) /// store timestamps of last window's activation
    property int cardHeight: 220 /// calculated dynamically before assist reveal
    property int cardWidth: 370
    property int columnsCount: 2 /// calculated depending on available width
    property int gridSpacing: 25 /// maybe should be configurable?
    property bool cycleKeyboard: false /// not in use
    property bool preventFromShowing: false /// flag used to temporarly prevent assist from showing when not desired

    /// for tracking snapped windows
    property bool trackSnappedWindows: true
    property var snappedWindowGroups: ([]) /// store snapped windows in groups
    property var snappedWindows: ([]) /// temporarly store windows which will be added in group on finish
    property bool ignoreFocusChange: false /// prevent endless loop for raiseSnappedTogether

    /// for quater tiling
    property var quatersToShowNext: ({}) /// store next quaters to show assist after selection
    property var filteredClients: ([]) /// clients to filter (which are already snapped in current flow)
    property var filteredQuaters: ([]) /// quaters to ignore during iteration (occupied by big window)
    property int currentScreenWidth: 1
    property int currentScreenHeight: 1
    property int minDx: 0 /// store the real "0" dx coordinate
    property int minDy: 0
    property int assistPadding: 0  /// padding to add around assist (not applied to windows)
    property int layoutMode: 0 /// 0 - horizontal halve, 1 - quater, 2 - vertical halve
    property var storedQuaterPosition: ({}) /// store initial quater position for Tab button switching
    property var storedFirstQuaterToShow: ({}) /// store planned first quater for Tab button switching

    /// configurable
    property int transitionDuration
    property color cardColor
    property color hoveredCardColor
    property color backdropColor
    property color textColor
    property int borderRadius
    property bool sortByLastActive
    property bool showMinimizedWindows
    property bool showOtherScreensWindows
    property bool showOtherDesktopsWindows
    property bool descendingOrder
    property int snapDetectPrecision
    property bool showSnappedWindows
    property bool minimizeSnappedTogether
    property bool raiseSnappedTogether
    property bool fillOnSnappedClose
    property int delayBeforeShowingAssist

    Connections {
        target: workspace
        function onClientActivated(window) {
            if (!window) return;
            WindowManager.handleWindowFocus(window);
        }
        function onClientAdded(window) {
            WindowManager.addListenersToClient(window);
        }
        function onClientFullScreenSet(client, isFullScreen, isUser) {
            /// we likely don't want assist to be shown when user exited fullscreen mode
            if (isFullScreen == false) AssistManager.preventAssistFromShowing();
        }
        function onClientMinimized(client){
            if (!trackSnappedWindows || !minimizeSnappedTogether) return;
            WindowManager.applyActionToAssosiatedSnapGroup(client, function(cl){ if (cl) cl.minimized = true; });
        }
        function onClientUnminimized(client){
            if (!trackSnappedWindows || !minimizeSnappedTogether) return;
            WindowManager.applyActionToAssosiatedSnapGroup(client, function(cl) { if (cl) cl.minimized = false; });
        }
        function onVirtualScreenSizeChanged(){
            /// Fix for assist getting shown when screen size changed
            AssistManager.preventAssistFromShowing(1000, () => hideAssist(false));
        }
    }

    /// Doesn't work for some reason :(
    /// hence the recommendation to re-enable the script on configs page
    Connections {
        target: options
        function onConfigChanged() { loadConfigs(); }
    }

    Component.onCompleted: {
        loadConfigs();
        const windows = workspace.clients;
        for (let i = 0; i < windows.length; ++i) {
            WindowManager.addListenersToClient(windows[i]);
        }

        mainWindow.hide();
    }

    /// Main view
    Rectangle {
        id: assistBackground
        width: mainWindow.width
        height: mainWindow.height
        color: backdropColor

        /// fade-in animation on appear
        NumberAnimation on opacity {
            id: fadeInAnimation
            from: 0
            to: 1
            duration: transitionDuration
        }

        /// click on empty space to close
        MouseArea {
            anchors.fill: parent
            onClicked: {  if (activated) AssistManager.hideAssist(true); }
        }

        ScrollView {
            id: scrollView
            anchors.centerIn: parent
            height: gridView.height > mainWindow.height * 0.95 ? mainWindow.height * 0.95 : gridView.height
            width: columnsCount * (cardWidth + gridSpacing)

            Grid {
                id: gridView
                columns: columnsCount
                spacing: gridSpacing
                anchors.centerIn: parent

                Repeater {
                    id: clientsRepeater
                    model: clients

                        Rectangle {
                            id: clientItem
                            color: cardColor
                            radius: borderRadius
                            width:  cardWidth
                            height: cardHeight
                            border.color: activePalette.highlight
                            border.width: focusedIndex == index ? 3 : 0
                            visible: true

                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter

                                Rectangle {
                                    height: 8
                                    width: 12
                                    color: "transparent"
                                }

                                /// window title and icon
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    bottomPadding: 8
                                    width: cardWidth - 10

                                    Rectangle {
                                        height: 8
                                        width: 15
                                        color: "transparent"
                                    }

                                    PlasmaCore.IconItem {
                                        id: icon
                                        height: 12 // PlasmaCore.Units.iconSizes.medium?
                                        width: 12
                                        source: modelData.icon
                                    }

                                    Text {
                                        text: modelData.caption
                                        leftPadding: 7
                                        color: textColor
                                        elide: Text.ElideRight
                                        width: parent.width - 26
                                    }
                                }

                                /// window thumbnail
                                KWinComponents.ThumbnailItem {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    id: clientThumbnail
                                    wId: modelData.internalId
                                    clip: true
                                    visible: mainWindow.activated
                                    width: cardWidth - 6
                                    height: cardHeight - 40
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    clientItem.color = hoveredCardColor;
                                }
                                onExited: {
                                    clientItem.color = cardColor;
                                }
                                onClicked: {
                                    WindowManager.selectClient(modelData);
                                }
                            }
                        }
                    }
            }
        }
    }

    /// Close assist button
    CornerButton {
        id: closeButton
        y: 20
        icon.name: "window-close"
        ToolTip.text: qsTr("Close snap assist")
        onClicked: AssistManager.hideAssist(true);
    }

    /// Change layout button
    CornerButton {
        id: changeSizeButton
        y: 60

        Image {
            anchors.centerIn: parent
            source: mainWindow.height == currentScreenHeight && mainWindow.width == currentScreenWidth / 2 ?
                        "icons/vertical-half.svg"
                        : mainWindow.width == currentScreenWidth ?
                            "icons/horizontal-half.svg"
                            : mainWindow.width == currentScreenWidth / 3 ?
                                "icons/three-in-row.svg"
                                : mainWindow.width == currentScreenWidth / 3 * 2 ?
                                    "icons/65-35.svg"
                                    : "icons/quarter.svg"
            sourceSize.width: parent.width - 8
            sourceSize.height: parent.height - 8
            cache: true
            opacity: 0.85
        }

        ToolTip.text: qsTr("Change layout")
        onClicked: AssistManager.switchAssistLayout();
    }

    /// Timer to delay snap assist reveal.
    /// Delay is added to get the updated snapped window's size and location,
    /// which sometimes differs from the half of the screen
    Timer {
        id: timer
        function setTimeout(cb, delayTime) {
            timer.interval = delayTime;
            timer.repeat = false;
            timer.triggered.connect(cb);
            timer.triggered.connect(function release () {
                timer.triggered.disconnect(cb); // This is important
                timer.triggered.disconnect(release); // This is important as well
            });
            timer.start();
        }
    }

    /// Reference for current theme's highlight color
    SystemPalette {
        id: activePalette
        colorGroup: SystemPalette.Active
    }

    /// Keyboard handler
    Item {
        anchors.fill: parent
        id: keyboardHandler
        Keys.onPressed: function(event) {
            if (activated == false) return;

               switch (event.key) {
                case Qt.Key_Escape:
                    AssistManager.hideAssist(true);
                    break;
                case Qt.Key_Left:
                    KeyboardManager.moveFocusLeft();
                    break;
                case Qt.Key_Right:
                    KeyboardManager.moveFocusRight();
                    break;
                case Qt.Key_Up:
                    KeyboardManager.moveFocusUp();
                    break;
                case Qt.Key_Down:
                    KeyboardManager.moveFocusDown();
                    break;
                case Qt.Key_Return:
                    WindowManager.selectClient(clients[focusedIndex]);
                    break;
                case Qt.Key_Tab:
                    AssistManager.switchAssistLayout();
                    break;
                }
        }
    }

    function loadConfigs() {
        sortByLastActive = KWin.readConfig("sortByLastActive", true);
        descendingOrder = KWin.readConfig("descendingOrder", true);
        showMinimizedWindows = KWin.readConfig("showMinimizedWindows", true);
        showOtherScreensWindows = KWin.readConfig("showOtherScreensWindows", false);
        showOtherDesktopsWindows = KWin.readConfig("showOtherDesktopsWindows", false);
        textColor = KWin.readConfig("textColor", "#ffffff");
        cardColor = KWin.readConfig("cardColor", "#75475057");
        hoveredCardColor = KWin.readConfig("hoveredCardColor", "#75d9dde1");
        backdropColor = KWin.readConfig("backdropColor", "#502a2e32");
        borderRadius = KWin.readConfig("borderRadius", 5);
        transitionDuration = KWin.readConfig("transitionDuration", 150);
        snapDetectPrecision = KWin.readConfig("snapDetectPrecision", 0);
        delayBeforeShowingAssist = KWin.readConfig("delayBeforeShowingAssist", 100);
        showSnappedWindows = KWin.readConfig("showSnappedWindows", true);
        minimizeSnappedTogether = KWin.readConfig("minimizeSnappedTogether", false);
        raiseSnappedTogether = KWin.readConfig("raiseSnappedTogether", false);
        fillOnSnappedClose = KWin.readConfig("fillOnSnappedClose", false);
        trackSnappedWindows = minimizeSnappedTogether || raiseSnappedTogether || fillOnSnappedClose || !showSnappedWindows;
    }
}
