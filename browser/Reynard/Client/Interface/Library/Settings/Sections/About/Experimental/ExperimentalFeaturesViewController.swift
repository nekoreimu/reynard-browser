//
//  ExperimentalFeaturesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 19/7/26.
//

import UIKit

final class ExperimentalFeaturesViewController: SettingsTableViewController {
    private enum UX {
        static let restartDelay = 1
    }
    
    init() {
        super.init(style: .insetGrouped)
        title = "Experimental Features"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 0
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 0
    }
    
    private func showRestartAlert() {
        let alert = UIAlertController(
            title: "Restart Required",
            message: "The app will now close for the experimental setting to take effect.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .seconds(UX.restartDelay)
            ) {
                exit(EXIT_SUCCESS)
            }
        })
        present(alert, animated: true)
    }
}
