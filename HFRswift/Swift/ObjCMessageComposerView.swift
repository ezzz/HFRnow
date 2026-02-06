//
//  ObjCMessageComposerView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 29/01/2026.
//
/*
import SwiftUI
import UIKit

struct ObjCMessageComposerView: UIViewControllerRepresentable {
    let urlQuote: String
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UINavigationController {
        let composer = NewMessageViewController(nibName: "AddMessageViewController", bundle: nil)
        composer.delegate = context.coordinator
        composer.urlQuote = urlQuote
        composer.title = "Nouv. Réponse"
        let navController = UINavigationController(rootViewController: composer)
        navController.modalPresentationStyle = .fullScreen
        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No-op
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    final class Coordinator: NSObject, AddMessageViewControllerDelegate {
        @Binding var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func addMessageViewControllerDidFinish(_ controller: AddMessageViewController) {
            isPresented = false
        }

        func addMessageViewControllerDidFinishOK(_ controller: AddMessageViewController) {
            isPresented = false
        }
    }
}
*/
