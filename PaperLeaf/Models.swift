import Foundation

enum PageTemplate: String, Codable, CaseIterable, Identifiable, Hashable {
    case ruled = "Ruled"
    case grid = "Grid"
    case blank = "Blank"
    case pdf = "PDF"

    var id: String { rawValue }
}

struct NotePage: Codable, Identifiable {
    var id = UUID()
    var drawingData = Data()
    var backgroundImageName: String?
    var aspectRatio = 0.707 // A4 portrait width / height
    var template: PageTemplate = .ruled
    var canvasWidth = 900.0
    var canvasHeight = 1273.0
}

struct Notebook: Codable, Identifiable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var pages: [NotePage] = [NotePage()]
    var pdfFileName: String?
}
