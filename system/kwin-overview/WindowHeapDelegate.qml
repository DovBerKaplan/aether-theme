/*
    SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2022 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2024 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
    Aether: restyled against the stock Plasma 6.8.1 file.
    - the hover/selection border is a thin accent hairline, concentric with the
      tile corners, instead of the stock 6px slab
    - the tile breathes on hover (a 1.5% lift, no layout change)
    - the floating 48px icon and the flat caption chip become one glass pill:
      small icon inside + shortened title ("Page — App" -> "Page")
    - the close button is a small glass circle
    Everything else is stock. Re-applied by `make install-overview`; a Plasma
    update reverts it safely to stock.
*/

import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.kwin.private.effects
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.ksvg as KSvg

ExpoCell {
    id: thumb

    required property KWinComponents.Window window
    required property int index
    required property WindowHeap windowHeap

    readonly property bool selected: windowHeap.selectedIndex === index
    property bool gestureInProgress: effect.gestureInProgress
    // Where the internal contentItem will be parented to
    property Item contentItemParent: this

    // no desktops is a special value which means "All Desktops"
    readonly property bool presentOnCurrentDesktop: !window.desktops.length || window.desktops.indexOf(KWinComponents.Workspace.currentDesktop) !== -1
    readonly property bool initialHidden: window.minimized
    readonly property bool activeHidden: {
        if (window.skipSwitcher) {
            return true;
        } else if (windowHeap.showOnly === "activeClass") {
            if (!KWinComponents.Workspace.activeWindow) {
                return true;
            } else {
                return KWinComponents.Workspace.activeWindow.resourceName !== window.resourceName;
            }
        } else {
            return windowHeap.showOnly.length !== 0
                && windowHeap.showOnly.indexOf(window.internalId) === -1;
        }
    }

    // Show a close button on this thumbnail
    property bool closeButtonVisible: true
    // Show a text label under this thumbnail
    property bool windowTitleVisible: true

    // Same as for window heap
    property bool animationEnabled: false

    //scale up and down the whole thumbnail without affecting layouting
    property real targetScale: 1.0

    property DragManager activeDragHandler: dragHandler

    // Swipe down gesture by touch, in some effects will close the window
    readonly property alias downGestureProgress: touchDragHandler.downGestureProgress
    signal downGestureTriggered()

    property bool isReady: width !== 0 && height !== 0

    function restoreDND(oldGlobalRect: rect) {
        thumbSource.restoreDND(oldGlobalRect);
    }

    // Aether: keep the app name when the title half of "Title — App" is
    // too short to stand on its own ("-: — Konsole" -> "Konsole")
    function shortTitle(caption: string): string {
        if (!caption || caption.length === 0) {
            return "";
        }
        const seps = [" — ", " – ", " - "];
        for (let i = 0; i < seps.length; i++) {
            const idx = caption.indexOf(seps[i]);
            if (idx > 0) {
                const first = caption.substring(0, idx).trim();
                if (first.length >= 3) {
                    return first;
                }
                const second = caption.substring(idx + seps[i].length).trim();
                return second.length > 0 ? second : first;
            }
        }
        return caption;
    }

    layout: windowHeap.layout
    shouldLayout: !thumb.activeHidden
    partialActivationFactor: effect.partialActivationFactor
    naturalX: thumb.window.x - thumb.window.output.geometry.x
    naturalY: thumb.window.y - thumb.window.output.geometry.y
    naturalWidth: thumb.window.width
    naturalHeight: thumb.window.height
    persistentKey: thumb.window.internalId
    bottomMargin: (captionPill.visible ? captionPill.height + Kirigami.Units.smallSpacing : 0) + Kirigami.Units.largeSpacing

    Behavior on x {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on y {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on width {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }
    Behavior on height {
        enabled: thumb.isReady
        NumberAnimation {
            duration: thumb.windowHeap.animationDuration
            easing.type: Easing.InOutCubic
        }
    }

    contentItem: Item {
        id: mainContent
        parent: contentItemParent
        visible: opacity > 0 && (!activeHidden || !initialHidden)
        opacity: (1 - downGestureProgress) * (initialHidden ? partialActivationFactor : 1)
        z: (activeDragHandler.active || returnAnimation.running) ? 1000
            : thumb.window.stackingOrder * (presentOnCurrentDesktop ? 1 : 0.001)

        // Aether: the tile lifts a touch under the cursor
        readonly property real hoverLift: hoverHandler.hovered
            && windowHeap.effectiveOrganized
            && !thumb.activeDragHandler.active
            && !returnAnimation.running ? 1.015 : 1.0
        scale: hoverLift
        Behavior on scale {
            enabled: thumb.isReady
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        KWinComponents.WindowThumbnail {
            id: thumbSource
            wId: thumb.window.internalId
            scale: targetScale
            width: mainContent.width
            height: mainContent.height

            Binding on width {
                value: mainContent.width
                when: !returnAnimation.active
            }
            Binding on height {
                value: mainContent.height
                when: !returnAnimation.active
            }

            Drag.proposedAction: Qt.MoveAction
            Drag.supportedActions: Qt.MoveAction
            Drag.source: thumb.window
            Drag.hotSpot: Qt.point(
                thumb.activeDragHandler.centroid.pressPosition.x,
                thumb.activeDragHandler.centroid.pressPosition.y)
            Drag.keys: ["kwin-window"]

            onXChanged: effect.checkItemDraggedOutOfScreen(thumbSource)
            onYChanged: effect.checkItemDraggedOutOfScreen(thumbSource)

            function saveDND() {
                const oldGlobalRect = mapToItem(null, 0, 0, width, height);
                thumb.windowHeap.saveDND(thumb.window.internalId, oldGlobalRect);
            }
            function restoreDND(oldGlobalRect: rect) {
                const newGlobalRect = mapFromItem(null, oldGlobalRect);
                // We need proper mapping for the heap geometry because they are positioned with
                // translation transformations
                const heapRect = thumb.windowHeap.mapToItem(null, Qt.size(thumb.windowHeap.width, thumb.windowHeap.height));
                // Disable bindings
                returnAnimation.active = true;
                x = newGlobalRect.x;
                y = newGlobalRect.y;
                width = newGlobalRect.width;
                height = newGlobalRect.height;

                returnAnimation.restart();

                // If we dropped on another desktop, don't make the window fly off  the screen
                if ((oldGlobalRect.x < heapRect.x && heapRect.x + heapRect.width < oldGlobalRect.x + oldGlobalRect.width) ||
                    (oldGlobalRect.y < heapRect.y && heapRect.y + heapRect.height < oldGlobalRect.y + oldGlobalRect.height)) {
                    returnAnimation.complete();
                }
            }
            function deleteDND() {
                thumb.windowHeap.deleteDND(thumb.window.internalId);
            }

            // Not using FrameSvg hover element intentionally for stylistic reasons
            // Aether: thin concentric hairline instead of the 6px slab
            Rectangle {
                id: highlightFrame
                readonly property bool lit: !thumb.windowHeap.dragActive
                    && (hoverHandler.hovered || (thumb.selected && Window.window.activeFocusItem))
                    && windowHeap.effectiveOrganized
                anchors.fill: parent
                anchors.margins: -border.width
                border.width: 2
                border.color: Kirigami.Theme.highlightColor
                color: thumb.selected && Window.window.activeFocusItem
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                              Kirigami.Theme.highlightColor.g,
                              Kirigami.Theme.highlightColor.b, 0.08)
                    : "transparent"
                radius: Kirigami.Units.cornerRadius + border.width / 2
                opacity: lit ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Kirigami.Units.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: thumb.activeDragHandler.active ? Qt.ClosedHandCursor : Qt.ArrowCursor
            }
            ParallelAnimation {
                id: returnAnimation
                property bool active: false
                onRunningChanged: active = running
                NumberAnimation {
                    target: thumbSource
                    properties: "x,y"
                    to: 0
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
                NumberAnimation {
                    target: thumbSource
                    property: "width"
                    to: mainContent.width
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
                NumberAnimation {
                    target: thumbSource
                    property: "height"
                    to: mainContent.height
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
                NumberAnimation {
                    target: thumbSource
                    property: "scale"
                    to: 1
                    duration: thumb.windowHeap.animationDuration
                    easing.type: Easing.InOutCubic
                }
            }
        }

        PC3.Label {
            anchors.fill: thumbSource
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: i18nd("kwin", "Drag Down To Close")
            visible: !thumb.activeHidden && touchDragHandler.active
            background: Rectangle {
                anchors.centerIn: parent
                height: parent.contentHeight + Kirigami.Units.smallSpacing
                width: parent.contentWidth + Kirigami.Units.smallSpacing
                color: Kirigami.Theme.backgroundColor
                radius: Kirigami.Units.cornerRadius
            }
        }

        // Aether: one glass pill — small app icon inside + short title
        Item {
            id: captionPill
            readonly property string title: thumb.shortTitle(thumb.window.caption)
            readonly property int paddingH: Kirigami.Units.largeSpacing
            readonly property int pillHeight: Math.round(Kirigami.Units.gridUnit * 1.4)

            width: Math.min(iconItem.width + row.spacing + label.implicitWidth + 2 * paddingH,
                            Math.max(0, thumb.width - Kirigami.Units.largeSpacing))
            height: pillHeight
            scale: Math.min(1.0, mainContent.width / Math.max(0.01, thumb.width))
            opacity: partialActivationFactor
            visible: !thumb.activeHidden
                && !activeDragHandler.active
                && !returnAnimation.running
                && thumb.windowTitleVisible
                && title.length > 0
            anchors.horizontalCenter: thumbSource.horizontalCenter
            anchors.top: thumbSource.bottom
            anchors.topMargin: Kirigami.Units.smallSpacing

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Kirigami.Theme.backgroundColor
                opacity: 0.62
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                      Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.12)
            }
            Row {
                id: row
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    id: iconItem
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.iconSizes.small
                    height: Kirigami.Units.iconSizes.small
                    source: thumb.window.icon
                }
                PC3.Label {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth,
                                    captionPill.width - iconItem.width - row.spacing - 2 * captionPill.paddingH)
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    text: captionPill.title
                    color: Kirigami.Theme.textColor
                    textFormat: Text.PlainText
                }
            }
        }

        HoverHandler {
            id: hoverHandler
            onHoveredChanged: if (hovered !== selected) {
                thumb.windowHeap.resetSelected();
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: {
                KWinComponents.Workspace.activeWindow = thumb.window;
                thumb.windowHeap.activated();
            }
            onPressedChanged: {
                if (pressed) {
                    thumbSource.Drag.active = true;
                } else if (!thumb.activeDragHandler.active) {
                    thumbSource.Drag.active = false;
                }
            }
        }

        component DragManager : DragHandler {
            target: thumbSource
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            // This does not work when moving pointer fast and pressing along the way
            // See also QTBUG-105903, QTBUG-105904
            // enabled: thumb.state !== "active-normal"

            onActiveChanged: {
                thumb.windowHeap.dragActive = active;
                if (active) {
                    thumb.activeDragHandler = this;
                } else {
                    thumbSource.saveDND();
                    returnAnimation.restart();

                    var action = thumbSource.Drag.drop();
                    if (action === Qt.MoveAction) {
                        // This whole component is in the process of being destroyed due to drop onto
                        // another virtual desktop (not another screen).
                        if (typeof thumbSource !== "undefined") {
                            // Except the case when it was dropped on the same desktop which it's already on, so let's return to normal state anyway.
                            thumbSource.deleteDND();
                        }
                        return;
                    }

                    var globalPos = targetScreen.mapToGlobal(centroid.scenePosition);
                    effect.checkItemDroppedOutOfScreen(globalPos, thumbSource);

                    if (typeof thumbSource !== "undefined") {
                        // else, return to normal without reparenting
                        thumbSource.deleteDND();
                    }
                }
            }
        }

        DragManager {
            id: dragHandler
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        }

        DragManager {
            id: touchDragHandler
            acceptedDevices: PointerDevice.TouchScreen
            readonly property double downGestureProgress: {
                if (!active) {
                    return 0.0;
                }

                const startDistance = thumb.windowHeap.Kirigami.ScenePosition.y + thumb.windowHeap.height - centroid.scenePressPosition.y;
                const localPosition = thumb.windowHeap.Kirigami.ScenePosition.y + thumb.windowHeap.height - centroid.scenePosition.y;
                return 1 - Math.min(localPosition/startDistance, 1);
            }

            onActiveChanged: {
                if (!active) {
                    if (downGestureProgress > 0.6) {
                        thumb.downGestureTriggered();
                    }
                }
            }
        }

        Loader {
            id: closeButton
            LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft

            anchors {
                right: thumbSource.right
                top: thumbSource.top
                margins: Kirigami.Units.smallSpacing
            }
            active: thumb.closeButtonVisible && (hoverHandler.hovered || Kirigami.Settings.tabletMode || Kirigami.Settings.hasTransientTouchInput) && thumb.window.closeable && !thumb.activeDragHandler.active && !returnAnimation.running

            // Aether: a small glass circle, not the stock themed button
            sourceComponent: Item {
                width: Math.round(Kirigami.Units.gridUnit * 1.3)
                height: width
                Accessible.name: i18ndc("kwin", "@info:tooltip as in: 'close this window'", "Close window")

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Kirigami.Theme.backgroundColor
                    opacity: closeHover.hovered ? 0.85 : 0.62
                    border.width: 1
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.12)
                    Behavior on opacity {
                        NumberAnimation { duration: Kirigami.Units.shortDuration }
                    }
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.small
                    height: Kirigami.Units.iconSizes.small
                    source: "window-close"
                }
                HoverHandler {
                    id: closeHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: thumb.window.closeWindow()
                }
            }
        }

        Component.onDestruction: {
            if (selected) {
                windowHeap.resetSelected();
            }
        }
    }
}
