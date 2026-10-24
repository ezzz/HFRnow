//
//  NatifMessagePreview.swift
//  HFRswift
//
//  Live preview of a forum message in Réglages (design 3d): follows the theme, accent,
//  text size, smiley size and compact mode as they change.
//

import SwiftUI

struct NatifMessagePreview: View {
    @Environment(\.natif) private var natif
    @AppStorage(AppTextSizeScale.key) private var textSizeScaleRawValue = AppTextSizeScale.standard.rawValue
    @AppStorage(AppLayoutCompactMode.key) private var isCompact = false
    @AppStorage(NatifAppearance.smileyScaleKey) private var smileyScale = 1.0
    @ScaledMetric(relativeTo: .body) private var bodyBase: CGFloat = 17

    private var bodySize: CGFloat {
        bodyBase * AppTextSizeScale.value(for: textSizeScaleRawValue).factor * (isCompact ? 15 / 17 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            header
            VStack(alignment: .leading, spacing: 6) {
                Text("Grumly a écrit :")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(natif.accent)
                Text("Le 9800X3D vaut vraiment le coup pour jouer ?")
                    .font(.system(size: bodySize - 2))
                    .foregroundStyle(natif.text.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(natif.surface, in: .rect(cornerRadius: 12))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Clairement, surtout en 1440p.")
                    .font(.system(size: bodySize))
                    .foregroundStyle(natif.text)
                Image(systemName: "face.smiling.inverse")
                    .font(.system(size: 15 * smileyScale))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, isCompact ? 8 : 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aperçu d'un message")
    }

    @ViewBuilder
    private var header: some View {
        if isCompact {
            HStack(spacing: 8) {
                NatifAvatar(pseudo: "Kaiju", size: 26)
                Text("Kaiju").font(.subheadline.weight(.semibold)).foregroundStyle(natif.text)
                Text("14:02").font(.caption).foregroundStyle(natif.text2)
                Spacer()
                moreButton
            }
        } else {
            HStack(spacing: 10) {
                NatifAvatar(pseudo: "Kaiju", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kaiju").font(.subheadline.weight(.semibold)).foregroundStyle(natif.text)
                    Text("Aujourd'hui, 14:02").font(.caption).foregroundStyle(natif.text2)
                }
                Spacer()
                moreButton
            }
        }
    }

    private var moreButton: some View {
        Image(systemName: "ellipsis")
            .font(.footnote.weight(.bold))
            .foregroundStyle(natif.accent)
            .frame(width: 30, height: 30)
            .background(Circle().fill(isCompact ? Color.clear : natif.surface))
            .accessibilityHidden(true)
    }
}
