//
//  WindowTransitionCoordinator.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 3/24/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import Cocoa
import Foundation
import Silica

enum WindowTransition<Window: WindowType> {
    typealias Screen = Window.Screen
    case switchWindows(_ window1: Window, _ window2: Window)
    case moveWindowToScreen(_ window: Window, screen: Screen)
    case moveWindowToSpaceAtIndex(_ window: Window, spaceIndex: Int, sourceSpaceIndex: Int)
    case resetFocus
    case rollWindows(screen: Screen, ccw: Bool)
}

protocol WindowTransitionTarget: AnyObject {
    associatedtype Application: ApplicationType
    typealias Window = Application.Window
    typealias Screen = Window.Screen

    func executeTransition(_ transition: WindowTransition<Window>)

    func isWindowFloating(_ window: Window) -> Bool
    func currentLayout() -> Layout<Application.Window>?
    func screen(at index: Int) -> Screen?
    func activeWindows(on screen: Screen) -> [Window]
    func nextScreenIndexClockwise(from screen: Screen) -> Int
    func nextScreenIndexCounterClockwise(from screen: Screen) -> Int
    func lastMainWindowForCurrentSpace() -> Window?
}

class WindowTransitionCoordinator<Target: WindowTransitionTarget> {
    typealias Window = Target.Window
    typealias Screen = Window.Screen

    weak var target: Target?

    init() {}

    func swapFocusedWindowToMain() {
        guard let focusedWindow = Window.currentlyFocused(), target?.isWindowFloating(focusedWindow) == false, let screen = focusedWindow.screen() else {
            return
        }

        guard let windows = target?.activeWindows(on: screen), let focusedIndex = windows.firstIndex(of: focusedWindow) else {
            return
        }

        if windows.count <= 1 {
            return
        }

        if focusedIndex == 0 {
            let lastMainWindow = target?.lastMainWindowForCurrentSpace() ?? windows[1]
            log.debug("focusing main \(String(describing: focusedWindow.title())), swap it with \(String(describing: lastMainWindow.title()))")
            target?.executeTransition(.switchWindows(lastMainWindow, focusedWindow))
            return
        }

        if focusedIndex != 0 {
            // Swap focused window with main window if other window is focused
            log.debug("focusing slave \(String(describing: focusedWindow.title())), swap it with \(String(describing: windows[0].title()))")
            target?.executeTransition(.switchWindows(focusedWindow, windows[0]))
        }
    }

    func swapFocusedWindowCounterClockwise() {
        guard let focusedWindow = Window.currentlyFocused(), target?.isWindowFloating(focusedWindow) == false else {
            target?.executeTransition(.resetFocus)
            return
        }

        guard let screen = focusedWindow.screen() else {
            return
        }

        guard let windows = target?.activeWindows(on: screen), let focusedWindowIndex = windows.firstIndex(of: focusedWindow) else {
            return
        }

        let windowToSwapWith = windows[(focusedWindowIndex == 0 ? windows.count - 1 : focusedWindowIndex - 1)]

        target?.executeTransition(.switchWindows(focusedWindow, windowToSwapWith))
    }

    func swapFocusedWindowClockwise() {
        guard let focusedWindow = Window.currentlyFocused(), target?.isWindowFloating(focusedWindow) == false else {
            target?.executeTransition(.resetFocus)
            return
        }

        guard let screen = focusedWindow.screen() else {
            return
        }

        guard let windows = target?.activeWindows(on: screen), let focusedWindowIndex = windows.firstIndex(of: focusedWindow) else {
            return
        }

        let windowToSwapWith = windows[(focusedWindowIndex + 1) % windows.count]

        target?.executeTransition(.switchWindows(focusedWindow, windowToSwapWith))
    }

    func rollWindowsCounterClockwise() {
        guard let focusedWindow = Window.currentlyFocused(), target?.isWindowFloating(focusedWindow) == false else {
            target?.executeTransition(.resetFocus)
            return
        }

        guard let screen = focusedWindow.screen() else {
            return
        }

        target?.executeTransition(.rollWindows(screen: screen, ccw: true))
    }

    func rollWindowsClockwise() {
        guard let focusedWindow = Window.currentlyFocused(), target?.isWindowFloating(focusedWindow) == false else {
            target?.executeTransition(.resetFocus)
            return
        }

        guard let screen = focusedWindow.screen() else {
            return
        }

        target?.executeTransition(.rollWindows(screen: screen, ccw: false))
    }

    func throwToScreenAtIndex(_ screenIndex: Int) {
        guard let screen = target?.screen(at: screenIndex), let focusedWindow = Window.currentlyFocused() else {
            return
        }

        // If the window is already on the screen do nothing.
        guard let focusedScreen = focusedWindow.screen(), focusedScreen.screenID() != screen.screenID() else {
            return
        }

        target?.executeTransition(.moveWindowToScreen(focusedWindow, screen: screen))
    }

    func swapFocusedWindowScreenClockwise() {
        guard let focusedWindow = Window.currentlyFocused(), target?.isWindowFloating(focusedWindow) == false else {
            target?.executeTransition(.resetFocus)
            return
        }

        guard let screen = focusedWindow.screen() else {
            return
        }

        guard let nextScreenIndex = target?.nextScreenIndexClockwise(from: screen), let nextScreen = target?.screen(at: nextScreenIndex) else {
            return
        }

        target?.executeTransition(.moveWindowToScreen(focusedWindow, screen: nextScreen))
    }

    func swapFocusedWindowScreenCounterClockwise() {
        guard let focusedWindow = Window.currentlyFocused(), target?.isWindowFloating(focusedWindow) == false else {
            target?.executeTransition(.resetFocus)
            return
        }

        guard let screen = focusedWindow.screen() else {
            return
        }

        guard let nextScreenIndex = target?.nextScreenIndexCounterClockwise(from: screen), let nextScreen = target?.screen(at: nextScreenIndex) else {
            return
        }

        target?.executeTransition(.moveWindowToScreen(focusedWindow, screen: nextScreen))
    }

    func pushFocusedWindowToSpace(_ space: Int) {
        guard let currentFocusedSpace = CGSpacesInfo<Window>.currentFocusedSpace(), let spaces = CGSpacesInfo<Window>.spacesForAllScreens() else {
            return
        }

        guard let index = spaces.firstIndex(of: currentFocusedSpace), index < spaces.count else {
            return
        }

        pushFocusedWindowToSpace(space, sourceSpace: index)
    }

    func pushFocusedWindowToSpace(_ space: Int, sourceSpace: Int) {
        guard let focusedWindow = Window.currentlyFocused(), focusedWindow.screen() != nil else {
            return
        }

        target?.executeTransition(.moveWindowToSpaceAtIndex(focusedWindow, spaceIndex: space, sourceSpaceIndex: sourceSpace))
    }

    func pushFocusedWindowToSpaceLeft() {
        guard let currentFocusedSpace = CGSpacesInfo<Window>.currentFocusedSpace(), let spaces = CGSpacesInfo<Window>.spacesForAllScreens() else {
            return
        }

        let filteredSpaces = spaces.filter { $0.type == CGSSpaceTypeUser }
        guard let index = filteredSpaces.firstIndex(of: currentFocusedSpace), index > 0 else {
            return
        }

        pushFocusedWindowToSpace(index - 1, sourceSpace: index)
    }

    func pushFocusedWindowToSpaceRight() {
        guard let currentFocusedSpace = CGSpacesInfo<Window>.currentFocusedSpace(), let spaces = CGSpacesInfo<Window>.spacesForAllScreens() else {
            return
        }

        let filteredSpaces = spaces.filter { $0.type == CGSSpaceTypeUser }
        guard let index = filteredSpaces.firstIndex(of: currentFocusedSpace), index + 1 < spaces.count else {
            return
        }

        pushFocusedWindowToSpace(index + 1, sourceSpace: index)
    }
}
