# Roadmap: ideas for future implementation

Features not in the app yet. Each builds on something that already exists.

## Picking from the model (builds on edge selection)

- **Face and feature picking, not only edges.** Click a pocket floor or a hole and get the toolpath. This is the biggest step up from edge selection. "Select linked" is already a first version of it.
- **Hole detection.** Find all the circles of the same diameter and depth, then offer drilling, peck drilling, or helical milling of the group. This pairs well with the new circle and arc measurements.
- **Automatic machinable regions.** Detect pockets and the stock exterior from the model, which fits the probing goal of telling stock exterior from pocket interior.

## Checking before cutting

- **Collision and gouge checks.** Check the tool and holder against the model, clamps and fixtures, and flag cuts into the part.
- **Cutting-time estimate and a feed/speed advisor.** Show time per toolpath and total, and warn when chip load or spindle load looks wrong for the tool and material.
