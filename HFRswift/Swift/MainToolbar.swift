//
//  MainToolbar.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import UIKit

struct MainToolbarContent<MenuItems: View>: ToolbarContent {
    let onRefresh: () -> Void
    let isLoading: Bool
    let profileImage: UIImage?
    let profileImageURL: URL?
    let menuItems: () -> MenuItems

    init(
        onRefresh: @escaping () -> Void,
        isLoading: Bool = false,
        profileImage: UIImage? = nil,
        profileImageURL: URL? = nil,
        @ViewBuilder menuItems: @escaping () -> MenuItems
    ) {
        self.onRefresh = onRefresh
        self.isLoading = isLoading
        self.profileImage = profileImage
        self.profileImageURL = profileImageURL
        self.menuItems = menuItems
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onRefresh()
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isLoading)
        }
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Menu {
                menuItems()
            } label: {
                ToolbarProfileImage(image: profileImage, url: profileImageURL)
            }
        }
    }
}

struct ToolbarProfileImage: View {
    let image: UIImage?
    let url: URL?

    var body: some View {
        avatarContent
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .liquidGlassIfAvailable(in: Circle())
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            Image(systemName: "person.crop.circle")
                .resizable()
                .scaledToFit()
                .padding(4)
        }
    }
}
