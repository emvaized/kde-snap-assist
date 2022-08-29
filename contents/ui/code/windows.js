function selectClient(client){
    client.setMaximize(false, false);
    client.shade = false;

    if (rememberWindowSizes)
        windowSizesBeforeSnap[client.internalId] = { height: client.height, width: client.width };

    client.frameGeometry = Qt.rect(
        mainWindow.x - (assistPadding / 2),
        mainWindow.y - (assistPadding / 2),
        mainWindow.width + assistPadding,
        mainWindow.height + assistPadding
    );

    workspace.activeClient = client;

    if (trackSnappedWindows) {
        removeWindowFromTrack(client.internalId); /// remove from track if was previously snapped
        snappedWindows.push(client.internalId);
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
        if (trackSnappedWindows && !client.resize)
            removeWindowFromTrack(cl.internalId, function(group){
                if (fillOnSnappedMove) fillClosedWindow(cl, group);
            });

        if (rememberWindowSizes){
            const storedSize = windowSizesBeforeSnap[cl.internalId];
            if (storedSize) {
                cl.frameGeometry.height = windowSizesBeforeSnap[cl.internalId].height ?? cl.height;
                cl.frameGeometry.width = windowSizesBeforeSnap[cl.internalId].width ?? cl.width;
                delete windowSizesBeforeSnap[cl.internalId];
            }
        }
    });

    client.windowClosed.connect(function(window){
        handleWindowClose(client);
    });

    client.desktopChanged.connect(function(){
        if (trackSnappedWindows && !client.resize) removeWindowFromTrack(client.internalId);
    });

    client.clientMinimized.connect(function(c){
            if (!trackSnappedWindows || !minimizeSnappedTogether) return;
            WindowManager.applyActionToAssosiatedSnapGroup(client, function(cl){ if (cl) cl.minimized = true; });
    });

    client.clientUnminimized.connect(function(c){
            if (!trackSnappedWindows || !minimizeSnappedTogether) return;
            WindowManager.applyActionToAssosiatedSnapGroup(client, function(cl) {
                if (cl) {
                    cl.minimized = false;
                    if (trackActiveWindows) {
                        const d = new Date();
                        activationTime[cl.internalId] = d.getTime();
                    }
                }
            });
    });
}

function onWindowResize(window) {
    if (activated) return;
    AssistManager.finishSnap(false); /// make sure we cleared all variables

    /// don't show assist if window could be fit in the group behind
    if (fitWindowInGroupBehind && windowFitsInSnapGroup(window)) return;

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
        filteredClients.push(window);

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
        filteredClients.push(window);
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

    /// if only one window available, show it in center and bigger
    if (clients && clients.length == 1) {
        columnsCount = 1;
        cardWidth *= 1.2;
        cardHeight *= 1.2;
    }
}

function handleWindowFocus(window) {
    if (ignoreFocusChange) return;
    if (activated) AssistManager.hideAssist(false);
    if (!window || window.specialWindow) return;

    /// Store timestamp of last window activation
    if (trackActiveWindows) {
        const d = new Date();
        activationTime[window.internalId] = d.getTime();
    }

    /// Raise all snapped windows together
    if (trackSnappedWindows && raiseSnappedTogether && !activated) {
        const i = snappedWindowGroups.findIndex((group) => group.windows.includes(window.internalId));
        if (i > -1) {
            ignoreFocusChange = true;
            const windows = snappedWindowGroups[i].windows;
            const l = windows.length;
            if (l < 2) return;

            for(let i = 0; i < l; i++) {
                if (windows[i] !== window.internalId) {
                    const w = getClientFromId(windows[i]);
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
    if (!window || window.specialWindow) return;
    if (trackActiveWindows) delete activationTime[window.internalId];
    if (rememberWindowSizes) delete windowSizesBeforeSnap[window.internalId];

    if (trackSnappedWindows) {
        /// remove window if it was snapped
        removeWindowFromTrack(window.internalId, function(group){
            /// callback when snapped window was closed.
            if (fillOnSnappedClose) fillClosedWindow(window, group);
        });
    }
}


/// for snap groups
function applyActionToAssosiatedSnapGroup(client, callback){
    if (!client || !client.internalId) return;

    const i = snappedWindowGroups.findIndex((group) => group.windows.includes(client.internalId));
    if (i > -1) {
        const windows = snappedWindowGroups[i].windows;
        windows.forEach(windowId => callback(getClientFromId(windowId)));
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
        if (snappedWindowGroups[i].windows.length < 1) snappedWindowGroups.splice(i, 1);
    }
}

function fillClosedWindow(closedWindow, group){
    /// fill the free area when snapped window closed or moved
    const closedWindowGeom = closedWindow.frameGeometry;
    const remainingWindows = group.windows;
    for(let i = 0, l = remainingWindows.length; i < l; i++){
        const window = getClientFromId(remainingWindows[i]);
        if (!window) continue;
        if (window.internalId == closedWindow.internalId) continue;
        const windowGeom = window.frameGeometry;
        if (!windowGeom) continue;

        if (windowGeom.x == closedWindowGeom.x && windowGeom.width == closedWindowGeom.width){
            /// expand vertically
            AssistManager.preventAssistFromShowing();
            let newHeight = windowGeom.height + closedWindowGeom.height;
            if (newHeight > currentScreenHeight) newHeight = currentScreenHeight;
            window.frameGeometry = Qt.rect(windowGeom.x,
                                           windowGeom.y - (windowGeom.y > closedWindowGeom.y ? closedWindowGeom.height : 0),
                                           windowGeom.width, newHeight);
            break;
        } else if(windowGeom.y == closedWindowGeom.y && windowGeom.height == closedWindowGeom.height) {
            /// expand horizontally
            AssistManager.preventAssistFromShowing();
            let newWidth = windowGeom.width + closedWindowGeom.width;
            if (newWidth > currentScreenWidth) newWidth = currentScreenWidth;
            window.frameGeometry = Qt.rect(
                windowGeom.x - (windowGeom.x > closedWindowGeom.x ? closedWindowGeom.width : 0),
                windowGeom.y, newWidth, windowGeom.height);
            break;
        }
    }
}

function windowFitsInSnapGroup(client){
    /// determines if newly snapped window could be fit in group behind it
    /// requires track activation time and raise snapped windows together

    /// find last active client
    let lastActiveWindowId = -1, lastActiveTime = -1;
    const activeClientId = workspace.activeClient ? workspace.activeClient.internalId : null;
    Object.keys(activationTime).forEach(function(key) {
        if(activationTime[key] > lastActiveTime && key != client.internalId && key != activeClientId) {
            const c = getClientFromId(key);
            if (c && !c.minimized && c.screen == workspace.activeScreen && c.desktop == workspace.currentDesktop) {
                lastActiveWindowId = c.internalId;
                lastActiveTime = activationTime[key];
            }
        }
    });
    if (lastActiveWindowId < 0) return false;

    /// find if it belongs to snap group
    const indexOfGroup = snappedWindowGroups.findIndex((group) => group.windows.includes(lastActiveWindowId));
    if (indexOfGroup < 0) return false;

    /// check rest of windows in that group
    const snappedWindows = snappedWindowGroups[indexOfGroup].windows;

    for (let i = 0, l = snappedWindows.length; i < l; i++) {
        const w = getClientFromId(snappedWindows[i]);
        if (!w) continue;

        if (w.y == client.y && w.height == client.height && w.width > client.width) {
            /// reduce window width to fit new window in layout
            snappedWindowGroups[indexOfGroup].windows.push(client.internalId);
            AssistManager.preventAssistFromShowing();
            const newWidth = w.frameGeometry.width - client.width;
            w.frameGeometry = Qt.rect(w.frameGeometry.x + (w.x == client.x ? client.width : 0), w.frameGeometry.y, newWidth, w.frameGeometry.height);
            return true;

        } else if (w.x == client.x && w.width == client.width && w.height > client.height) {
            /// reduce window height to fit new window in layout
            snappedWindowGroups[indexOfGroup].windows.push(client.internalId);
            AssistManager.preventAssistFromShowing();
            const newHeight = w.frameGeometry.height - client.height;
            w.frameGeometry = Qt.rect(w.frameGeometry.x, w.frameGeometry.y + (w.y == client.y ? client.height : 0), w.frameGeometry.width, newHeight);
            return true;

        } else if (w.x == client.x && w.y == client.y && w.height == client.height && w.width == client.width) {
            /// replace window in group with newly snapped window
            snappedWindowGroups[indexOfGroup].windows.splice(i, 1);
            snappedWindowGroups[indexOfGroup].windows.push(client.internalId);
            return true;
        }
    }

    return false;
}


/// utility functions
function isEqual(a, b) {
    /// for compatibility with scripts like Window Gap
    return a - b <= snapDetectPrecision && a - b >= -snapDetectPrecision;
}

function getClientFromId(windowId){
    //return workspace.getClient(windowId);
    /// Works on Wayland
    return Object.values(workspace.clients).find((el) => el.internalId == windowId);
}

function shouldShowWindow(client) {
    if (filteredClients.includes(client)) return false;
    if (client.active || client.specialWindow) return false;
    if (!showMinimizedWindows && client.minimized) return false;
    if (!showOtherScreensWindows && client.screen !== workspace.activeScreen) return false;
    if (!showOtherDesktopsWindows && client.desktop !== workspace.currentDesktop) return false;
    if (!showSnappedWindows && snappedWindowGroups.findIndex(group => group.windows.includes(client.internalId) && group.windows.length > 1) > -1) return false;
    if (client.activities.length > 0 && !client.activities.includes(workspace.currentActivity)) return false;
    return true;
}

function sortClientsByLastActive() {
    clients = clients.sort(function(a, b) {
        const windowIdA = a.internalId, windowIdB = b.internalId;
        if (activationTime[windowIdA] && !activationTime[windowIdB]) return 1;
        if (!activationTime[windowIdA] && activationTime[windowIdB]) return -1;
        return activationTime[windowIdA] - activationTime[windowIdB];
    });
}
