//
//  LiquidGlass.swift
//  HFRswift
//
//  Created by Bruno ARENE on 29/01/2026.
//

import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassIfAvailable<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self
        }
    }

    /// Applique un fond thinMaterial aux sheets enfants sur iOS 26,
    /// pour rester cohérent avec l'esthétique Liquid Glass.
    @ViewBuilder
    func presentationGlassBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.presentationBackground(.thinMaterial)
        } else {
            self
        }
    }
}
