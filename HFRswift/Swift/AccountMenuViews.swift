//
//  AccountMenuViews.swift
//  HFRswift
//
//  Created by Bruno ARENE on 29/01/2026.
//

import SwiftUI
import UIKit

struct AccountMenuRow: View {
    let account: Account

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(account.displayName)
                if account.isMain {
                    Image(systemName: "checkmark")
                }
            }
        } icon: {
            AccountAvatarView(image: account.avatarImage, size: 18)
        }
    }
}

struct AccountAvatarView: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
