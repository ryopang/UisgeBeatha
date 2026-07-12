//
//  ContentView.swift
//  UisgeBeatha
//

import SwiftUI

/// Placeholder root. Replaced by RootTabView in Phase 2.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wineglass")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(Strings.App.name)
                .font(.title2)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
