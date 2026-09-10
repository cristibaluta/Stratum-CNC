DXF Entities  --->  [ Geometry Processor ]  --->  Path / Loop Graphs
                                                         |
Tool & Machining Parameters  ----------------------------+
                                                         v
                                              [ Operation Pipeline ]
                                                         |
                                                         v
                                                Processed Toolpaths
                                              (Draw in UI / Export G-code)


[ DXF Entities ]
      │
      ▼
1. Extract & Linearize (Convert bulges/ellipses -> VectorPath)
      │
      ▼
2. Chain & Topology (Stitch disconnected lines/arcs into closed loops)
      │
      ▼
3. Offset & Pocket Generators (Apply tool radius offsetting, stepdowns, and pocket logic)
      │
      ▼
4. Z-Pass & Lead-In Generator (Add helical ramps, multi-depth Z passes, and safe moves)
      │
      ▼
[ ComputedToolpath ] ───► Render on Screen (SwiftUI / Metal Canvas)
      │
      ▼
[ G-Code Emitter ] ───► Export to File (.nc / .gcode)
