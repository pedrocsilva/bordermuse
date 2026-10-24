# Geometry integration

The core returns canvas dimensions and four margins. Your editor prepares the
image, calls geometry, then fills and draws using its own rendering pipeline.
It needs no Border Muse app, image library or Lightroom installation.

## Swift

Add this repository as a Swift package, then depend on the geometry product:

```swift
// In your Package.swift:
.package(url: "https://github.com/pedrocsilva/bordermuse.git", branch: "main")
// In your target's dependencies:
.product(name: "BorderMuseGeometry", package: "bordermuse")
```

The API is experimental; pin a reviewed revision for reproducible integrations
until a versioned package release is available. The local example uses a path
dependency instead: `swift run --package-path examples/swift-editor`.

```swift
import BorderMuseGeometry

let size = try PixelSize(width: 6000, height: 4000)
let ratio = try AspectRatio(width: 5, height: 4)
let layout = try CanvasLayout.calculate(content: size, thickness: 10, ratio: ratio)
// Canvas 6600 × 5280; left/right 300; top/bottom 640.
// Draw the prepared 6000 × 4000 content at (300, 640), using top-left coordinates.
```

Pass `nil` for Original. Dimensions/ratio must be positive integers and thickness
must be 0–50. `GeometryError` reports invalid size, ratio, thickness or overflow.
The core has no resizing or fill API. The Apple renderer is a separate local
package under `packages/imaging-apple/`.

## Python reference and other languages

From this checkout, Python 3.9+ requires only the standard library:

```python
from geometry.reference import calculate
layout = calculate(6000, 4000, 10, (5, 4))
assert (layout.width, layout.height) == (6600, 5280)
assert (layout.left, layout.top) == (300, 640)
```

The Python source is the normative reference, not an independently published
Python distribution. For another stack, port [the specification](../docs/GEOMETRY_SPEC.md)
and run every case in `conformance-v1.json`. Use exact intermediate arithmetic,
including checked overflow or arbitrary precision as appropriate. Coordinate
conversion, orientation, resize filters, fill, color and metadata belong to the
host. Validate preview and export against the same prepared dimensions/settings.

Run `python3 -m unittest discover -s geometry -p 'test_*.py'` and `swift test`
from the repository root. The JSON is shared by both suites and includes source
hashes and confirmed corrections; do not regenerate measurements from the formula.

The code is [MIT licensed](../LICENSE); retain its license when redistributing.
