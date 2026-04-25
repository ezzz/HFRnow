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

    @ViewBuilder
    func hfrGlassSurface<S: Shape>(
        in shape: S,
        fallbackStrokeOpacity: Double = 0.14,
        shadowOpacity: Double = 0.16,
        shadowRadius: CGFloat = 10,
        shadowY: CGFloat = 4
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular, in: shape)
                .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        } else {
            self
                .background(.thinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(fallbackStrokeOpacity), lineWidth: 0.7)
                }
                .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        }
    }

    @ViewBuilder
    func hfrGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    func hfrLoadingPanel<S: Shape>(in shape: S) -> some View {
        self.hfrGlassSurface(in: shape, shadowOpacity: 0.18, shadowRadius: 12, shadowY: 4)
    }

    func hfrToastSurface() -> some View {
        self.hfrGlassSurface(in: Capsule(), shadowOpacity: 0.18, shadowRadius: 10, shadowY: 4)
    }
}
