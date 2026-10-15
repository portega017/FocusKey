//
//  FocusKeyApp.swift
//  FocusKey
//
//  Created by Pablo Ortega on 14/10/2026.
//


import SwiftUI

@main
struct FocusKeyApp: App {
    @StateObject private var model = FocusModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
