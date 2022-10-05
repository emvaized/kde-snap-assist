/// Ideas:
/// - refactor all complex height/width calculations to use simple 12x12 virtual grid
/// - "skip layout" button, which would allow to skip to next assist position from the quatersToShowNext
/// - support for search field, and maybe Krunner to launch new apps
/// - restore previous size on un-snapping of programatically snapped window
/// - create task switcher widget which will visually show windows tiled using this assist, allowing to minimize/restore them at once (not possible yet)

import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import org.kde.kwin 2.0 as KWinComponents
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQml.Models 2.2
import org.kde.plasma.components 3.0 as PlasmaComponents
import QtGraphicalEffects 1.12

import "components"
import "./code/assist.js" as AssistManager
import "./code/keyboard.js" as KeyboardManager
import "./code/windows.js" as WindowManager

Window {
    id: main
    flags: Qt.FramelessWindowHint | Qt.X11BypassWindowManagerHint
    visible: true
    color: "transparent"
    x: 0
    y: 0
    height: currentScreenHeight
    width: currentScreenWidth

    /// service variables
    property bool activated: false
    property var clients: null /// filtered clients to show in the grid
    property var allClients: null /// all clients fetched on assist reveal
    property var desktopWindowId: null
    property var currentWindowId: null
    property var lastActiveClient: null /// last active client to focus if cancelled
    property int focusedIndex: 0 /// selection by keyboard
    property bool trackActiveWindows: true
    property var activationTime: ({}) /// store timestamps of last window's activation
    property var windowSizesBeforeSnap: ({}) /// store widnow sizes before they were snapped via script (when rememberWindowSizes is on)
    property int cardHeight: 220 /// calculated dynamically before assist reveal
    property int cardWidth: 370
    property int columnsCount: 2 /// calculated depending on available width
    property int gridSpacing: 25 /// maybe should be configurable?
    property bool cycleKeyboard: false /// not in use
    property bool preventFromShowing: false /// flag used to temporarly prevent assist from showing when not desired

    property int transitionDurationOnAssistMove: 0 /// separate transition duration when moving assist window with the Tab key
    property var visibleWindowPreviews: ([]) /// stores windows which should be displayed on top of canvas (snapped)
    property bool showRegularGridPreviews: true /// used for seamless switch between animated and static window previews

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
    property int delayBeforeShowingAssist
    property bool showSnappedWindows
    property bool minimizeSnappedTogether
    property bool raiseSnappedTogether
    property bool fillOnSnappedClose
    property bool fillOnSnappedMove
    property int fitWindowInGroupBehind
    property bool rememberWindowSizes
    property bool showDesktopBackground
    property int desktopBackgroundBlur
    property bool immersiveMode

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
        function onVirtualScreenSizeChanged(){
            /// Fix for assist getting shown when screen size changed
            AssistManager.preventAssistFromShowing(1000, () => AssistManager.hideAssist(false));
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

        main.hide();
    }

    /// Desktop preview on background
    Loader {
        source: !immersiveMode && showDesktopBackground && desktopWindowId != null ? 'components/DesktopBackground.qml' : ''
    }

    Loader {
        active: immersiveMode && desktopWindowId != null
        sourceComponent: Item {
            y: 0
            x: 0
            height: Screen.height
            width: currentScreenWidth
            visible: showDesktopBackground && activated

            KWinComponents.ThumbnailItem {
                wId: desktopWindowId
                id: desktopBackground
                anchors.fill: parent
            }
        }
    }

    /// click on empty space to close
    MouseArea {
        anchors.fill: parent
        onClicked: {  if (activated) AssistManager.hideAssist(true); }
    }

    /// Main view
    Item {
        id: mainWindow
        width: 1
        height: 1
        clip: true
        anchors.fill: immersiveMode ? null : parent

        /// Blurred clipped part of background
        Loader {
            source: immersiveMode && showDesktopBackground && desktopWindowId != null ? 'components/DesktopBackground.qml' : ''
        }

        /// Backdrop color
        Rectangle {
            anchors.fill: parent
            border.color: "#75475057"
            border.width: immersiveMode ? 1 : 0
            color: backdropColor
        }

        /// fade-in animation on appear
        NumberAnimation on opacity {
            id: fadeInAnimation
            from: 0
            to: 1
            duration: transitionDuration
        }

        /// transition on moving assist around
        Behavior on x { PropertyAnimation {duration: transitionDurationOnAssistMove; easing.type: Easing.OutExpo } }
        Behavior on y { PropertyAnimation {duration: transitionDurationOnAssistMove; easing.type: Easing.OutExpo} }
        Behavior on width { PropertyAnimation {duration: transitionDurationOnAssistMove; easing.type: Easing.OutExpo} }
        Behavior on height { PropertyAnimation {duration: transitionDurationOnAssistMove; easing.type: Easing.OutExpo} }

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
                                    visible: activated && (showRegularGridPreviews || modelData.minimized)
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
                                    WindowManager.animateWindowPreviewToSelect(index, modelData);
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
            ToolTip.text: qsTr("Close snap assist (Esc)")
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

            ToolTip.text: qsTr("Change layout (Tab)")
            onClicked: AssistManager.switchAssistLayout();
        }
    }

    /// Snapped windows previews
    Repeater {
        id: windowPreviewsRepeater
        enabled: immersiveMode
        model: visibleWindowPreviews

        KWinComponents.ThumbnailItem {
            wId: modelData.internalId
            clip: true
            visible: !modelData.minimized
            width: modelData.width
            height: modelData.height
            x: modelData.x - minDx
            y: modelData.y - minDy

            Behavior on x { PropertyAnimation {duration: transitionDuration; easing.type: Easing.OutExpo } }
            Behavior on y { PropertyAnimation {duration: transitionDuration; easing.type: Easing.OutExpo} }
            Behavior on width { PropertyAnimation {duration: transitionDuration; easing.type: Easing.OutExpo} }
            Behavior on height { PropertyAnimation {duration: transitionDuration; easing.type: Easing.OutExpo} }
        }
    }

    /// Current window preview
    Loader {
        id: currentWindowPreview
        active: immersiveMode && currentWindowId != null
        sourceComponent: Item {
            width: 1
            height: 1
            x: 0
            y: 0

            KWinComponents.ThumbnailItem {
                wId: currentWindowId
                anchors.fill: parent
            }
        }
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
                    WindowManager.animateWindowPreviewToSelect(focusedIndex, clients[focusedIndex]);
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
        backdropColor = KWin.readConfig("backdropColor", "#902a2e32");
        borderRadius = KWin.readConfig("borderRadius", 5);
        transitionDuration = KWin.readConfig("transitionDuration", 150);
        snapDetectPrecision = KWin.readConfig("snapDetectPrecision", 0);
        delayBeforeShowingAssist = KWin.readConfig("delayBeforeShowingAssist", 100);
        rememberWindowSizes = KWin.readConfig("rememberWindowSizes", true);
        showSnappedWindows = KWin.readConfig("showSnappedWindows", true);
        minimizeSnappedTogether = KWin.readConfig("minimizeSnappedTogether", false);
        raiseSnappedTogether = KWin.readConfig("raiseSnappedTogether", false);
        fillOnSnappedClose = KWin.readConfig("fillOnSnappedClose", false);
        fillOnSnappedMove = KWin.readConfig("fillOnSnappedMove", false);
        fitWindowInGroupBehind = KWin.readConfig("fitWindowInGroupBehind", false);
        showDesktopBackground = KWin.readConfig("showDesktopBackground", false);
        desktopBackgroundBlur = KWin.readConfig("desktopBackgroundBlur", 18);
        immersiveMode = KWin.readConfig("immersiveMode", false);
        trackSnappedWindows = minimizeSnappedTogether || raiseSnappedTogether || fillOnSnappedClose || !showSnappedWindows;
        trackActiveWindows = sortByLastActive || fitWindowInGroupBehind;
        if (!showDesktopBackground) immersiveMode = false;

        /// workaround for configs bug, when boolean gets stored for string values
        if (textColor == false) textColor = "#ffffff";
        if (cardColor == false) cardColor = "#75475057";
        if (hoveredCardColor == false) hoveredCardColor = "#75d9dde1";
        if (backdropColor == false) backdropColor = "#902a2e32";
    }
}
