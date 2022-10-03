/// assist
function delayedShowAssist(dx, dy, height, width, window){
    allClients = Object.values(workspace.clients);
    clients = allClients.filter(c => WindowManager.shouldShowWindow(c));
    if (clients.length == 0) return;

    cardWidth = currentScreenWidth / 5;
    cardHeight = cardWidth / 1.68;
    lastActiveClient = workspace.activeClient;

    timer.setTimeout(function(){
        const w = window ?? workspace.activeClient;
        if (w && w.internalId) snappedWindows.push(w.internalId);
        main.requestActivate();
        keyboardHandler.forceActiveFocus();
        showAssist(dx, dy, height ?? currentScreenHeight, width ?? currentScreenWidth - window.width);
    }, 3);

    if (sortByLastActive) WindowManager.sortClientsByLastActive();
    if (immersiveMode && visibleWindowPreviews.length == 0) visibleWindowPreviews = clients;
    if (descendingOrder) clients = clients.reverse();

    /// find current desktop background
    if (showDesktopBackground) {
        const indexOfDesktopWindow = allClients.findIndex((c) => c.desktopWindow && c.screen === workspace.activeScreen);
        if (indexOfDesktopWindow < 0) return;
        desktopWindowId = allClients[indexOfDesktopWindow].internalId;
    }
}

function showAssist(dx, dy, height, width) {
    activated = true;
    showRegularGridPreviews = true;
    focusedIndex = 0;
    main.showNormal();

    if (immersiveMode) {
        /// need separation between the window and main view
        main.x = 0;
        main.y = 0;
        main.width = currentScreenWidth;
        main.height = currentScreenHeight;

        mainWindow.width = width - assistPadding;
        mainWindow.height = height - assistPadding;
        mainWindow.x = dx + (assistPadding / 2);
        mainWindow.y = dy + (assistPadding / 2);
    } else {
        main.width = width;
        main.height = height;
        main.x = dx;
        main.y = dy;

        mainWindow.width = width;
        mainWindow.height = height;
        mainWindow.x = 0;
        mainWindow.y = 0;
    }

    fadeInAnimation.restart();
    scrollView.ScrollBar.vertical.position = 0;
    transitionDurationOnAssistMove = transitionDuration;

    if (immersiveMode && snappedWindows.length <= 1) animateWindowPreviewsOnInit();
}


function preventAssistFromShowing(delay, callback){
    preventFromShowing = true;
    timer.setTimeout(function(){
        preventFromShowing = false;
        if (callback) callback();
    }, delay ?? 300);
}

function hideAssist(shouldFocusLastClient) {
    if (shouldFocusLastClient && immersiveMode) {
        /// when assist was called without selecting any item
        animateWindowPreviewsOnCancel(function(){actuallyHideAssist(shouldFocusLastClient)});
    } else {
        actuallyHideAssist();
    }
}

function actuallyHideAssist(shouldFocusLastClient){
    activated = false;
    transitionDurationOnAssistMove = 0;
    main.x = mainWindow.width * 2;
    main.y = mainWindow.height * 2;
    main.width = 0;
    main.height = 0;

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
    visibleWindowPreviews = [];
    quatersToShowNext = {};
    lastActiveClient = null;
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
        delayedShowAssist(nextQuater.dx, nextQuater.dy, nextQuater.height, nextQuater.width);
        if (lastSelectedClient) lastActiveClient = lastSelectedClient;
        return true;
    } else {
        /// no other quaters to show assist — we can reset the variables
        preventAssistFromShowing();
        hideAssist(false);
        finishSnap(true);
        return false;
    }
}

function switchAssistLayout() {
    if (!activated) return;
    const halfScreenWidth = currentScreenWidth / 2, halfScreenHeight = currentScreenHeight / 2;
    const assist = immersiveMode ? mainWindow : main;

    if (layoutMode == 0) {
        /// horizontal halve
        if (WindowManager.isEqual(assist.height + assistPadding, currentScreenHeight)) {
            /// reduce to quater
            assist.height /= 2;
            if (assist.y !== minDy + (assistPadding / 2)) assist.y = minDy + (assistPadding / 2);
            quatersToShowNext[0] = {dx: assist.x, dy: minDy + halfScreenHeight + (assistPadding / 2), height: halfScreenHeight, width: assist.width};
        } else if (WindowManager.isEqual(assist.height + assistPadding, halfScreenHeight)) {
            if (WindowManager.isEqual(assist.y - (assistPadding / 2), minDy)) {
                /// already shown in top quater, move to the bottom quater
                assist.y = minDy + halfScreenHeight;
                quatersToShowNext[0] = {dx: assist.x, dy: minDy + (assistPadding / 2), height: assist.height, width: assist.width};
            } else {
                /// return to initial position
                assist.height *= 2;
                if (assist.y !== minDy + (assistPadding / 2)) assist.y = minDy + (assistPadding / 2);
                delete quatersToShowNext[0];
            }
        }
    } else if (layoutMode == 2) {
        /// vertical halve
        if (WindowManager.isEqual(assist.width + assistPadding, currentScreenWidth)) {
            /// reduce to quater
            assist.width /= 2;
            columnsCount = 2;
            if (assist.x !== minDx + (assistPadding / 2)) assist.x = minDx + (assistPadding / 2);
            quatersToShowNext[0] = {dx: minDy + halfScreenWidth, dy: assist.y, height: assist.height, width: assist.width};
        } else if (WindowManager.isEqual(assist.width + assistPadding, halfScreenWidth)) {
            if (WindowManager.isEqual(assist.x - (assistPadding / 2), minDx)) {
                /// already shown in left quater, move to the right quater
                assist.x = minDx + halfScreenWidth ;
                quatersToShowNext[0] = {dx: minDy + (assistPadding / 2), dy: assist.y + (assistPadding / 2), height: assist.height - assistPadding, width: assist.width - assistPadding};
            } else {
                /// return to initial position
                assist.width *= 2;
                columnsCount = 3;
                if (assist.x !== minDx + (assistPadding / 2)) assist.x = minDx + (assistPadding / 2);
                delete quatersToShowNext[0];
            }
        }
    } else if (layoutMode == 1) {
        /// quater
        if (WindowManager.isEqual(assist.height + assistPadding, halfScreenHeight) && WindowManager.isEqual(assist.width + assistPadding, halfScreenWidth)) {
            /// store quater's position - to return to in the end of cycle
            storedQuaterPosition.dx = assist.x; storedQuaterPosition.dy = assist.y;
            storedFirstQuaterToShow = quatersToShowNext[0];

            /// make horizontal halve
            assist.height  = currentScreenHeight - assistPadding;
            if (assist.y !== minDy + (assistPadding / 2)) assist.y = minDy + (assistPadding / 2);
            columnsCount = 2;
            if (WindowManager.isEqual(lastActiveClient.x - (assistPadding / 2), minDx)) {
                /// show on the right
                assist.x =  minDx + halfScreenWidth + (assistPadding / 2);
                filteredQuaters = [1, 3];

                /// special handling to show assist again for newly appeared free quater
                if (WindowManager.isEqual(lastActiveClient.y, minDy + halfScreenHeight))
                    quatersToShowNext[0] = {dx: minDx + (assistPadding / 2), dy: minDy + (assistPadding / 2), height: halfScreenHeight - assistPadding, width: halfScreenWidth - assistPadding};
            } else {
                /// show on the left
                assist.x =  minDx + (assistPadding / 2);
                filteredQuaters = [0, 2];
            }
        } else if (WindowManager.isEqual(assist.height + assistPadding, currentScreenHeight)) {
            /// make vertical halve
            assist.height  = halfScreenHeight - assistPadding;
            assist.width = currentScreenWidth - assistPadding;
            if (assist.x !== minDx + (assistPadding / 2)) assist.x = minDx + (assistPadding / 2);
            columnsCount = 3;
            if (WindowManager.isEqual(lastActiveClient.y - (assistPadding / 2), minDy)) {
                /// show in bottom
                assist.y = minDy + halfScreenHeight + (assistPadding / 2);
                filteredQuaters = [2, 3];

                /// special handling to show assist again for newly appeared free quater
                if (WindowManager.isEqual(lastActiveClient.x, minDx + halfScreenWidth))
                    quatersToShowNext[0] = {dx: minDx + (assistPadding / 2), dy: minDy + (assistPadding / 2), height: halfScreenHeight - assistPadding, width: halfScreenWidth - assistPadding};
                else if (WindowManager.isEqual(lastActiveClient.x, minDx))
                    quatersToShowNext[0] = {dx: minDx + halfScreenWidth + (assistPadding / 2), dy: minDy + (assistPadding / 2), height: halfScreenHeight - assistPadding, width: halfScreenWidth - assistPadding};
            } else {
                /// show on top
                assist.y = minDy;
                filteredQuaters = [0, 1];
            }
        } else {
            /// return to initial position
            assist.width /= 2;
            assist.x = storedQuaterPosition.dx; assist.y = storedQuaterPosition.dy;
            columnsCount = 2;
            filteredQuaters = [];
            quatersToShowNext[0] = storedFirstQuaterToShow;
        }
    } else if (layoutMode == 3) {
        /// three-in-a-row layout
        const thirdOfScreenWidth = currentScreenWidth / 3;

        if (lastActiveClient.x == minDx + thirdOfScreenWidth) {
            /// snapped window in the center
            if (WindowManager.isEqual(assist.x - (assistPadding / 2), minDx)) {
                /// move third to right
                assist.x = minDx + (thirdOfScreenWidth * 2) + (assistPadding / 2);
                filteredQuaters = [2];
                quatersToShowNext[0] = {dx: minDx, dy: minDy, height: currentScreenHeight, width: thirdOfScreenWidth};
            } else {
                /// move third to left
                assist.x = minDx + (assistPadding / 2);
                filteredQuaters = [];
                delete quatersToShowNext[0];
            }
        } else {
            /// snapped window on the side
            if (WindowManager.isEqual(assist.width + assistPadding, thirdOfScreenWidth)) {
                /// expand to take two thirds
                storedQuaterPosition.dx = assist.x;
                assist.width = thirdOfScreenWidth * 2 - assistPadding;
                columnsCount = 2;
                filteredQuaters = WindowManager.isEqual(assist.x - (assistPadding / 2), minDx) ? [1] : [2];

            } else if (WindowManager.isEqual(assist.height + assistPadding, currentScreenHeight / 2)) {
                /// return to initial position
                assist.width = thirdOfScreenWidth - assistPadding;
                assist.height = currentScreenHeight - assistPadding;
                assist.x = storedQuaterPosition.dx;
                columnsCount = 1;
                filteredQuaters = [];
                delete quatersToShowNext[0];

            } else if (WindowManager.isEqual(assist.width + assistPadding, thirdOfScreenWidth * 2)) {
                /// show vertically
                assist.height = currentScreenHeight / 2 - assistPadding;
                filteredQuaters = [1, 2];
                quatersToShowNext[0] = {dx: assist.x, dy: minDy + (currentScreenHeight / 2), height: currentScreenHeight / 2, width: assist.width};
            }
        }
    }
}




function animateWindowPreviewsOnInit(){
    let item, thumbnail, thumbnailGlobalCoords, indexOfThumbnail, processedClient;

    timer.setTimeout(function(){
        showRegularGridPreviews = false;

        for(let i = 0, l = visibleWindowPreviews.length; i < l; i++){
            processedClient = visibleWindowPreviews[i];
            item = windowPreviewsRepeater.itemAt(i);
            thumbnail = clientsRepeater.itemAt(descendingOrder ? l - 1 - i : i);
            if (!item || !thumbnail) continue;
            thumbnailGlobalCoords = thumbnail.mapToGlobal(0,0);

            item.x = thumbnailGlobalCoords.x + 3;
            item.y = thumbnailGlobalCoords.y + 32;
            item.height = cardHeight - 40;
            item.width = cardWidth - 6;
        }

        timer.setTimeout(function(){
            visibleWindowPreviews = [];
            showRegularGridPreviews = true;
        }, transitionDuration);
    }, 3);
}


function animateWindowPreviewsOnCancel(callback){
    /// show previews of all windows
    visibleWindowPreviews = [...descendingOrder ? clients.reverse() : clients, ...visibleWindowPreviews];

    let item, thumbnail, thumbnailGlobalCoords, indexOfThumbnail;
    timer.setTimeout(function(){
        transitionDuration = 0;
        showRegularGridPreviews = false;

        /// move previews to their positions in the grid
        for(let i = 0, l = visibleWindowPreviews.length; i < l; i++){
            if (snappedWindows.includes(visibleWindowPreviews[i].internalId)) continue;

            item = windowPreviewsRepeater.itemAt(i);
            thumbnail = clientsRepeater.itemAt(descendingOrder ? l - 1 - i : i);
            if (!item || !thumbnail) continue;
            thumbnailGlobalCoords = thumbnail.mapToGlobal(0,0);

            item.x = thumbnailGlobalCoords.x + 3;
            item.y = thumbnailGlobalCoords.y + 32;
            item.height = cardHeight - 40;
            item.width = cardWidth - 6;
        }

        timer.setTimeout(function(){
            /// animate previews to their windows positions
            transitionDuration = transitionDurationOnAssistMove;
            for(let i = 0, l = visibleWindowPreviews.length; i < l; i++){
                item = windowPreviewsRepeater.itemAt(i);
                if (!item) continue;

                item.x = visibleWindowPreviews[i].x;
                item.y = visibleWindowPreviews[i].y;
                item.height = visibleWindowPreviews[i].height;
                item.width = visibleWindowPreviews[i].width;

                timer.setTimeout(function(){
                    /// close assist
                    showRegularGridPreviews = true;
                    if (callback) callback();
                }, transitionDuration);
            }
        }, 3);
    }, 0);
}
