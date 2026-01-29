//
//  MainToolbar.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI

struct MainToolbarContent<MenuItems: View>: ToolbarContent {
    let onRefresh: () -> Void
    let onMore: () -> Void
    let profileImageURL: URL?
    let menuItems: () -> MenuItems

    init(
        onRefresh: @escaping () -> Void,
        onMore: @escaping () -> Void,
        profileImageURL: URL?,
        @ViewBuilder menuItems: @escaping () -> MenuItems
    ) {
        self.onRefresh = onRefresh
        self.onMore = onMore
        self.profileImageURL = profileImageURL
        self.menuItems = menuItems
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            Button {
                onMore()
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Menu {
                menuItems()
            } label: {
                ToolbarProfileImage(url: profileImageURL)
            }
        }
    }
}

struct ToolbarProfileImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(width: 28, height: 28)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            case .failure:
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            @unknown default:
                EmptyView()
            }
        }
    }
}
