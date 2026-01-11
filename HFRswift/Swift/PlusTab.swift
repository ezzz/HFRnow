//
//  PlusTab.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import SwiftUI

struct PlusTableViewWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PlusTableViewController {
        return PlusTableViewController()
    }

    func updateUIViewController(_ uiViewController: PlusTableViewController, context: Context) {
        // Pas besoin de mise à jour pour une vue statique
    }
}
