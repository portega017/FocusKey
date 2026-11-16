//
//  ToastCenter.swift
//  FocusKey
//
//  Shows FocusModel.status messages above everything, sheets included (Settings, editors…),
//  in a transparent window that ignores touches, so it never blocks what's underneath.
//

import Combine
import SwiftUI
import UIKit

@MainActor
final class ToastCenter: ObservableObject {
    @Published fileprivate(set) var message: String?
    private var window: UIWindow?
    private var hideTask: Task<Void, Never>?

    /// Creates the overlay window once, in the app's scene.
    func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let host = UIHostingController(rootView: ToastOverlay(center: self))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        // Touches go to the app underneath; the toast hides by itself.
        window.isUserInteractionEnabled = false
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    func show(_ text: String) {
        install()
        withAnimation(.smooth) { message = text }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { message = nil }
        }
    }
}

private struct ToastOverlay: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        VStack {
            if let message = center.message {
                Toast(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
