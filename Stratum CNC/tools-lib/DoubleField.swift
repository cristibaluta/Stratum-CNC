//
//  DoubleField.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct DoubleField: View {

    @Binding var value: Double

    var body: some View {
        TextField(
            "",
            value: $value,
            format: .number
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 100)
    }
}

struct Int2Field: View {

    @Binding var value: Int

    var body: some View {
        TextField(
            "",
            value: $value,
            format: .number
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 100)
    }
}
