/// for keyboard navigation
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
