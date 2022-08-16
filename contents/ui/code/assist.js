/// assist
function delayedShowAssist(dx, dy, height, width, window){
    clients = Object.values(workspace.clients).filter(c => WindowManager.shouldShowWindow(c));
    if (clients.length == 0) return;

    if (sortByLastActive) WindowManager.sortClientsByLastActive();
    if (descendingOrder) clients = clients.reverse();

    cardWidth = currentScreenWidth / 5;
    cardHeight = cardWidth / 1.68;
    lastActiveClient = workspace.activeClient;

    timer.setTimeout(function(){
        const w = window ?? workspace.activeClient;
        if (w && w.windowId) snappedWindows.push(w.windowId);
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

function preventAssistFromShowing(delay, callback){
    preventFromShowing = true;
    timer.setTimeout(function(){
        preventFromShowing = false;
        if (callback) callback();
    }, delay ?? 300);
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
        finishSnap(true);
    }
}

function finishSnap(success){
    /// gets called when close assist, and no other assists awaiting to show
    if (success == true && trackSnappedWindows && snappedWindows.length > 1) {
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
    quatersToShowNext = {};
}


/// for quater tiling
function checkToShowNextQuaterAssist(lastSelectedClient){
    const keys = Object.keys(quatersToShowNext).filter(quaterIndex => !filteredQuaters.includes(parseInt(quaterIndex)));
    const l = keys.length;

    if (l > 0) {
        /// need to show assist in other quaters
        if (lastSelectedClient) filteredClients.push(lastSelectedClient);
        const nextQuater = quatersToShowNext[keys[0]];
        delete quatersToShowNext[keys[0]];
        if (layoutMode !== 3) columnsCount = 2;
        delayedShowAssist(nextQuater.dx + (assistPadding / 2), nextQuater.dy + (assistPadding / 2), nextQuater.height - assistPadding, nextQuater.width - assistPadding);
        if (lastSelectedClient) lastActiveClient = lastSelectedClient;
        return true;
    } else {
        /// no other quaters to show assist — we can reset the variables
        finishSnap(true);
        return false;
    }
}

function switchAssistLayout() {
    if (!activated) return;
    const halfScreenWidth = currentScreenWidth / 2, halfScreenHeight = currentScreenHeight / 2;

    if (layoutMode == 0) {
        /// horizontal halve
        if (WindowManager.isEqual(mainWindow.height, currentScreenHeight)) {
            /// reduce to quater
            mainWindow.height /= 2;
            if (mainWindow.y !== minDy) mainWindow.y = minDy;
            quatersToShowNext[0] = {dx: mainWindow.x, dy: minDy + halfScreenHeight, height: mainWindow.height, width: mainWindow.width};
        } else if (WindowManager.isEqual(mainWindow.height, halfScreenHeight)) {
            if (WindowManager.isEqual(mainWindow.y, minDy)) {
                /// already shown in top quater, move to the bottom quater
                mainWindow.y = minDy + halfScreenHeight;
                quatersToShowNext[0] = {dx: mainWindow.x, dy: minDy, height: mainWindow.height, width: mainWindow.width};
            } else {
                /// return to initial position
                mainWindow.height *= 2;
                if (mainWindow.y !== minDy) mainWindow.y = minDy;
                delete quatersToShowNext[0];
            }
        }
    } else if (layoutMode == 2) {
        /// vertical halve
        if (WindowManager.isEqual(mainWindow.width, currentScreenWidth)) {
            /// reduce to quater
            mainWindow.width /= 2;
            columnsCount = 2;
            if (mainWindow.x !== minDx) mainWindow.x = minDx;
            quatersToShowNext[0] = {dx: minDy + halfScreenWidth, dy: mainWindow.y, height: mainWindow.height, width: mainWindow.width};
        } else if (WindowManager.isEqual(mainWindow.width, halfScreenWidth)) {
            if (WindowManager.isEqual(mainWindow.x, minDx)) {
                /// already shown in left quater, move to the right quater
                mainWindow.x = minDx + halfScreenWidth;
                quatersToShowNext[0] = {dx: minDy, dy: mainWindow.y, height: mainWindow.height, width: mainWindow.width};
            } else {
                /// return to initial position
                mainWindow.width *= 2;
                columnsCount = 3;
                if (mainWindow.x !== minDx) mainWindow.x = minDx;
                delete quatersToShowNext[0];
            }
        }
    } else if (layoutMode == 1) {
        /// quater
        if (WindowManager.isEqual(mainWindow.height, halfScreenHeight) && WindowManager.isEqual(mainWindow.width, halfScreenWidth)) {
            /// store quater's position - to return to in the end of cycle
            storedQuaterPosition.dx = mainWindow.x; storedQuaterPosition.dy = mainWindow.y;
            storedFirstQuaterToShow = quatersToShowNext[0];

            /// make horizontal halve
            mainWindow.height  = currentScreenHeight;
            if (mainWindow.y !== minDy) mainWindow.y = minDy;
            columnsCount = 2;
            if (WindowManager.isEqual(lastActiveClient.x, minDx)) {
                /// show on the right
                mainWindow.x =  minDx + halfScreenWidth;
                filteredQuaters = [1, 3];

                /// special handling to show assist again for newly appeared free quater
                if (WindowManager.isEqual(lastActiveClient.y, minDy + halfScreenHeight))
                    quatersToShowNext[0] = {dx: minDx, dy: minDy, height: halfScreenHeight, width: halfScreenWidth};
            } else {
                /// show on the left
                mainWindow.x =  minDx;
                filteredQuaters = [0, 2];
            }
        } else if (WindowManager.isEqual(mainWindow.height, currentScreenHeight)) {
            /// make vertical halve
            mainWindow.height  = halfScreenHeight;
            mainWindow.width = currentScreenWidth;
            if (mainWindow.x !== minDx) mainWindow.x = minDx;
            columnsCount = 3;
            if (WindowManager.isEqual(lastActiveClient.y, minDy)) {
                /// show in bottom
                mainWindow.y = minDy + halfScreenHeight;
                filteredQuaters = [2, 3];

                /// special handling to show assist again for newly appeared free quater
                if (WindowManager.isEqual(lastActiveClient.x, minDx + halfScreenWidth))
                    quatersToShowNext[0] = {dx: minDx, dy: minDy, height: halfScreenHeight, width: halfScreenWidth};
                else if (WindowManager.isEqual(lastActiveClient.x, minDx))
                    quatersToShowNext[0] = {dx: minDx + halfScreenWidth, dy: minDy, height: halfScreenHeight, width: halfScreenWidth};
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
            quatersToShowNext[0] = storedFirstQuaterToShow;
        }
    } else if (layoutMode == 3) {
        /// three-in-a-row layout

        const thirdOfScreenWidth = currentScreenWidth / 3;

        if (lastActiveClient.x == minDx + thirdOfScreenWidth) {
            /// snapped window in the center
            if (WindowManager.isEqual(mainWindow.x, minDx)) {
                /// move third to right
                mainWindow.x = minDx + (thirdOfScreenWidth * 2);
                filteredQuaters = [2];
                quatersToShowNext[0] = {dx: minDx, dy: minDy, height: currentScreenHeight, width: thirdOfScreenWidth};
            } else {
                /// move third to left
                mainWindow.x = minDx;
                filteredQuaters = [];
                delete quatersToShowNext[0];
            }
        } else {
            /// snapped window on the side
            if (WindowManager.isEqual(mainWindow.width, thirdOfScreenWidth)) {
                /// expand to take two thirds
                storedQuaterPosition.dx = mainWindow.x;
                mainWindow.width = thirdOfScreenWidth * 2;
                columnsCount = 2;
                filteredQuaters = isEqual(mainWindow.x, minDx) ? [1] : [2];

            } else if (WindowManager.isEqual(mainWindow.height, currentScreenHeight / 2)) {
                /// return to initial position
                mainWindow.width = thirdOfScreenWidth;
                mainWindow.height = currentScreenHeight;
                mainWindow.x = storedQuaterPosition.dx;
                columnsCount = 1;
                filteredQuaters = [];
                delete quatersToShowNext[0];
            }
                else if (WindowManager.isEqual(mainWindow.width, thirdOfScreenWidth * 2)) {
                /// show vertically
                mainWindow.height = currentScreenHeight / 2;
                filteredQuaters = [1, 2];
                quatersToShowNext[0] = {dx: mainWindow.x, dy: minDy + (currentScreenHeight / 2), height: currentScreenHeight / 2, width: mainWindow.width};
                }
        }
    }
}
