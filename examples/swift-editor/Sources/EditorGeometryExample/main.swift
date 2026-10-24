import BorderMuseGeometry

// An editor prepares its image, then uses these dimensions in its own renderer.
let content = try PixelSize(width: 6000, height: 4000)
let ratio = try AspectRatio(width: 5, height: 4)
let layout = try CanvasLayout.calculate(content: content, thickness: 10, ratio: ratio)
precondition(layout.width == 6600 && layout.height == 5280)
precondition(layout.left == 300 && layout.right == 300)
precondition(layout.top == 640 && layout.bottom == 640)
print("Canvas: \(layout.width) × \(layout.height); photo origin: \(layout.left), \(layout.top)")
