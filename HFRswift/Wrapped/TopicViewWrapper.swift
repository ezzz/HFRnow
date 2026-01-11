//
//  TopicViewWrapper.swift
//  SuperHFRplus
//
//  Created by ezzz on 19/07/2025.
//

import SwiftUI

struct MessageViewWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        return MessageTableViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Optionnel, rien à mettre à jour dynamiquement
    }
}
