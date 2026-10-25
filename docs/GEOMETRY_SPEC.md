# Border geometry v1

Contract: `bordermuse-geometry-v1`. Python [reference](../geometry/reference.py)
is normative; every implementation must match the [shared measured cases](../geometry/conformance-v1.json)
exactly for canvas dimensions and all four margins.

## Inputs and result

- `w`, `h`: positive integer content dimensions, after orientation and deliberate resizing.
- `rw`, `rh`: positive integer target ratio components.
- `t`: integer thickness from 0 to 50, using the measured Lightroom Mobile UI scale.
- Original means `(rw, rh) = (w, h)` in Border Muse; Mobile's Original mode is unmeasured.

The result is canvas width/height and symmetric left/right/top/bottom margins.
Photo placement starts at `(left, top)` in top-left canvas coordinates. Geometry
neither resizes nor crops. Fill color, image formats, encoding, color management
and metadata are renderer concerns.

## Formula

Keep all intermediates exact until flooring the half-margins:

```text
r = rw / rh
s = (100 + t) / 100
idealWidth  = max(w, h × r) × s
idealHeight = max(h, w / r) × s
marginX = floor((idealWidth  - w) / 2)
marginY = floor((idealHeight - h) / 2)
width  = w + 2 × marginX
height = h + 2 × marginY
left = right = marginX
top = bottom = marginY
```

Equivalent exact integer arithmetic (`//` is floor division):

```text
if w × rh >= h × rw:
    marginX = (w × t) // 200
    marginY = (w × (100+t) × rh - 100 × h × rw) // (200 × rw)
else:
    marginX = (h × (100+t) × rw - 100 × w × rh) // (200 × rh)
    marginY = (h × t) // 200
```

Use checked/wide integers or arbitrary precision for intermediates. Do not round
thickness first, introduce floating-point tolerances or snap the final canvas to
an exact ratio. Output preserves content parity and equal margins per axis.
Thickness zero can still add ratio padding. Invalid inputs and arithmetic
overflow must produce errors, rather than approximate layouts.

## Measurement provenance and limits

Reference exports identify Lightroom 11.6.10 for iOS. The corpus contains 20
bordered cases and three full-size baselines, with filenames, SHA-256 hashes,
measured dimensions/margins and a confirmed setting correction. These are the
observations used to infer the formula, not independent validation of all Mobile
behavior. The repository includes numeric evidence, not source photographs.

`16by9_3by2export_thic10.JPG` is confirmed as a 1:1, thickness 10 export despite
its filename. Preserve its recorded correction and all measured evidence.
The actual 16:9 → 3:2, thickness 10 case remains missing.

The samples used a 2048 px content long edge. This is not a geometry limit;
resizing is separate. Measurements cover thickness 0/10/20 and explicit ratios
5:4, 1:1, 3:2, 9:16 and 2:1. Original mode, other thicknesses, odd dimensions,
other content resolutions, Android and other Mobile versions need further
empirical checks. Mathematical tests at other sizes do not establish those claims.

## Mobile reference export policy

The built-in **Mobile reference** preset applies target 5:4, thickness 10 and a
photo long edge up to 2048 px. It leaves JPEG quality and metadata policy as
chosen by the user. It is read-only; Save creates a separate user preset.
Changing its geometry switches the selection to Custom. Original and Custom
photo sizes remain available outside this preset; the default stays Original.

Preparation occurs before the geometry call. The 2048 px limit concerns the
photo, not the final canvas. For the measured 3923 × 5886 portrait source,
preparation produces 1365 × 2048. With thickness 10, the measured canvases are
2815 × 2252 (5:4), 4505 × 2252 (2:1), and 3379 × 2252 (3:2).

[Mobile export baselines](../geometry/mobile-export-v1.json) record the three
original source dimensions and hashes, paired with the unchanged 20-case corpus.
Apple and Windows renderer tests generate synthetic black images at those source
sizes, reduce them, export borders, and measure the resulting canvas and all four
margins against the existing observations. No personal photos are bundled or
needed in CI. These tests protect the preparation/export path as well as the
portable arithmetic.

The preset is a reference to measured iOS 11.6.10 geometry, not a promise about
all Mobile settings or future versions. Tests for smaller/odd images, Original
ratio and other thicknesses validate Border Muse's own policies separately and
must not be reported as new Lightroom observations.

Further empirical captures should pair an untouched source with its Mobile
export and record platform/version, ratio and thickness. Remaining gaps include
the actual 16:9 → 3:2 thickness-10 case, Original ratio, other thickness values,
photos smaller than 2048 and odd dimensions. Preserve the existing confirmed
filename correction; a new capture must become a separate case.

Version changes to output behavior explicitly and agree them before implementation.
Renaming package or contract metadata does not change the formula. Preserve
measured cases and test every port against the same corpus with zero pixel tolerance.
