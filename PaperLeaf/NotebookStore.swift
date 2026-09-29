import Foundation
import Combine
import PDFKit
import PencilKit
import UIKit

@MainActor
final class NotebookStore: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []

    private let fileManager = FileManager.default
    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var libraryURL: URL { documentsURL.appendingPathComponent("PaperLeafLibrary.json") }
    private var assetsURL: URL { documentsURL.appendingPathComponent("PaperLeafFiles", isDirectory: true) }

    init() {
        try? fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        load()
    }

    func notebook(id: UUID) -> Notebook? {
        notebooks.first { $0.id == id }
    }

    @discardableResult
    func createNotebook(title: String = "Untitled Notebook") -> UUID {
        let notebook = Notebook(title: title)
        notebooks.insert(notebook, at: 0)
        persist()
        return notebook.id
    }

    func addPage(to notebookID: UUID) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
        notebooks[index].pages.append(NotePage())
        persist()
    }

    func updateDrawing(_ data: Data, notebookID: UUID, pageIndex: Int, canvasSize: CGSize? = nil) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }),
              notebooks[index].pages.indices.contains(pageIndex) else { return }
        notebooks[index].pages[pageIndex].drawingData = data
        if let canvasSize, canvasSize.width > 0, canvasSize.height > 0 {
            notebooks[index].pages[pageIndex].canvasWidth = Double(canvasSize.width)
            notebooks[index].pages[pageIndex].canvasHeight = Double(canvasSize.height)
        }
        persist()
    }

    func updateTemplate(_ template: PageTemplate, notebookID: UUID, pageIndex: Int) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }),
              notebooks[index].pages.indices.contains(pageIndex),
              notebooks[index].pages[pageIndex].backgroundImageName == nil else { return }
        notebooks[index].pages[pageIndex].template = template
        persist()
    }

    func backgroundImage(named name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: assetsURL.appendingPathComponent(name).path)
    }

    func pdfURL(named name: String?) -> URL? {
        guard let name else { return nil }
        let url = assetsURL.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func importPDF(from sourceURL: URL) throws -> UUID {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: sourceURL), document.pageCount > 0 else {
            throw ImportError.unreadablePDF
        }

        var pages: [NotePage] = []
        for pageNumber in 0..<document.pageCount {
            guard let pdfPage = document.page(at: pageNumber) else { continue }
            let bounds = pdfPage.bounds(for: .cropBox)
            pages.append(NotePage(
                aspectRatio: Double(bounds.width / max(bounds.height, 1)),
                template: .pdf
            ))
        }

        guard !pages.isEmpty else { throw ImportError.unreadablePDF }
        let storedPDFName = "\(UUID().uuidString).pdf"
        try fileManager.copyItem(at: sourceURL, to: assetsURL.appendingPathComponent(storedPDFName))
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let notebook = Notebook(title: title, pages: pages, pdfFileName: storedPDFName)
        notebooks.insert(notebook, at: 0)
        persist()
        return notebook.id
    }

    /// Imports every readable PDF and keeps the successful imports if one file fails.
    func importPDFs(from sourceURLs: [URL]) -> (imported: Int, skipped: [String]) {
        var imported = 0
        var skipped: [String] = []

        for sourceURL in sourceURLs {
            do {
                _ = try importPDF(from: sourceURL)
                imported += 1
            } catch {
                skipped.append(sourceURL.deletingPathExtension().lastPathComponent)
            }
        }

        return (imported, skipped)
    }

    func exportNotebookPDF(id: UUID) throws -> URL {
        guard let notebook = notebook(id: id) else { throw ImportError.notebookMissing }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let originalPDF = pdfURL(named: notebook.pdfFileName).flatMap { PDFDocument(url: $0) }
        let data = renderer.pdfData { context in
            for (pageIndex, page) in notebook.pages.enumerated() {
                let aspect = max(CGFloat(page.aspectRatio), 0.45)
                let pageRect = CGRect(x: 0, y: 0, width: 612, height: 612 / aspect)
                context.beginPage(withBounds: pageRect, pageInfo: [:])
                UIColor.white.setFill()
                context.fill(pageRect)

                if let originalPage = originalPDF?.page(at: pageIndex) {
                    originalPage.draw(with: .cropBox, to: context.cgContext)
                } else if let background = backgroundImage(named: page.backgroundImageName) {
                    background.draw(in: pageRect)
                } else {
                    drawTemplate(page.template, in: pageRect)
                }

                if !page.drawingData.isEmpty,
                   let drawing = try? PKDrawing(data: page.drawingData) {
                    let drawingImage = drawing.image(
                        from: CGRect(x: 0, y: 0, width: CGFloat(page.canvasWidth), height: CGFloat(page.canvasHeight)),
                        scale: pageRect.width / CGFloat(page.canvasWidth)
                    )
                    drawingImage.draw(in: pageRect)
                }
            }
        }

        let safeName = notebook.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent("\(safeName).pdf")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func drawTemplate(_ template: PageTemplate, in rect: CGRect) {
        guard template == .ruled || template == .grid else { return }
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setStrokeColor(UIColor(red: 0.78, green: 0.84, blue: 0.93, alpha: 1).cgColor)
        context?.setLineWidth(0.5)
        if template == .ruled {
            stride(from: 48.0, to: rect.height, by: 28.0).forEach { y in
                context?.move(to: CGPoint(x: 24, y: y))
                context?.addLine(to: CGPoint(x: rect.width - 24, y: y))
            }
        } else {
            stride(from: 24.0, to: rect.width, by: 24.0).forEach { x in
                context?.move(to: CGPoint(x: x, y: 0))
                context?.addLine(to: CGPoint(x: x, y: rect.height))
            }
            stride(from: 24.0, to: rect.height, by: 24.0).forEach { y in
                context?.move(to: CGPoint(x: 0, y: y))
                context?.addLine(to: CGPoint(x: rect.width, y: y))
            }
        }
        context?.strokePath()
        context?.restoreGState()
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL),
              let saved = try? JSONDecoder().decode([Notebook].self, from: data) else { return }
        notebooks = saved.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notebooks) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    enum ImportError: LocalizedError {
        case unreadablePDF
        case notebookMissing

        var errorDescription: String? {
            switch self {
            case .unreadablePDF: return "This PDF could not be opened or contains no pages."
            case .notebookMissing: return "This notebook is no longer available."
            }
        }
    }
}
