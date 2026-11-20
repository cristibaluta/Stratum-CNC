# Swift Code Conventions

Follow these rules for all Swift code you write or modify in this project. They override your default formatting habits.

## 1. No one-liners

Never put a control-flow body on the same line as its statement. This applies to `guard`, `if`, `else`, `for`, `while`, `switch` cases, and `defer`, no matter how short the body is.

Always open a brace, put the body on its own line(s), and close the brace on its own line.

### guard

```swift
// Wrong
guard let user = user else { return }

// Correct
guard let user = user else {
    return
}
```

### if / else

```swift
// Wrong
if isEnabled { start() }
if count == 0 { return nil } else { return items[0] }

// Correct
if isEnabled {
    start()
}

if count == 0 {
    return nil
} else {
    return items[0]
}
```

### for / while

```swift
// Wrong
for item in items { process(item) }
while queue.isEmpty == false { queue.removeFirst() }

// Correct
for item in items {
    process(item)
}

while queue.isEmpty == false {
    queue.removeFirst()
}
```

### Other cases

- Do not write `case .foo: return bar` on one line. Put the `return` on the next line.
- Do not write `defer { cleanup() }` on one line.
- Do not write one-line computed properties with braces, e.g. `var isEmpty: Bool { items.isEmpty }`. Use a multi-line body.
- Do not use semicolons to join statements on a single line.

## 2. Long method definitions

When a method signature is too long for one line (or has more than two or three parameters), use the default Xcode style:

- The first parameter stays on the same line as the method name.
- Every following parameter goes on its own line, aligned with the first parameter.
- The closing parenthesis stays on the line of the last parameter, followed by the return type and the opening brace.

```swift
// Wrong
func configure(title: String, subtitle: String, image: UIImage?, isSelected: Bool, completion: @escaping () -> Void) {
    ...
}

// Wrong: first parameter moved to its own line
func configure(
    title: String,
    subtitle: String
) {
    ...
}

// Correct
func configure(title: String,
               subtitle: String,
               image: UIImage?,
               isSelected: Bool,
               completion: @escaping () -> Void) {
    ...
}
```

The same wrapping applies to long initializers and long function calls: first argument on the same line as the name, each remaining argument on its own line, aligned with the first.

```swift
let cell = CardView(title: item.title,
                    subtitle: item.subtitle,
                    image: item.image)
```

## 3. General

- Use 4 spaces for indentation, never tabs.
- No trailing whitespace.
- Opening braces go on the same line as the declaration or statement.
- Do not reformat unrelated code when making a change. Only touch the lines needed.
