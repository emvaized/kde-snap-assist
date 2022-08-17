function selectClient(client){
    client.setMaximize(false, false);
    client.frameGeometry = Qt.rect(
        mainWindow.x - (assistPadding / 2),
        mainWindow.y - (assistPadding / 2),
        mainWindow.width + assistPadding,
        mainWindow.height + assistPadding
    );

    workspace.activeClient = client;

    if (trackSnappedWindows) {
        removeWindowFromTrack(client.windowId); /// remove from track if was previously snapped
        snappedWindows.push(client.windowId);
    }

    AssistManager.checkToShowNextQuaterAssist(client);
}

/// listeners
function addListenersToClient(client) {
    client.frameGeometryChanged.connect(function() {
        if (!client.move && !client.resize && activated == false && preventFromShowing == false) {
            if (delayBeforeShowingAssist == 0) {
                onWindowResize(client);
            } else {
                timer.setTimeout(function(){
                    onWindowResize(client);
                }, delayBeforeShowingAssist);
            }
        }
    });

    client.clientStartUserMovedResized.connect(function(cl){
        if (trackSnappedWindows && !client.resize) removeWindowFromTrack(cl.windowId);
    });

    client.windowClosed.connect(function(window){
        handleWindowClose(client);
    });
}

function onWindowResize(window) {
    if (activated) AssistManager.hideAssist();
    AssistManager.finishSnap(false); /// make sure we cleared all variables

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
            AssistManager.delayedShowAssist(minDx + window.width, window.y, undefined, undefined, window);
        } else if (isEqual(dx, minDx + halfScreenWidth)) {
            /// show on left half
            AssistManager.delayedShowAssist(minDx, minDy, undefined, undefined, window);
        }
        columnsCount = 2;
        layoutMode = 0;

    /// top/bottom halves
    } else if (isEqual(width, currentScreenWidth) && isEqual(height, halfScreenHeight) && isEqual(dx, minDx)) {
        if (isEqual(dy, minDy)) {
            /// show in bottom half
            AssistManager.delayedShowAssist(minDx, minDy + halfScreenHeight, halfScreenHeight, currentScreenWidth);
        } else if (isEqual(dy, minDy + halfScreenHeight)) {
            /// show in top half
            AssistManager.delayedShowAssist(minDx, minDy, halfScreenHeight, currentScreenWidth);
        }
        columnsCount = 3;
        layoutMode = 2;
    }

    /// quater tiling
    else if (isEqual(width, halfScreenWidth) && isEqual(height, halfScreenHeight)) {
        /// define current screen quaters
            quatersToShowNext = {
            0: { dx: minDx, dy:  minDy, height: halfScreenHeight, width: halfScreenWidth, },
            1: { dx: minDx + halfScreenWidth, dy:  minDy, height: halfScreenHeight, width: halfScreenWidth, },
            2: { dx: minDx, dy: minDy + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
            3: { dx: minDx + halfScreenWidth, dy:  minDy + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
        };

        /// detect which quater snapped window takes
        let currentQuater = -1;
        let l = Object.keys(quatersToShowNext).length;

        for (let i = 0; i < l; i++) {
            const quater = quatersToShowNext[i];
            if (isEqual(dx, quater.dx) && isEqual(dy, quater.dy)) {
                currentQuater = i;
                delete quatersToShowNext[i];
                break;
            }
        }

        /// show snap assist in next quater
        if (currentQuater == -1) return;
        AssistManager.checkToShowNextQuaterAssist(window);
        layoutMode = 1;
        columnsCount = 2;
    }

    /// 3-in-row tiling
    else if (isEqual(height, currentScreenHeight)) {
        const thirdOfScreenWidth = currentScreenWidth / 3;
        if (isEqual(width, thirdOfScreenWidth)) {
            /// define current screen thirds
            quatersToShowNext = {
                0: { dx: minDx, dy:  minDy, height: currentScreenHeight, width: thirdOfScreenWidth, },
                1: { dx: minDx + thirdOfScreenWidth, dy:  minDy, height: currentScreenHeight, width: thirdOfScreenWidth, },
                2: { dx: minDx + (thirdOfScreenWidth * 2), dy: minDy, height: currentScreenHeight, width: thirdOfScreenWidth, },
            };

            /// detect which quater snapped window takes
            let currentQuater = -1;
            let l = Object.keys(quatersToShowNext).length;

            for (let i = 0; i < l; i++) {
                const quater = quatersToShowNext[i];
                if (isEqual(dx, quater.dx) && isEqual(dy, quater.dy)) {
                    currentQuater = i;
                    delete quatersToShowNext[i];
                    break;
                }
            }

            /// show snap assist in next quater
            if (currentQuater == -1) return;
            AssistManager.checkToShowNextQuaterAssist(window);
            layoutMode = 3;
            columnsCount = 1;
        }
    }
}

function handleWindowFocus(window) {
    if (ignoreFocusChange) return;
    if (activated) AssistManager.hideAssist(false);

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
                    if (w && !w.minimized) workspace.activeClient = w;
                }
            }

            workspace.activeClient = window;
            timer.setTimeout(function(){
                ignoreFocusChange = false;
            }, 100);
        }
    }
}

function handleWindowClose(window){
    if (sortByLastActive) delete activationTime[window.windowId];

        if (trackSnappedWindows) {
        /// remove window if it was snapped
        removeWindowFromTrack(window.windowId, function(group){
            /// callback when snapped window was closed.
            if (fillOnSnappedClose) fillClosedWindow(window, group);
        });
    }
}


/// for snap groups
function applyActionToAssosiatedSnapGroup(client, callback){
    if (!client || !client.windowId) return;

    const i = snappedWindowGroups.findIndex((group) => group.windows.includes(client.windowId));
    if (i > -1) {
        const windows = snappedWindowGroups[i].windows;
        windows.forEach(windowId => callback(workspace.getClient(windowId)));
    }
}

function removeWindowFromTrack(windowId, callback){
    /// Removes provided windowId from tracking of snapped windows
    if (!windowId) return;

    let i2 = -1;
    const i = snappedWindowGroups.findIndex(function(group) {
        i2 = group.windows.indexOf(windowId);
        return i2 > -1;
    });

    if (i > -1) {
        snappedWindowGroups[i].windows.splice(i2, 1);
        if (callback) callback(snappedWindowGroups[i]);
        if (snappedWindowGroups[i].windows.length < 2) snappedWindowGroups.splice(i, 1);
    }
}

function fillClosedWindow(closedWindow, group){
    /// fill the free area when snapped window closed
    const closedWindowGeom = closedWindow.frameGeometry;
    const remainingWindows = group.windows;
    for(let i = 0, l = remainingWindows.length; i < l; i++){
        const window = workspace.getClient(remainingWindows[i]);
        if (!window) continue;
        if (window.windowId == closedWindow.windowId) continue;
        const windowGeom = window.frameGeometry;
        if (!windowGeom) continue;

        if (windowGeom.x == closedWindowGeom.x && windowGeom.width == closedWindowGeom.width){
            AssistManager.preventAssistFromShowing();
            windowGeom.height += closedWindowGeom.height;
            if(windowGeom.y > closedWindowGeom.y) windowGeom.y -= closedWindowGeom.height;
            break;
        } else if(windowGeom.y == closedWindowGeom.y && windowGeom.height == closedWindowGeom.height) {
            AssistManager.preventAssistFromShowing();
            windowGeom.width += closedWindowGeom.width;
            if (windowGeom.x > closedWindowGeom.x) windowGeom.x -= closedWindowGeom.width;
            break;
        }
    }
}

/// utility functions
function isEqual(a, b) {
    /// for compatibility with scripts like Window Gap
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
