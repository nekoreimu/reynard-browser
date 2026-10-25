//
//  DataManagementSettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 22/10/26.
//

import UIKit

struct DataManagementSettingsSection {
    enum Row: CaseIterable {
        case importData
        case exportData
        case clearBrowsingData
    }
    
    var rowCount: Int {
        return Row.allCases.count
    }
    
    func cell(at index: Int) -> UITableViewCell {
        guard Row.allCases.indices.contains(index) else {
            return UITableViewCell()
        }
        
        switch Row.allCases[index] {
        case .importData:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Import", comment: ""))
        case .exportData:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Export", comment: ""))
        case .clearBrowsingData:
            return SettingsViewUtils.disclosureCell(title: NSLocalizedString("Clear Browsing Data", comment: ""))
        }
    }
    
    func selectRow(at index: Int, from viewController: UIViewController) {
        guard Row.allCases.indices.contains(index) else {
            return
        }
        
        let destination: UIViewController
        switch Row.allCases[index] {
        case .importData:
            destination = ImportPreferencesViewController()
        case .exportData:
            destination = ExportPreferencesViewController()
        case .clearBrowsingData:
            destination = ClearBrowsingDataViewController()
        }
        viewController.navigationController?.pushViewController(destination, animated: true)
    }
}
