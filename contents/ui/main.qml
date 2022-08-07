/// Ideas
/// - handle quater tiling
/// - restore previous window size on un-snap
/// - handle keyboard shortcut snapping + control from keyboard
/// - if one of the windows is unsnapped or closed, unsnap the second one (option in settings)
/// - support for Krunner text field to launch new apps

import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import org.kde.kwin 2.0 as KWinComponents
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQml.Models 2.2
import org.kde.plasma.components 3.0 as PlasmaComponents

Window {
    id: mainWindow
    flags: Qt.X11BypassWindowManagerHint
    visible: true
    color: "transparent"
    x: mainWindow.width * 2
    y: mainWindow.height * 2
    height: 1
    width: 1

    property bool activated: false
    property var clients: null
    property var lastActiveClient: null /// last active client to focus if cancelled
    property int focusedIndex: 0 /// selection by keyboard
    property var activationTime: ({}) /// store timestamps of last window's activation

    /// for quater tiling
    property var currentScreenQuaters: ({}) /// store quaters of the current screen
    property var filteredClients: ([]) /// clients to filter (which are already snapped)
    property int currentScreenWidth: 1
    property int currentScreenHeight: 1
    property int assistPadding: 0  /// padding to add around assist when quater snap

    property int columnsCount: 2
    property int gridSpacing: 25
    property color cardColor
    property color hoveredCardColor
    property color backdropColor
    property color textColor
    property int cardHeight: 220
    property int cardWidth: 370
    property bool cycleKeyboard: false

    property int borderRadius
    property bool sortByLastActive
    property bool showMinimizedWindows
    property bool showOtherScreensWindows
    property bool showOtherDesktopsWindows
    property bool descendingOrder


    Connections {
        target: workspace
        function onClientActivated(window) {
            if (!window) return;
            handleWindowFocus(window);
        }
        function onClientRemoved(window) {
            if (sortByLastActive) delete activationTime[window.windowId];
        }
        function onClientAdded(window) {
            addListenersToClient(window);
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
            addListenersToClient(windows[i]);
        }
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
            duration: 150
        }

        /// click on empty space to close
        MouseArea {
            anchors.fill: parent
            onClicked: {  if (activated) hideAssist(true); }
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
                                        width: parent.width - 24
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
                                    selectClient(modelData);
                                }
                            }
                        }
                    }
            }
        }
    }

    /// Close button
    PlasmaComponents.Button {
        id: closeButton
        x: mainWindow.width - 50
        y: 20
        height: 30
        width: 30
        visible: true
        flat: false
        focusPolicy: Qt.NoFocus
        icon.name: "window-close"
        icon.height: 30
        icon.width: 30

        ToolTip.delay: 1000
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Close snap assist")

        onClicked: hideAssist(true);
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
        focus: true
        Keys.onPressed: function(event) {
            if (activated == false) return;

               switch (event.key) {
                case Qt.Key_Escape:
                    hideAssist(true);
                    break;
                case Qt.Key_Left:
                    moveFocusLeft();
                    break;
                case Qt.Key_Right:
                    moveFocusRight();
                    break;
                case Qt.Key_Up:
                    moveFocusUp();
                    break;
                case Qt.Key_Down:
                    moveFocusDown();
                    break;
                case Qt.Key_Return:
                    selectClient(clients[focusedIndex]);
                    break;
                case Qt.Key_Tab:
                     if (event.modifiers & Qt.ShiftModifier) {
                        moveFocusLeft();
                    } else {
                        moveFocusRight();
                    }
                    break;
                }

                if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) event.accepted = true;
        }
    }

    /// Functions
    function loadConfigs() {
        sortByLastActive = KWin.readConfig("sortByLastActive", true);
        descendingOrder = KWin.readConfig("descendingOrder", true);
        showMinimizedWindows = KWin.readConfig("showMinimizedWindows", true);
        showOtherScreensWindows = KWin.readConfig("showOtherScreensWindows", false);
        showOtherDesktopsWindows = KWin.readConfig("showOtherDesktopsWindows", false);
        textColor = KWin.readConfig("textColor", "#ffffff");
        cardColor = KWin.readConfig("cardColor", "#75475057");
        hoveredCardColor = KWin.readConfig("hoveredCardColor", "#75d9dde1");
        backdropColor = KWin.readConfig("backdropColor", "#50000000");
        borderRadius = KWin.readConfig("borderRadius", 5);
    }

    function addListenersToClient(client) {
        client.frameGeometryChanged.connect(function() {
            if (!client.move && !client.resize && activated == false) onWindowResize(client);
        });
    }

    function sortClientsByLastActive() {
         clients = clients.sort(function(a, b) {
             const windowIdA = a.windowId, windowIdB = b.windowId;
            if (activationTime[windowIdA] && !activationTime[windowIdB]) return 1;
            if (!activationTime[windowIdA] && activationTime[windowIdB]) return -1;
            return activationTime[windowIdA] - activationTime[windowIdB];
        });
    }

    function onWindowResize(window) {
        if (activated) hideAssist();

        const maxArea = workspace.clientArea(KWin.MaximizeArea, window);
        currentScreenWidth = maxArea.width; currentScreenHeight = maxArea.height;
        const dx = window.x, dy = window.y;
        const width = window.width, height = window.height;
        const halfScreenWidth = currentScreenWidth / 2, halfScreenHeight = currentScreenHeight / 2;

        /// Detect if window was snapped
        /// left/right halves
        if (width === halfScreenWidth && height == currentScreenHeight && dy === maxArea.y) {
            if (dx === maxArea.x) {
                /// show on right half
                delayedShowAssist(maxArea.x + window.width, window.y, undefined, undefined, window);
            } else if (dx === maxArea.x + halfScreenWidth) {
                /// show on left half
                delayedShowAssist(maxArea.x, maxArea.y, undefined, undefined, window);
            }
            columnsCount = 2;
            assistPadding = 0;

        /// top/bottom halves
        } else if (width == currentScreenWidth && height == currentScreenHeight / 2 && dx === maxArea.x) {
            if(dy === maxArea.y) {
                /// show in bottom half
                delayedShowAssist(maxArea.x, maxArea.y + halfScreenHeight, halfScreenHeight, currentScreenWidth);
            } else if (dy === maxArea.y + halfScreenHeight) {
                /// show in top half
                delayedShowAssist(maxArea.x, maxArea.y, halfScreenHeight, currentScreenWidth);
            }
            columnsCount = 3;
            assistPadding = 0;
        }

        /// quater tiling
        else if (width === halfScreenWidth && height == halfScreenHeight) {
            assistPadding = 9;

            /// define current screen quaters
             currentScreenQuaters = {
                0: { dx: maxArea.x, dy:  maxArea.y, height: halfScreenHeight, width: halfScreenWidth, },
                1: { dx: maxArea.x + halfScreenWidth, dy:  maxArea.y, height: halfScreenHeight, width: halfScreenWidth, },
                2: { dx: maxArea.x, dy:  maxArea.y + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
                3: { dx: maxArea.x + halfScreenWidth, dy:  maxArea.y + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
            };

            /// detect which quater snapped window takes
            let currentQuater = -1;
            let l = Object.keys(currentScreenQuaters).length;

            for (let i = 0; i < l; i++) {
                const quater = currentScreenQuaters[i];
                if (dx == quater.dx && dy == quater.dy) {
                    currentQuater = i;
                    delete currentScreenQuaters[i];
                    break;
                }
            }

            /// show snap assist in next quater
            if (currentQuater == -1) return;
            checkToShowNextQuaterAssist(window);
        }
    }

    function handleWindowFocus(window) {
        if (activated) hideAssist(false);

        /// Store timestamp of last window activation
        if (sortByLastActive) {
            const d = new Date();
            activationTime[window.windowId] = d.getTime();
        }
    }

    function delayedShowAssist(dx, dy, height, width, window){
            clients = Object.values(workspace.clients).filter(c => shouldShowWindow(c));
            if (clients.length == 0) return;

            if (sortByLastActive) sortClientsByLastActive();
            if (descendingOrder) clients = clients.reverse();

            cardWidth = currentScreenWidth / 5;
            cardHeight = cardWidth / 1.68;
            lastActiveClient = workspace.activeClient;

            timer.setTimeout(function(){
                mainWindow.requestActivate();
                keyboardHandler.forceActiveFocus();
                showAssist(dx, dy, height ?? currentScreenHeight, width ?? currentScreenWidth - window.width);
            }, 1);
    }

    function checkToShowNextQuaterAssist(lastSelectedClient){
        const keys = Object.keys(currentScreenQuaters);
        const l = keys.length;

        if (l > 0) {
            if (lastSelectedClient) filteredClients.push(lastSelectedClient);
            const nextQuater = currentScreenQuaters[keys[0]];
            delete currentScreenQuaters[keys[0]];
            delayedShowAssist(nextQuater.dx + (assistPadding / 2), nextQuater.dy + (assistPadding / 2), nextQuater.height - assistPadding, nextQuater.width - assistPadding);
            if (lastSelectedClient) lastActiveClient = lastSelectedClient;
        } else {
            filteredClients = [];
        }
    }

    function showAssist(dx, dy, height, width) {
        activated = true;
        focusedIndex = 0;
        mainWindow.width = width;
        mainWindow.height = height;
        mainWindow.x = dx;
        mainWindow.y = dy;
        fadeInAnimation.restart();
        scrollView.ScrollBar.vertical.position = 0;
    }

    function hideAssist(shouldFocusLastClient) {
        activated = false;
        mainWindow.x = mainWindow.width * 2;
        mainWindow.y = mainWindow.height * 2;
        mainWindow.width = 0;
        mainWindow.height = 0;

        /// gets called when assist closed without selecting item
        if (shouldFocusLastClient == true) {
            if(lastActiveClient) workspace.activeClient = lastActiveClient;
            filteredClients = [];
            currentScreenQuaters = {};
        }
    }

    function shouldShowWindow(client) {
        if (filteredClients.includes(client)) return false;
        if (client.active || client.specialWindow) return false;
        if (!showMinimizedWindows && client.minimized) return false;
        if (!showOtherScreensWindows && client.screen !== workspace.activeScreen) return false;
        if (!showOtherDesktopsWindows && client.desktop !== workspace.currentDesktop) return false;
        return true;
    }

    function selectClient(client){
        const clientGeometry = client.geometry;
        clientGeometry.x = mainWindow.x - (assistPadding / 2);
        clientGeometry.y = mainWindow.y - (assistPadding / 2);
        clientGeometry.width = mainWindow.width + assistPadding;
        clientGeometry.height = mainWindow.height + assistPadding;
        workspace.activeClient = client;
        checkToShowNextQuaterAssist(client);
    }

    function moveFocusLeft() {
        focusedIndex = focusedIndex - 1;
        if (focusedIndex < 0) focusedIndex = cycleKeyboard ? clients.length - 1 : 0;
        scrollItemIntoView(focusedIndex);
    }

    function moveFocusRight() {
        focusedIndex = focusedIndex + 1;
        const lastIndex = clients.length - 1;
        if (focusedIndex > lastIndex) focusedIndex = cycleKeyboard ? 0 : lastIndex;
        scrollItemIntoView(focusedIndex);
    }

    function moveFocusUp(){
        if(focusedIndex - columnsCount >= 0) {
           focusedIndex = focusedIndex - columnsCount;
           scrollItemIntoView(focusedIndex);
        }
    }

    function moveFocusDown(){
        const clientsLen = clients.length;
        if(focusedIndex + columnsCount < clients.length) {
            focusedIndex = focusedIndex + columnsCount;
            scrollItemIntoView(focusedIndex);
        } else {
            focusedIndex =  clients.length - 1;
            scrollItemIntoView(focusedIndex);
        }
    }

    function scrollItemIntoView(index) {
        const dy = clientsRepeater.itemAt(index).y, viewHeight = mainWindow.height * 0.95;
        const scrollStep = (cardHeight + gridSpacing)  / scrollView.contentHeight;
        if (dy > viewHeight) scrollView.ScrollBar.vertical.position += scrollStep;
        else if (dy < scrollView.ScrollBar.vertical.position) scrollView.ScrollBar.vertical.position -= scrollStep;
    }
}
