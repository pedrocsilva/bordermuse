import BorderMuseGeometry

// Content preparation is independent of canvas geometry.
extension PixelSize {
    public func reduced(longEdge: Int?) throws -> PixelSize {
        guard let longEdge else { return self }
        guard longEdge > 0 else { throw GeometryError.invalidSize }
        let longest = max(width, height)
        guard longEdge < longest else { return self }
        let scale = Double(longEdge) / Double(longest)
        return try PixelSize(width: max(1, Int((Double(width) * scale).rounded())),
                             height: max(1, Int((Double(height) * scale).rounded())))
    }
}
