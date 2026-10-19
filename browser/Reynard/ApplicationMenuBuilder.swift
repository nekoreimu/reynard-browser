//
//  ApplicationMenuBuilder.swift
//  Reynard
//
//  Created by Minh Ton on 16/8/26.
//

import UIKit

enum ApplicationMenuBuilder {
    private static let commands: (
        file: [UIKeyCommand], edit: [UIKeyCommand], view: [UIKeyCommand],
        history: [UIKeyCommand], bookmarks: [UIKeyCommand], window: [UIKeyCommand]
    ) = {
        let fileCommands = [
            UIKeyCommand(
                title: NSLocalizedString("New Tab", comment: ""),
                action: #selector(BrowserViewController.newTabKeyCommand(_:)),
                input: "t",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("New Private Tab", comment: ""),
                action: #selector(BrowserViewController.newPrivateTabKeyCommand(_:)),
                input: "n",
                modifierFlags: [.command, .shift]
            ),
            UIKeyCommand(
                title: NSLocalizedString("Open Location", comment: ""),
                action: #selector(BrowserViewController.focusAddressBarKeyCommand(_:)),
                input: "l",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Close Tab", comment: ""),
                action: #selector(BrowserViewController.closeTabKeyCommand(_:)),
                input: "w",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Print", comment: ""),
                action: #selector(BrowserViewController.printPageKeyCommand(_:)),
                input: "p",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Downloads", comment: ""),
                action: #selector(BrowserViewController.showDownloadsKeyCommand(_:)),
                input: "j",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Settings", comment: ""),
                action: #selector(BrowserViewController.showSettingsKeyCommand(_:)),
                input: ",",
                modifierFlags: .command
            ),
        ]
        
        let editCommands = [
            UIKeyCommand(
                title: NSLocalizedString("Find in Page", comment: ""),
                action: #selector(BrowserViewController.findInPageKeyCommand(_:)),
                input: "f",
                modifierFlags: .command
            ),
        ]
        
        let viewCommands = [
            UIKeyCommand(
                title: NSLocalizedString("Reload Page", comment: ""),
                action: #selector(BrowserViewController.reloadPageKeyCommand(_:)),
                input: "r",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Show or Hide Reader", comment: ""),
                action: #selector(BrowserViewController.toggleReaderKeyCommand(_:)),
                input: "r",
                modifierFlags: [.command, .shift]
            ),
            UIKeyCommand(
                title: NSLocalizedString("Zoom In", comment: ""),
                action: #selector(BrowserViewController.zoomInKeyCommand(_:)),
                input: "+",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Zoom Out", comment: ""),
                action: #selector(BrowserViewController.zoomOutKeyCommand(_:)),
                input: "-",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Actual Size", comment: ""),
                action: #selector(BrowserViewController.actualSizeKeyCommand(_:)),
                input: "0",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Show Tab Overview", comment: ""),
                action: #selector(BrowserViewController.showTabOverviewKeyCommand(_:)),
                input: "\\",
                modifierFlags: [.command, .shift]
            ),
            UIKeyCommand(
                title: NSLocalizedString("Show or Hide Sidebar", comment: ""),
                action: #selector(BrowserViewController.toggleSidebarKeyCommand(_:)),
                input: "l",
                modifierFlags: [.command, .shift]
            ),
        ]
        
        let historyCommands = [
            UIKeyCommand(
                title: NSLocalizedString("Back", comment: ""),
                action: #selector(BrowserViewController.goBackKeyCommand(_:)),
                input: "[",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Forward", comment: ""),
                action: #selector(BrowserViewController.goForwardKeyCommand(_:)),
                input: "]",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Show History", comment: ""),
                action: #selector(BrowserViewController.showHistoryKeyCommand(_:)),
                input: "y",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Reopen Last Closed Tab", comment: ""),
                action: #selector(BrowserViewController.reopenLastClosedTabKeyCommand(_:)),
                input: "t",
                modifierFlags: [.command, .shift]
            ),
        ]
        
        let bookmarksCommands = [
            UIKeyCommand(
                title: NSLocalizedString("Show Bookmarks", comment: ""),
                action: #selector(BrowserViewController.showBookmarksKeyCommand(_:)),
                input: "o",
                modifierFlags: [.command, .shift]
            ),
            UIKeyCommand(
                title: NSLocalizedString("Add Bookmark", comment: ""),
                action: #selector(BrowserViewController.addBookmarkKeyCommand(_:)),
                input: "d",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("Edit Bookmarks", comment: ""),
                action: #selector(BrowserViewController.editBookmarksKeyCommand(_:)),
                input: "b",
                modifierFlags: [.alternate, .command]
            ),
        ]
        
        let tabSelectionCommands = (1...9).map { number in
            UIKeyCommand(
                title: String(format: NSLocalizedString("Show Tab %d", comment: ""), number),
                action: #selector(BrowserViewController.selectTabKeyCommand(_:)),
                input: String(number),
                modifierFlags: .command,
                propertyList: NSNumber(value: number)
            )
        }
        
        let tabCyclingCommands = [
            UIKeyCommand(
                title: NSLocalizedString("Previous Tab", comment: ""),
                action: #selector(BrowserViewController.previousTabKeyCommand(_:)),
                input: "\t",
                modifierFlags: [.control, .shift],
                propertyList: "previousTabControl"
            ),
            UIKeyCommand(
                title: NSLocalizedString("Next Tab", comment: ""),
                action: #selector(BrowserViewController.nextTabKeyCommand(_:)),
                input: "\t",
                modifierFlags: .control,
                propertyList: "nextTabControl"
            ),
        ]
        
        if #available(iOS 15.0, *) {
            tabCyclingCommands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        }
        
        let windowCommands = [
            UIKeyCommand(
                title: NSLocalizedString("Previous Tab", comment: ""),
                action: #selector(BrowserViewController.previousTabKeyCommand(_:)),
                input: "[",
                modifierFlags: [.command, .shift]
            ),
            UIKeyCommand(
                title: NSLocalizedString("Next Tab", comment: ""),
                action: #selector(BrowserViewController.nextTabKeyCommand(_:)),
                input: "]",
                modifierFlags: [.command, .shift]
            ),
        ] + tabCyclingCommands + tabSelectionCommands + [
            UIKeyCommand(
                title: NSLocalizedString("Close Other Tabs", comment: ""),
                action: #selector(BrowserViewController.closeOtherTabsKeyCommand(_:)),
                input: "w",
                modifierFlags: [.alternate, .command]
            ),
        ]
        
        return (
            fileCommands, editCommands, viewCommands,
            historyCommands, bookmarksCommands, windowCommands
        )
    }()
    
    static let keyCommands = commands.file + commands.edit + commands.view +
    commands.history + commands.bookmarks + commands.window
    
    static func build(with builder: UIMenuBuilder) {
        guard builder.system == UIMenuSystem.main else {
            return
        }
        
        builder.remove(menu: .preferences)
        builder.remove(menu: .close)
        builder.remove(menu: .find)
        builder.remove(menu: .textSize)
        
        if #available(iOS 15.0, *) {
            builder.remove(menu: .sidebar)
        }
        
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: commands.file), atEndOfMenu: .file)
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: commands.edit), atEndOfMenu: .edit)
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: commands.view), atEndOfMenu: .view)
        
        let historyMenu = UIMenu(
            title: NSLocalizedString("History", comment: ""),
            identifier: UIMenu.Identifier("com.minh-ton.Reynard.ApplicationMenu.History"),
            children: commands.history
        )
        builder.insertSibling(historyMenu, beforeMenu: .window)
        
        let bookmarksMenu = UIMenu(
            title: NSLocalizedString("Bookmarks", comment: ""),
            identifier: UIMenu.Identifier("com.minh-ton.Reynard.ApplicationMenu.Bookmarks"),
            children: commands.bookmarks
        )
        builder.insertSibling(bookmarksMenu, afterMenu: historyMenu.identifier)
        
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: commands.window), atEndOfMenu: .window)
    }
}
