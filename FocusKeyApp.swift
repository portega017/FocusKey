//
//  FocusKeyApp.swift
//  FocusKey
//
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
