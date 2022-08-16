/// Ideas:
/// - refactor all complex height/width calculations to use simple 12x12 virtual grid
/// - restore previous size on un-snapping of programatically snapped window
/// - support for Krunner text field to launch new apps
/// - create task switcher widget which will visually show windows tiled using this assist, allowing to minimize/restore them at once
/// - option to filter already snapped windows

import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import org.kde.kwin 2.0 as KWinComponents
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQml.Models 2.2
import org.kde.plasma.components 3.0 as PlasmaComponents

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
    property var screenQuatersToShowNext: ({}) /// store next quaters to show assist after selection
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

    Connections {
        target: workspace
        function onClientActivated(window) {
            if (!window) return;
            handleWindowFocus(window);
        }
        function onClientRemoved(window) {
            handleWindowClose(window);
        }
        function onClientAdded(window) {
            addListenersToClient(window);
        }
        function onClientFullScreenSet(client, isFullScreen, isUser) {
            /// we likely don't want assist to be shown when user exited fullscreen mode
            if (isFullScreen == false) preventAssistFromShowing();
        }

        function onClientMinimized(client){
            if (!trackSnappedWindows || !minimizeSnappedTogether) return;
            applyActionToAssosiatedSnapGroup(client, function(cl){cl.minimized = true; });
        }
        function onClientUnminimized(client){
            if (!trackSnappedWindows || !minimizeSnappedTogether) return;
            applyActionToAssosiatedSnapGroup(client, function(cl) {cl.minimized = false; });
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
                                    selectClient(modelData);
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
        onClicked: hideAssist(true);
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
        }

        ToolTip.text: qsTr("Change layout")
        onClicked: switchAssistLayout();
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
        //focus: true
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
                    switchAssistLayout();
                    break;
                }

                //if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) event.accepted = true;
        }
    }

    /// Functions

    /// general
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
        showSnappedWindows = KWin.readConfig("showSnappedWindows", true);
        minimizeSnappedTogether = KWin.readConfig("minimizeSnappedTogether", false);
        raiseSnappedTogether = KWin.readConfig("raiseSnappedTogether", false);
    }

    function selectClient(client){
        const clientGeometry = client.frameGeometry;
        clientGeometry.x = mainWindow.x - (assistPadding / 2);
        clientGeometry.y = mainWindow.y - (assistPadding / 2);
        clientGeometry.width = mainWindow.width + assistPadding;
        clientGeometry.height = mainWindow.height + assistPadding;
        workspace.activeClient = client;

        if (trackSnappedWindows) {
            removeWindowFromTrack(client.windowId); /// remove from track if was previously snapped
            snappedWindows.push(client.windowId);
        }

        checkToShowNextQuaterAssist(client);
    }

    /// listeners
    function addListenersToClient(client) {
        client.frameGeometryChanged.connect(function() {
            if (!client.move && !client.resize && activated == false && preventFromShowing == false) onWindowResize(client);
        });

        client.clientStartUserMovedResized.connect(function(cl){
            if (trackSnappedWindows) removeWindowFromTrack(cl.windowId);
        });
    }

    function handleWindowFocus(window) {
        if (ignoreFocusChange) return;
        if (activated) hideAssist(false);

        /// Store timestamp of last window activation
        if (sortByLastActive) {
            const d = new Date();
            activationTime[window.windowId] = d.getTime();
        }

        /// Raise all snapped windows together
        if (trackSnappedWindows && raiseSnappedTogether && !activated) {
            const i = snappedWindowGroups.findIndex((group) => group.windows.includes(window.windowId));
            if (i > -1) {
                ignoreFocusChange = true;
                const windows = snappedWindowGroups[i].windows;

                for(let i = 0, l = windows.length; i < l; i++) {
                    if (windows[i] !== window.windowId) {
                        const w = workspace.getClient(windows[i]);
                        if (!w.minimized) workspace.activeClient = w;
                    }
                }

                workspace.activeClient = window;
                timer.setTimeout(function(){
                    ignoreFocusChange = false;
                }, 100);
            }
        }
    }

    function onWindowResize(window) {
        if (activated) hideAssist();

        const maxArea = workspace.clientArea(KWin.MaximizeArea, window);
        currentScreenWidth = maxArea.width; currentScreenHeight = maxArea.height;
        minDx = maxArea.x; minDy = maxArea.y;
        const dx = window.x, dy = window.y;
        const width = window.width, height = window.height;
        const halfScreenWidth = currentScreenWidth / 2, halfScreenHeight = currentScreenHeight / 2;

        /// Detect if window was snapped
        /// left/right halves
        if (isEqual(width, halfScreenWidth) && isEqual(height, currentScreenHeight) && isEqual(dy, minDy)) {
            if (isEqual(dx, minDx)) {
                /// show on right half
                delayedShowAssist(minDx + window.width, window.y, undefined, undefined, window);
            } else if (isEqual(dx, minDx + halfScreenWidth)) {
                /// show on left half
                delayedShowAssist(minDx, minDy, undefined, undefined, window);
            }
            columnsCount = 2;
            layoutMode = 0;

        /// top/bottom halves
        } else if (isEqual(width, currentScreenWidth) && isEqual(height, halfScreenHeight) && isEqual(dx, minDx)) {
            if (isEqual(dy, minDy)) {
                /// show in bottom half
                delayedShowAssist(minDx, minDy + halfScreenHeight, halfScreenHeight, currentScreenWidth);
            } else if (isEqual(dy, minDy + halfScreenHeight)) {
                /// show in top half
                delayedShowAssist(minDx, minDy, halfScreenHeight, currentScreenWidth);
            }
            columnsCount = 3;
            layoutMode = 2;
        }

        /// quater tiling
        else if (isEqual(width, halfScreenWidth) && isEqual(height, halfScreenHeight)) {
            /// define current screen quaters
             screenQuatersToShowNext = {
                0: { dx: minDx, dy:  minDy, height: halfScreenHeight, width: halfScreenWidth, },
                1: { dx: minDx + halfScreenWidth, dy:  minDy, height: halfScreenHeight, width: halfScreenWidth, },
                2: { dx: minDx, dy: minDy + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
                3: { dx: minDx + halfScreenWidth, dy:  minDy + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
            };

            /// detect which quater snapped window takes
            let currentQuater = -1;
            let l = Object.keys(screenQuatersToShowNext).length;

            for (let i = 0; i < l; i++) {
                const quater = screenQuatersToShowNext[i];
                if (isEqual(dx, quater.dx) && isEqual(dy, quater.dy)) {
                    currentQuater = i;
                    delete screenQuatersToShowNext[i];
                    break;
                }
            }

            /// show snap assist in next quater
            if (currentQuater == -1) return;
            checkToShowNextQuaterAssist(window);
            layoutMode = 1;
            columnsCount = 2;
        }

        /// 3-in-row tiling
        else if (isEqual(height, currentScreenHeight)) {
            const thirdOfScreenWidth = currentScreenWidth / 3;
            if (isEqual(width, thirdOfScreenWidth)) {
                /// define current screen thirds
                screenQuatersToShowNext = {
                    0: { dx: minDx, dy:  minDy, height: currentScreenHeight, width: thirdOfScreenWidth, },
                    1: { dx: minDx + thirdOfScreenWidth, dy:  minDy, height: currentScreenHeight, width: thirdOfScreenWidth, },
                    2: { dx: minDx + (thirdOfScreenWidth * 2), dy: minDy, height: currentScreenHeight, width: thirdOfScreenWidth, },
                };

                /// detect which quater snapped window takes
                let currentQuater = -1;
                let l = Object.keys(screenQuatersToShowNext).length;

                for (let i = 0; i < l; i++) {
                    const quater = screenQuatersToShowNext[i];
                    if (isEqual(dx, quater.dx) && isEqual(dy, quater.dy)) {
                        currentQuater = i;
                        delete screenQuatersToShowNext[i];
                        break;
                    }
                }

                /// show snap assist in next quater
                if (currentQuater == -1) return;
                checkToShowNextQuaterAssist(window);
                layoutMode = 3;
                columnsCount = 1;
            }
        }
    }

    function handleWindowClose(window){
        if (sortByLastActive) delete activationTime[window.windowId];

        if (trackSnappedWindows) {
            /// remove window if it was snapped
            removeWindowFromTrack(window.windowId, function(remainingWindows){
                /// callback when snapped window was closed.
                /// we can show the assist here,
                /// or try to resize other windows from the same group to cover the area

            });
        }
    }


    /// assist
    function delayedShowAssist(dx, dy, height, width, window){
        clients = Object.values(workspace.clients).filter(c => shouldShowWindow(c));
        if (clients.length == 0) return;

        if (sortByLastActive) sortClientsByLastActive();
        if (descendingOrder) clients = clients.reverse();

        cardWidth = currentScreenWidth / 5;
        cardHeight = cardWidth / 1.68;
        lastActiveClient = workspace.activeClient;

        timer.setTimeout(function(){
            snappedWindows.push((window ?? workspace.activeClient).windowId);
            mainWindow.requestActivate();
            keyboardHandler.forceActiveFocus();
            showAssist(dx, dy, height ?? currentScreenHeight, width ?? currentScreenWidth - window.width);
        }, 3);
    }

    function showAssist(dx, dy, height, width) {
        activated = true;
        focusedIndex = 0;
        mainWindow.showNormal();
        mainWindow.width = width;
        mainWindow.height = height;
        mainWindow.x = dx;
        mainWindow.y = dy;
        fadeInAnimation.restart();
        scrollView.ScrollBar.vertical.position = 0;
    }

    function preventAssistFromShowing(){
        preventFromShowing = true;
        timer.setTimeout(function(){
            preventFromShowing = false;
        }, 300);
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
            finishSnap();
        }
    }

    function finishSnap(){
        /// gets called when close assist, and no other assists awaiting to show
        if (trackSnappedWindows && snappedWindows.length > 0) {
            /// store snapped windows
            const d = new Date();
            snappedWindowGroups.push({
                timestamp: d.getTime(),
                windows: snappedWindows
            });
        }

        filteredClients = [];
        filteredQuaters = [];
        snappedWindows = [];
        screenQuatersToShowNext = {};
    }


    /// utility functions
    function isEqual(a, b) {
        return a - b <= snapDetectPrecision && a - b >= -snapDetectPrecision;
    }

    function shouldShowWindow(client) {
        if (filteredClients.includes(client)) return false;
        if (client.active || client.specialWindow) return false;
        if (!showMinimizedWindows && client.minimized) return false;
        if (!showOtherScreensWindows && client.screen !== workspace.activeScreen) return false;
        if (!showOtherDesktopsWindows && client.desktop !== workspace.currentDesktop) return false;
        if (!showSnappedWindows && snappedWindowGroups.findIndex(group => group.windows.includes(client.windowId)) > -1) return false;
        return true;
    }

    function sortClientsByLastActive() {
        clients = clients.sort(function(a, b) {
            const windowIdA = a.windowId, windowIdB = b.windowId;
            if (activationTime[windowIdA] && !activationTime[windowIdB]) return 1;
            if (!activationTime[windowIdA] && activationTime[windowIdB]) return -1;
            return activationTime[windowIdA] - activationTime[windowIdB];
        });
    }


    /// snap groups
    function applyActionToAssosiatedSnapGroup(client, callback){
        if (!client.windowId) return;

        const i = snappedWindowGroups.findIndex((group) => group.windows.includes(client.windowId));
        if (i > -1) {
            const windows = snappedWindowGroups[i].windows;
            windows.forEach(windowId => callback(workspace.getClient(windowId)));
        }
    }

    function removeWindowFromTrack(windowId, callback){
        if (!windowId) return;

        let i2 = -1;
        const i = snappedWindowGroups.findIndex(function(group) {
            i2 = group.windows.indexOf(windowId);
            return i2 > -1;
        });

        if (i > -1) {
            snappedWindowGroups[i].windows.splice(i2, 1);
            if (snappedWindowGroups[i].windows.length < 2) snappedWindowGroups.splice(i, 1);
            else if (callback) { callback(snappedWindowGroups[i].windows); }
        }
    }


    /// for quater tiling
    function checkToShowNextQuaterAssist(lastSelectedClient){
        const keys = Object.keys(screenQuatersToShowNext).filter(quaterIndex => !filteredQuaters.includes(parseInt(quaterIndex)));
        const l = keys.length;

        if (l > 0) {
            /// need to show assist in other quaters
            if (lastSelectedClient) filteredClients.push(lastSelectedClient);
            const nextQuater = screenQuatersToShowNext[keys[0]];
            delete screenQuatersToShowNext[keys[0]];
            if (layoutMode !== 3) columnsCount = 2;
            delayedShowAssist(nextQuater.dx + (assistPadding / 2), nextQuater.dy + (assistPadding / 2), nextQuater.height - assistPadding, nextQuater.width - assistPadding);
            if (lastSelectedClient) lastActiveClient = lastSelectedClient;
            return true;
        } else {
            /// no other quaters to show assist — we can reset the variables
            finishSnap();
            return false;
        }
    }

    function switchAssistLayout() {
        if (!activated) return;
        const halfScreenWidth = currentScreenWidth / 2, halfScreenHeight = currentScreenHeight / 2;

        if (layoutMode == 0) {
            /// horizontal halve
            if (isEqual(mainWindow.height, currentScreenHeight)) {
                /// reduce to quater
                mainWindow.height /= 2;
                if (mainWindow.y !== minDy) mainWindow.y = minDy;
                screenQuatersToShowNext[0] = {dx: mainWindow.x, dy: minDy + halfScreenHeight, height: mainWindow.height, width: mainWindow.width};
            } else if (isEqual(mainWindow.height, halfScreenHeight)) {
                if (isEqual(mainWindow.y, minDy)) {
                    /// already shown in top quater, move to the bottom quater
                    mainWindow.y = minDy + halfScreenHeight;
                    screenQuatersToShowNext[0] = {dx: mainWindow.x, dy: minDy, height: mainWindow.height, width: mainWindow.width};
                } else {
                    /// return to initial position
                    mainWindow.height *= 2;
                    if (mainWindow.y !== minDy) mainWindow.y = minDy;
                    delete screenQuatersToShowNext[0];
                }
            }
        } else if (layoutMode == 2) {
            /// vertical halve
            if (isEqual(mainWindow.width, currentScreenWidth)) {
                /// reduce to quater
                mainWindow.width /= 2;
                columnsCount = 2;
                if (mainWindow.x !== minDx) mainWindow.x = minDx;
                screenQuatersToShowNext[0] = {dx: minDy + halfScreenWidth, dy: mainWindow.y, height: mainWindow.height, width: mainWindow.width};
            } else if (isEqual(mainWindow.width, halfScreenWidth)) {
                if (isEqual(mainWindow.x, minDx)) {
                    /// already shown in left quater, move to the right quater
                    mainWindow.x = minDx + halfScreenWidth;
                    screenQuatersToShowNext[0] = {dx: minDy, dy: mainWindow.y, height: mainWindow.height, width: mainWindow.width};
                } else {
                    /// return to initial position
                    mainWindow.width *= 2;
                    columnsCount = 3;
                    if (mainWindow.x !== minDx) mainWindow.x = minDx;
                    delete screenQuatersToShowNext[0];
                }
            }
        } else if (layoutMode == 1) {
            /// quater
            if (isEqual(mainWindow.height, halfScreenHeight) && isEqual(mainWindow.width, halfScreenWidth)) {
                /// store quater's position - to return to in the end of cycle
                storedQuaterPosition.dx = mainWindow.x; storedQuaterPosition.dy = mainWindow.y;
                storedFirstQuaterToShow = screenQuatersToShowNext[0];

                /// make horizontal halve
                mainWindow.height  = currentScreenHeight;
                if (mainWindow.y !== minDy) mainWindow.y = minDy;
                columnsCount = 2;
                if (isEqual(lastActiveClient.x, minDx)) {
                    /// show on the right
                    mainWindow.x =  minDx + halfScreenWidth;
                    filteredQuaters = [1, 3];

                    /// special handling to show assist again for newly appeared free quater
                    if (isEqual(lastActiveClient.y, minDy + halfScreenHeight))
                        screenQuatersToShowNext[0] = {dx: minDx, dy: minDy, height: halfScreenHeight, width: halfScreenWidth};
                } else {
                    /// show on the left
                    mainWindow.x =  minDx;
                    filteredQuaters = [0, 2];
                }
            } else if (isEqual(mainWindow.height, currentScreenHeight)) {
                /// make vertical halve
                mainWindow.height  = halfScreenHeight;
                mainWindow.width = currentScreenWidth;
                if (mainWindow.x !== minDx) mainWindow.x = minDx;
                columnsCount = 3;
                if (isEqual(lastActiveClient.y, minDy)) {
                    /// show in bottom
                    mainWindow.y = minDy + halfScreenHeight;
                    filteredQuaters = [2, 3];

                    /// special handling to show assist again for newly appeared free quater
                    if (isEqual(lastActiveClient.x, minDx + halfScreenWidth))
                        screenQuatersToShowNext[0] = {dx: minDx, dy: minDy, height: halfScreenHeight, width: halfScreenWidth};
                    else if (isEqual(lastActiveClient.x, minDx))
                        screenQuatersToShowNext[0] = {dx: minDx + halfScreenWidth, dy: minDy, height: halfScreenHeight, width: halfScreenWidth};
                } else {
                    /// show on top
                    mainWindow.y = minDy;
                    filteredQuaters = [0, 1];
                }
            } else {
                /// return to initial position
                mainWindow.width /= 2;
                mainWindow.x = storedQuaterPosition.dx; mainWindow.y = storedQuaterPosition.dy;
                columnsCount = 2;
                filteredQuaters = [];
                screenQuatersToShowNext[0] = storedFirstQuaterToShow;
            }
        } else if (layoutMode == 3) {
            /// three-in-a-row layout

            const thirdOfScreenWidth = currentScreenWidth / 3;

            if (lastActiveClient.x == minDx + thirdOfScreenWidth) {
                /// snapped window in the center
                if (isEqual(mainWindow.x, minDx)) {
                    /// move third to right
                    mainWindow.x = minDx + (thirdOfScreenWidth * 2);
                    filteredQuaters = [2];
                    screenQuatersToShowNext[0] = {dx: minDx, dy: minDy, height: currentScreenHeight, width: thirdOfScreenWidth};
                } else {
                    /// move third to left
                    mainWindow.x = minDx;
                    filteredQuaters = [];
                    delete screenQuatersToShowNext[0];
                }
            } else {
                /// snapped window on the side
                if (isEqual(mainWindow.width, thirdOfScreenWidth)) {
                    /// expand to take two thirds
                    storedQuaterPosition.dx = mainWindow.x;
                    mainWindow.width = thirdOfScreenWidth * 2;
                    columnsCount = 2;
                    filteredQuaters = isEqual(mainWindow.x, minDx) ? [1] : [2];

                } else if (isEqual(mainWindow.height, currentScreenHeight / 2)) {
                    /// return to initial position
                    mainWindow.width = thirdOfScreenWidth;
                    mainWindow.height = currentScreenHeight;
                    mainWindow.x = storedQuaterPosition.dx;
                    columnsCount = 1;
                    filteredQuaters = [];
                   delete screenQuatersToShowNext[0];
                }
                  else if (isEqual(mainWindow.width, thirdOfScreenWidth * 2)) {
                    /// show vertically
                    mainWindow.height = currentScreenHeight / 2;
                    filteredQuaters = [1, 2];
                    screenQuatersToShowNext[0] = {dx: mainWindow.x, dy: minDy + (currentScreenHeight / 2), height: currentScreenHeight / 2, width: mainWindow.width};
                  }
            }
        }
    }


    /// keyboard navigation
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
