/*
    Aether Sink - our own open/close animation.
    Opening is KWin's Scale (the approved look); closing dives the window into
    its taskbar icon, or sinks it through the bottom edge when it has no seat.
    SPDX-License-Identifier: GPL-2.0-or-later
*/

"use strict";

// Same exclusions as KWin's own Scale effect.
const blacklist = {
    // The logout screen has to be animated only by the logout effect.
    "ksmserver ksmserver": [],
    "ksmserver-logout-greeter ksmserver-logout-greeter": [],

    // KDE Plasma splash screen has to be animated only by the login effect.
    "ksplashqml ksplashqml": [],

    "spectacle org.kde.spectacle": ["region-editor"],
};

class AetherSinkEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.cleanupForcedRoles.bind(this));
        effects.windowAdded.connect(this.slotWindowAdded.bind(this));
        effects.windowClosed.connect(this.slotWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.slotWindowDataChanged.bind(this));

        this.loadConfig();
    }

    loadConfig() {
        const defaultDuration = 200;
        const duration = effect.readConfig("Duration", defaultDuration) || defaultDuration;
        this.duration = animationTime(duration);
        this.closeDuration = animationTime(250);
        this.inScale = effect.readConfig("InScale", 0.8);
    }

    static isSinkWindow(window) {
        // Same heuristics as Scale: animate plasmashell's decorated windows only,
        // skip popups, tooltips, the lock screen and unmanaged surfaces.
        if (window.windowClass == "plasmashell plasmashell"
                || window.windowClass == "plasmashell org.kde.plasmashell") {
            return window.hasDecoration;
        }

        const blacklistedTags = blacklist[window.windowClass];
        if (blacklistedTags && (blacklistedTags.length === 0 || blacklistedTags.includes(window.tag))) {
            return false;
        }

        if (window.hasDecoration) {
            return true;
        }

        if (window.popupWindow) {
            return false;
        }

        if (window.lockScreen || window.outline) {
            return false;
        }

        if (!window.managed) {
            return false;
        }

        return window.normalWindow || window.dialog;
    }

    setupForcedRoles(window) {
        // Keep the glass blurred while the window is in flight.
        window.setData(Effect.WindowForceBackgroundContrastRole, true);
        window.setData(Effect.WindowForceBlurRole, true);
    }

    cleanupForcedRoles(window) {
        window.setData(Effect.WindowForceBackgroundContrastRole, null);
        window.setData(Effect.WindowForceBlurRole, null);
    }

    slotWindowAdded(window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (!AetherSinkEffect.isSinkWindow(window)) {
            return;
        }
        if (!window.visible) {
            return;
        }
        if (effect.isGrabbed(window, Effect.WindowAddedGrabRole)) {
            return;
        }
        this.setupForcedRoles(window);
        window.sinkOpenAnimation = animate({
            window: window,
            curve: QEasingCurve.OutCubic,
            duration: this.duration,
            animations: [
                {
                    type: Effect.Scale,
                    from: this.inScale
                },
                {
                    type: Effect.Opacity,
                    from: 0
                }
            ]
        });
    }

    slotWindowClosed(window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (!AetherSinkEffect.isSinkWindow(window)) {
            return;
        }
        if (!window.visible || window.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(window, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (window.sinkOpenAnimation) {
            cancel(window.sinkOpenAnimation);
            delete window.sinkOpenAnimation;
        }
        this.setupForcedRoles(window);

        const windowRect = window.geometry;
        const iconRect = window.iconGeometry;
        let animations;
        if (iconRect && iconRect.width > 0 && iconRect.height > 0) {
            // Dive into the window's seat in the taskbar (squash's geometry).
            animations = [
                {
                    type: Effect.Size,
                    from: {
                        value1: windowRect.width,
                        value2: windowRect.height
                    },
                    to: {
                        value1: iconRect.width,
                        value2: iconRect.height
                    }
                },
                {
                    type: Effect.Translation,
                    from: {
                        value1: 0.0,
                        value2: 0.0
                    },
                    to: {
                        value1: iconRect.x - windowRect.x -
                            (windowRect.width - iconRect.width) / 2,
                        value2: iconRect.y - windowRect.y -
                            (windowRect.height - iconRect.height) / 2
                    }
                },
                {
                    type: Effect.Opacity,
                    from: 1.0,
                    to: 0.0
                }
            ];
        } else {
            // No seat in the taskbar: sink through the bottom edge instead.
            animations = [
                {
                    type: Effect.Scale,
                    to: 0.5
                },
                {
                    type: Effect.Translation,
                    from: {
                        value1: 0.0,
                        value2: 0.0
                    },
                    to: {
                        value1: 0.0,
                        value2: windowRect.height * 0.7
                    }
                },
                {
                    type: Effect.Opacity,
                    from: 1.0,
                    to: 0.0
                }
            ];
        }
        window.sinkCloseAnimation = animate({
            window: window,
            curve: QEasingCurve.InCubic,
            duration: this.closeDuration,
            animations: animations
        });
    }

    slotWindowDataChanged(window, role) {
        if (role == Effect.WindowAddedGrabRole) {
            if (window.sinkOpenAnimation && effect.isGrabbed(window, role)) {
                cancel(window.sinkOpenAnimation);
                delete window.sinkOpenAnimation;
                this.cleanupForcedRoles(window);
            }
        } else if (role == Effect.WindowClosedGrabRole) {
            if (window.sinkCloseAnimation && effect.isGrabbed(window, role)) {
                cancel(window.sinkCloseAnimation);
                delete window.sinkCloseAnimation;
                this.cleanupForcedRoles(window);
            }
        }
    }
}

new AetherSinkEffect();
