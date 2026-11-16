import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (ForumCategoryIconView, `:983-1011`) @ 87fe0d1c. Differences: the template image takes
// `.primary` (legacy's black or white by hand); `folder.fill` stays the fallback of a missing asset (GAP-021).
/// A category's 28 pt template icon.
struct ForumCategoryIconView: View {
    let assetName: String

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
