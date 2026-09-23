//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var registry = NinoModuleRegistry.shared
    @Namespace var animation

    private var ninoTabs: [TabModel] {
        var items = [
            TabModel(label: "Home", icon: "house.fill", view: .home),
            TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
        ]
        if !registry.modules.isEmpty {
            items.append(TabModel(label: "Nino", icon: "sparkles", view: .modules))
        }
        return items
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ninoTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? NinoTheme.gold : NinoTheme.dim)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? NinoTheme.gold.opacity(0.15) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? NinoTheme.gold.opacity(0.15) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

