#!/usr/bin/env python3
"""Run hardware-independent Swift tests without the external CAM packages."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    'projects/Project.swift',
    'projects/ProjectPaths.swift',
    'cam/supported-files/gerber/ArchiveEntryPath.swift',
    'controller/gcode/NCFileDocument.swift',
    'controller/gcode/GCodeToolpathAnalyzer.swift',
    'controller/gcode/GCodeToolpath.swift',
    'tools-lib/FusionToolsImporter.swift',
    'tools-lib/Tool.swift',
    'tools-lib/ToolsStore.swift',
    'tools-lib/ToolLibrary.swift',
    'tools-lib/LaserMaterialPreset.swift',
    'tools-lib/ThreadMillingPreset.swift',
    'tools-lib/ToolPreset.swift',

    'metal-canvas/HeightmapGrid.swift',
    'metal-canvas/ToolFootprint.swift',
    'controller/gcode/GCodeUploader.swift',
    'controller/connection/MakeraWireProtocol.swift',
    'controller/gcode/GCodeJobRunner.swift',
    'controller/gcode/GCodeParser.swift',
    'controller/gcode/GCodeBounds.swift',
    'controller/gcode/GCodeHeader.swift',
    'controller/gcode/ToolSpec.swift',
    'controller/gcode/MakeraHeaderParser.swift',
    'controller/gcode/FusionHeaderParser.swift',
    'controller/gcode/MakeraCAMHeaderParser.swift',

    'controller/connection/MakeraFraming.swift',
    'stocks-lib/StocksStore.swift',
    'stocks-lib/StockLibrary.swift',
    'stocks-lib/StockMaterial.swift',
    'stocks-lib/StockMaterialType.swift',
    'stocks-lib/StockGeometry.swift',

]

with tempfile.TemporaryDirectory(prefix='stratum-core-') as directory:
    package = Path(directory)
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "StratumCoreRegressionTests",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "Stratum_CNC"),
        .testTarget(name: "CoreTests", dependencies: ["Stratum_CNC"])
    ]
)
''')
    sources = package / 'Sources/Stratum_CNC'
    tests = package / 'Tests/CoreTests'
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for relative in SOURCES:
        source = ROOT / 'Stratum CNC' / relative
        (sources / source.name).symlink_to(source)
    for source in (ROOT / 'Stratum CNC Tests').glob('*RegressionTests.swift'):
        (tests / source.name).symlink_to(source)
    result = subprocess.run([
        'swift', 'test', '--package-path', str(package), '--disable-sandbox',
    ])
    raise SystemExit(result.returncode)
