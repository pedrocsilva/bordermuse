import ArgumentParser
import Foundation
import BorderMuseImaging

@main
struct BorderMuseCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bordermuse",
        abstract: "Frame photos with a border and a target aspect ratio. Currently exports white borders."
    )

    @Option(name: .long, help: "Input image path (JPEG, TIFF, PNG).")
    var input: String

    @Option(name: .long, help: "Output image path.")
    var output: String

    @Option(name: .long, help: "Thickness UI value (0–50), using bordermuse-geometry-v1.")
    var borderPercent: Int

    @Option(name: .long, help: "Target aspect ratio: 'original' or W:H (e.g. '4:5', '16:9').")
    var aspectRatio: String

    mutating func run() throws {
        do {
            try processImage(
                inputURL: URL(fileURLWithPath: input),
                outputURL: URL(fileURLWithPath: output),
                borderPercent: borderPercent,
                aspectRatio: aspectRatio
            )
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
