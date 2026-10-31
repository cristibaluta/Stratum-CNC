# Tool library redesign: implementation plan

Goal: replace the single grouped sidebar with **type rail | tool list | editor**, and track where each tool came from (**source**) as a field separate from its type.

Each step below builds and runs on its own, so you can stop after any of them and the app still works.

---

## Constraint: the editor column keeps its width

Today the editor gets roughly `900 − 300 = 600 pt` (the sheet is `minWidth: 900` in `ToolPickerDemo`, the sidebar is 260–400, ideal 300). The diagram, the form and the presets matrix are laid out for that.

Adding a rail must not take that space from the editor. So the rail's width is **added to the sheet**, not carved out of the editor:

| Column | Width |
|---|---|
| Type rail | 170 fixed |
| Tool list | min 260, ideal 300, max 400 (unchanged) |
| Editor | at least 600, takes all remaining space |
| **Sheet minimum** | **1080 × 600** |

Rules:
- The minimum size is set **inside `ToolsSheet`** (`.frame(minWidth: 1080, minHeight: 600)`), not by the callers. Today `ToolPickerDemo` sets 900, and any other caller could silently squeeze the editor.
- Remove the `minWidth: 900` from `ToolPickerDemo` once the sheet owns its size.
- The editor view itself is **not touched** in steps 1 to 4. Its fixed widths (`ToolDiagramView` 100 × 240, fields 80–180, matrix `maxWidth: .infinity`) stay as they are.
- Check at the end: with the sheet at its minimum size, the editor must look pixel-identical to today (Step 9).

---

## Step 1 [done]: Layout shell (no behaviour change)

**Files:** `ToolsSheet.swift`

1. Replace the body's `NavigationSplitView` with:
   ```swift
   HStack(spacing: 0) {
       ToolTypeRail(...)            // placeholder for now: just a 170pt-wide column
           .frame(width: 170)
       Divider()
       NavigationSplitView { list } detail: { editor }
   }
   ```
   Keep the existing two-column `NavigationSplitView` for list and editor. Do **not** use a three-column split view: it adds a collapsible sidebar toggle and lets the rail vanish or resize, which fights the fixed-width requirement.
2. Add `.frame(minWidth: 1080, minHeight: 600)` to the sheet's root.
3. Remove the 900 frame from `ToolPickerDemo`.

**Done when:** the sheet opens at 1080 wide, the rail is an empty 170 pt column, and the editor is the same width as before.

---

## Step 2 [done]: Filter model (pure logic, testable)

**New file:** `ToolFilter.swift`

```swift
enum MaterialFilter: CaseIterable { case any, metal, nonMetal }

enum ToolScope: Hashable {
    case all
    case inStock
    case type(ToolType)
}

struct ToolFilter {
    var scope: ToolScope = .all
    var material: MaterialFilter = .any
    var source: ToolSourceFilter = .any      // added in Step 6; stub as Void/any for now
    var query: String = ""

    func apply(to tools: [Tool]) -> [Tool] { ... }        // filter + sort
    func counts(in tools: [Tool]) -> [ToolScope: Int]    // for the rail
}
```

Behaviour:
- **Search** matches name, type display name, and diameter text (`"3.175"`, `"3"`), case-insensitive.
- **Sort** within a type: diameter, then length, then name. For `.all` / `.inStock`: `ToolType.allCases` order, then the same.
- **Counts are faceted:** each rail count reflects the search, material and source filters, but ignores the scope itself. Picking "Metal" shows how many metal tools each type has.
- Move `isForMetal` use here. `groupedByGroup` and `ToolGroup` stay for now and are deleted in Step 9.

**Done when:** unit tests cover search, material, stock, sort order, and counts.

---

## Step 3 [done]: Type rail

**New file:** `ToolTypeRail.swift`

- Rows: **All tools**, **In stock**, divider and a "Type" label, then one row per `ToolType` that has at least one tool.
- Each row: icon, title, trailing count (secondary colour). Reuse the existing `ToolTypeIcon(type:size: 18)` for type rows, so the rail and the editor stay visually consistent.
- Selected row uses the system sidebar selection style. Use `List(selection:)` with `.listStyle(.sidebar)`.
- A type with count 0 under the current filters is dimmed but still selectable.
- Bind to `ToolFilter.scope` and read counts from `filter.counts(in:)`.

**State in `ToolsSheet`:** replace `inStockOnly` and `metalOnly` with a single `@State private var filter = ToolFilter()`. Delete `visibleTools`'s inline closure and use `filter.apply(to: store.tools)`.

**Done when:** clicking a type filters the list, counts match, and the selection jumps to the first visible tool when the current one is filtered out (replace `reselectIfHidden` and `selectFirstIfNeeded` to use the new sorted order, not `groupedByGroup`).

---

## Step 4 [done]: List redesign and header cleanup

**Files:** `ToolListView.swift`, `ToolsSheet.swift`

**List top bar** (replaces the bottom toggles):
1. Search field.
2. Material chips: **Any material · Metal · Non metal** (single select).
3. Row with the Source dropdown (Step 8) and a `+` menu. Until Step 8, leave the dropdown out.

**`+` menu:** Add tool, Import… (moves the two buttons out of the page header).

**Rows:**
- Layout: `Ø diameter` (tabular digits, fixed ~44 pt) · name with a second line · source chip · stock count.
- Second line: `L 3 mm · Shank 3.175` under a single type, and the type name when scope is All or In stock.
- Drop the per-row `ToolTypeIcon` (the rail already says the type). Keep it when scope is All or In stock.
- No section headers. Keep the context menu (Duplicate, Delete).
- Empty state: "No tools match. Clear a filter." with a **Clear filters** button.

**Header:** remove the "Tools" title row and its divider. The sheet's title goes into the window or sheet title. The bottom bar (Unsaved changes, Revert, Save, Done or Pick) stays exactly as it is.

**Done when:** the old bottom toggles are gone, search and chips work together with the rail, and Add and Import still work from the `+` menu.

---

## Step 5 [done]: Source data model

**Files:** `Tool.swift`, `ToolLibrary.swift`, new `ToolSource.swift`

```swift
enum ToolSourceKind: String, Codable { case bundled, imported, custom }

struct ToolSourceInfo: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String          // "Makera defaults", "shop.tools", "My tools"
    var kind: ToolSourceKind
    var date: Date?           // import date; nil for bundled / custom
    var fileName: String?
}
```

- `Tool` gets `var sourceID: UUID?`. Decode with `decodeIfPresent`, so existing files still load. Add it to `CodingKeys` and both initialisers.
- `ToolLibrary` gets `var sources: [ToolSourceInfo]?` (optional for the same reason). Bump `schemaVersion`.
- Two fixed IDs, defined as constants: **bundled** and **custom** ("My tools"). Imports get a fresh UUID each.
- `Tool.group` stays as-is, as a free-text label. It is no longer used for navigation.

**Done when:** an old `tools.json` loads, saves back with `sources`, and round-trips unchanged otherwise.

---

## Step 6 [done]: Store and migration

**File:** `ToolsStore.swift`

- `load()`: if `sources` is missing, create the bundled and custom entries and set every tool without a `sourceID` to **bundled**. Save once.
- `add(_:)`: new tools get the **custom** source. The `+` menu's "Add tool" also pre-fills `type` from the current rail scope (falls back to `.endMill`). Today it copies the selected tool's `group`; drop that.
- `duplicate(_:)`: the copy gets the **custom** source, whatever the original's was. Keep the "Copy" name suffix.
- `copyDefaultTools()` (first run): all bundled tools are stamped with the bundled source.
- Expose `var sources: [ToolSourceInfo]` and `func source(for: Tool) -> ToolSourceInfo`.

**Done when:** a fresh install and an upgraded install both end up with every tool having a source, and duplicates land under My tools.

---

## Step 7 [done]: Importer stamps a batch

**Files:** `FusionToolsImporter.swift`, `ToolsStore.swift`, `ToolsSheet.swift`

- `ToolsStore.importTools(_:from:)` takes the file name, creates one `ToolSourceInfo(kind: .imported, name: <file name without extension>, date: .now)`, and stamps each **newly added** tool with its id.
- Tools that already exist (matched by id, as today) keep their original source. Only their new presets are merged, as today.
- If a batch ends up adding no tools, don't create the source.
- The result summary gains the batch name: "Imported 14 tools from shop.tools."
- The importer's `group` ("vendor + type") keeps being written; it's just a label now.

**Done when:** importing a `.tools` file creates a source, new tools carry it, and re-importing the same file creates none.

---

## Step 8: Source filter and import management

**Files:** `ToolFilter.swift`, `ToolListView.swift`, new small `ManageImportsView.swift`

- `ToolSourceFilter`: `.any` or `.source(UUID)`.
- Source dropdown in the list's top bar: **All sources**, then each source with its tool count, then a divider and **Manage imports…**.
- Source chip on each row: bundled in neutral, imported in warm, custom in green. The chip has text as well as colour.
- **Manage imports** sheet: one row per import batch (name, date, tool count) with a **Remove batch** action. It removes every tool in that batch after a confirmation that states the count. It can be undone until you press Save, because edits are live until then and Revert restores them.
- If the source of the current selection disappears, reselect the first visible tool.

**Done when:** filtering by a source works with the rail, and removing a batch updates counts and selection correctly.

---

## Step 9: Cleanup and verification

**Cleanup**
- Delete `ToolGroup`, `groupedByGroup`, `reselectIfHidden`'s old body, and the unused bottom-toggle code.
- `Tool+HeaderMatching.swift`: confirm nothing still reads `group` for logic.
- Delete the `ToolPickerDemo` frame override if not already done.

**Width check (the requirement)**
- Open the sheet at its minimum size (1080 × 600). The editor column is at least 600 pt, and the diagram, form and presets matrix show without horizontal clipping.
- Resize larger: the extra width goes to the editor. The rail stays 170 and the list stays within 260–400.
- Compare a screenshot of the editor before and after: it should be identical.

**Behaviour checklist**
- [ ] Rail counts update with search, material and source filters.
- [ ] Switching type keeps the selected tool if it's still visible, otherwise selects the first.
- [ ] Delete selects the neighbour in the **new** sorted order.
- [ ] Pick mode (`onPick`) still returns the selected tool.
- [ ] Unsaved changes, Revert and Save still work with the new filters.
- [ ] Old `tools.json` loads and upgrades. A new install gets the bundled source on all tools.
- [ ] Import, re-import and Manage imports behave as described.
- [ ] Dark mode and light mode both look right.

---

## Open decisions (defaults used above)

1. **Material stays inferred** (`isForMetal`). Storing it as a field would be more reliable but needs a one-time pass over the 69 bundled tools. Can be a follow-up without changing this plan.
2. **No Favourites or Recent row** in the rail for now. In stock is the only smart scope. Easy to add as another `ToolScope` case.
3. **Imported tools are edited in place.** No copy-on-write. Duplicate is the way to fork one into My tools.
