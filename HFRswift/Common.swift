//
//  Common.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

extension Favorite: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Topic: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
