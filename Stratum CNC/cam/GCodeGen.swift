
func generateGCode(polylines: [[CGPoint]], feedRate: Double, safeZ: Double, cutZ: Double, rapidZ: Double) -> String {
    var lines: [String] = []
    lines.append("G21") // mm mode
    lines.append("G90") // absolute positioning
    lines.append("G0 Z\(safeZ)")

    for polyline in polylines {
        guard let first = polyline.first else { continue }
        lines.append(String(format: "G0 X%.4f Y%.4f", first.x, first.y))
        lines.append(String(format: "G1 Z%.4f F%.1f", cutZ, feedRate))
        for pt in polyline.dropFirst() {
            lines.append(String(format: "G1 X%.4f Y%.4f F%.1f", pt.x, pt.y, feedRate))
        }
        lines.append(String(format: "G0 Z%.4f", safeZ))
    }

    lines.append("M2") // end program
    return lines.joined(separator: "\n")
}
