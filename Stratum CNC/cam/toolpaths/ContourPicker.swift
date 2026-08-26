//
//  ContourPicker.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ContourPicker: View {
    @Binding var selection: ContourType

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CONTOUR")
                .font(.system(size: 9))

            Picker("", selection: $selection) {
                ForEach(ContourType.allCases, id: \.self) {
                    Text($0.rawValue)
                        .tag($0)
                }
            }
            .pickerStyle(.menu)
            .frame(height: 30)
//            .background(.background)
//            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
