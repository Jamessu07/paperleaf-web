import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct PDFBookEditor: View {
    @EnvironmentObject private var store: NotebookStore
    let notebookID: UUID

    @State private var selectedTool: BookTool = .pen
    @State private var inkColor: BookInkColor = .black
    @State private var fingerDrawingEnabled = false
    @State private var shareItem: BookShareItem?
    @State private var exportError: String?
    @State private var showingExportError = false

    private var notebook: Notebook? { store.notebook(id: notebookID) }
    private var activeTool: PKTool {
        switch selectedTool {
        case .pen: return PKInkingTool(.pen, color: inkColor.uiColor, width: 3)
        case .highlighter: return PKInkingTool(.marker, color: inkColor.uiColor.withAlphaComponent(0.38), width: 22)
        case .eraser: return PKEraserTool(.vector)
        }
    }

    var body: some View {
        Group {
            if let notebook, let url = store.pdfURL(named: notebook.pdfFileName) {
                PDFNotebookView(
                    url: url,
                    store: store,
                    notebookID: notebookID,
                    tool: activeTool,
                    drawingPolicy: fingerDrawingEnabled ? .anyInput : .pencilOnly
                )
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            ForEach(BookTool.allCases) { tool in
                                Button {
                                    selectedTool = tool
                                    if tool == .highlighter { inkColor = .yellow }
                                } label: {
                                    Label(tool.title, systemImage: tool.icon)
                                }
                            }
                        } label: {
                            Image(systemName: selectedTool.icon)
                                .foregroundStyle(selectedTool == .highlighter ? Color.yellow : (selectedTool == .eraser ? Color.accentColor : Color.primary))
                                .accessibilityLabel("Writing tool: \(selectedTool.title)")
                        }

                        Menu {
                            ForEach(BookInkColor.allCases) { color in
                                Button {
                                    inkColor = color
                                    if selectedTool == .eraser { selectedTool = .pen }
                                } label: {
                                    Label(color.title, systemImage: color == inkColor ? "checkmark.circle.fill" : "circle.fill")
                                }
                            }
                        } label: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(inkColor.swiftUIColor)
                                .accessibilityLabel("Ink or highlight color")
                        }

                        Button {
                            fingerDrawingEnabled.toggle()
                        } label: {
                            Image(systemName: fingerDrawingEnabled ? "hand.draw.fill" : "hand.draw")
                                .foregroundStyle(fingerDrawingEnabled ? Color.accentColor : Color.primary)
                        }
                        .accessibilityLabel(fingerDrawingEnabled ? "Finger drawing on" : "Finger drawing off")

                        Button { exportPDF() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Export marked-up PDF")
                    }
                }
                .sheet(item: $shareItem) { item in
                    BookShareSheet(items: [item.url])
                }
                .alert("Could not export PDF", isPresented: $showingExportError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(exportError ?? "Please try again.")
                }
            } else {
                ContentUnavailableView("PDF unavailable", systemImage: "doc.richtext", description: Text("Import the PDF again from your library."))
            }
        }
    }

    private func exportPDF() {
        do { shareItem = BookShareItem(url: try store.exportNotebookPDF(id: notebookID)) }
        catch {
            exportError = error.localizedDescription
            showingExportError = true
        }
    }
}

private struct PDFNotebookView: UIViewRepresentable {
    let url: URL
    let store: NotebookStore
    let notebookID: UUID
    let tool: PKTool
    let drawingPolicy: PKCanvasViewDrawingPolicy

    func makeCoordinator() -> OverlayCoordinator {
        OverlayCoordinator(store: store, notebookID: notebookID, tool: tool, drawingPolicy: drawingPolicy)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displayBox = .cropBox
        pdfView.autoScales = true
        pdfView.pageShadowsEnabled = true
        pdfView.backgroundColor = UIColor.secondarySystemGroupedBackground
        pdfView.pageOverlayViewProvider = context.coordinator
        if #available(iOS 16.0, *) { pdfView.isFindInteractionEnabled = true }
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.update(tool: tool, drawingPolicy: drawingPolicy)
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: OverlayCoordinator) {
        coordinator.flush()
    }

    final class OverlayCoordinator: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate {
        private let store: NotebookStore
        private let notebookID: UUID
        private var tool: PKTool
        private var drawingPolicy: PKCanvasViewDrawingPolicy
        private var canvases: [Int: PKCanvasView] = [:]
        private var pageByCanvas: [ObjectIdentifier: Int] = [:]
        private var saveTasks: [Int: Task<Void, Never>] = [:]

        init(store: NotebookStore, notebookID: UUID, tool: PKTool, drawingPolicy: PKCanvasViewDrawingPolicy) {
            self.store = store
            self.notebookID = notebookID
            self.tool = tool
            self.drawingPolicy = drawingPolicy
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let document = view.document else { return nil }
            let pageIndex = document.index(for: page)
            guard (0..<document.pageCount).contains(pageIndex) else { return nil }
            if let canvas = canvases[pageIndex] { return canvas }

            let canvas = PKCanvasView()
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.isScrollEnabled = false
            canvas.drawingPolicy = drawingPolicy
            canvas.tool = tool
            if let pageData = store.notebook(id: notebookID)?.pages[safe: pageIndex]?.drawingData,
               !pageData.isEmpty {
                canvas.drawing = (try? PKDrawing(data: pageData)) ?? PKDrawing()
            }
            canvas.delegate = self
            canvases[pageIndex] = canvas
            pageByCanvas[ObjectIdentifier(canvas)] = pageIndex
            return canvas
        }

        func pdfView(_ view: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let document = view.document else { return }
            let pageIndex = document.index(for: page)
            guard (0..<document.pageCount).contains(pageIndex),
                  let canvas = overlayView as? PKCanvasView else { return }
            save(canvas, pageIndex: pageIndex)
            canvases.removeValue(forKey: pageIndex)
            pageByCanvas.removeValue(forKey: ObjectIdentifier(canvas))
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let pageIndex = pageByCanvas[ObjectIdentifier(canvasView)] else { return }
            scheduleSave(canvasView, pageIndex: pageIndex)
        }

        func update(tool: PKTool, drawingPolicy: PKCanvasViewDrawingPolicy) {
            self.tool = tool
            self.drawingPolicy = drawingPolicy
            for canvas in canvases.values {
                canvas.tool = tool
                canvas.drawingPolicy = drawingPolicy
            }
        }

        func flush() {
            for (pageIndex, canvas) in canvases { save(canvas, pageIndex: pageIndex) }
        }

        private func scheduleSave(_ canvas: PKCanvasView, pageIndex: Int) {
            saveTasks[pageIndex]?.cancel()
            let data = canvas.drawing.dataRepresentation()
            let canvasSize = canvas.bounds.size
            saveTasks[pageIndex] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                store.updateDrawing(data, notebookID: notebookID, pageIndex: pageIndex, canvasSize: canvasSize)
                saveTasks[pageIndex] = nil
            }
        }

        private func save(_ canvas: PKCanvasView, pageIndex: Int) {
            saveTasks[pageIndex]?.cancel()
            saveTasks[pageIndex] = nil
            store.updateDrawing(
                canvas.drawing.dataRepresentation(),
                notebookID: notebookID,
                pageIndex: pageIndex,
                canvasSize: canvas.bounds.size
            )
        }
    }
}

private enum BookTool: String, CaseIterable, Identifiable {
    case pen, highlighter, eraser
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }
}

private enum BookInkColor: String, CaseIterable, Identifiable, Hashable {
    case black, blue, red, green, yellow
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var uiColor: UIColor {
        switch self {
        case .black: return .black
        case .blue: return UIColor(red: 0.14, green: 0.34, blue: 0.82, alpha: 1)
        case .red: return UIColor(red: 0.78, green: 0.20, blue: 0.23, alpha: 1)
        case .green: return UIColor(red: 0.10, green: 0.48, blue: 0.31, alpha: 1)
        case .yellow: return .systemYellow
        }
    }
    var swiftUIColor: Color { Color(uiColor: uiColor) }
}

private struct BookShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BookShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
