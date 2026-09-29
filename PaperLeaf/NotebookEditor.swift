import PencilKit
import SwiftUI
import UIKit

struct NotebookEditor: View {
    @EnvironmentObject private var store: NotebookStore
    let notebookID: UUID

    @State private var pageIndex = 0
    @State private var drawing = PKDrawing()
    @State private var inkColor: InkColor = .black
    @State private var selectedTool: WritingTool = .pen
    @State private var currentCanvasSize = CGSize(width: 900, height: 1273)
    @State private var saveTask: Task<Void, Never>?
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var showingExportError = false

    private var notebook: Notebook? { store.notebook(id: notebookID) }
    private var pages: [NotePage] { notebook?.pages ?? [] }

    var body: some View {
        Group {
            if let notebook, pages.indices.contains(pageIndex) {
                GeometryReader { geometry in
                    let page = pages[pageIndex]
                    let aspect = max(CGFloat(page.aspectRatio), 0.45)
                    let availableWidth = geometry.size.width - 40
                    let availableHeight = geometry.size.height - 92
                    let paperWidth = min(availableWidth, availableHeight * aspect)
                    let paperHeight = paperWidth / aspect

                    VStack(spacing: 14) {
                        HStack {
                            Label(page.backgroundImageName == nil ? page.template.rawValue : "Imported PDF", systemImage: page.backgroundImageName == nil ? "doc.text" : "doc.richtext")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Page \(pageIndex + 1) of \(pages.count)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: min(availableWidth, 900))

                        ZStack {
                            PaperBackground(page: page, store: store)
                            PencilCanvas(drawing: $drawing, tool: activeTool)
                        }
                        .frame(width: paperWidth, height: paperHeight)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.17), radius: 14, y: 5)
                        .onAppear { currentCanvasSize = CGSize(width: paperWidth, height: paperHeight) }
                        .onChange(of: geometry.size) { _, _ in
                            currentCanvasSize = CGSize(width: paperWidth, height: paperHeight)
                        }
                        .onChange(of: pageIndex) { _, _ in
                            currentCanvasSize = CGSize(width: paperWidth, height: paperHeight)
                        }

                        HStack(spacing: 22) {
                            Button { movePage(to: pageIndex - 1) } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(pageIndex == 0)
                            Text("\(pageIndex + 1) / \(pages.count)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Button { movePage(to: pageIndex + 1) } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(pageIndex + 1 >= pages.count)
                            Spacer()
                            Button {
                                store.addPage(to: notebook.id)
                                movePage(to: pages.count - 1)
                            } label: {
                                Label("Add page", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: min(availableWidth, 900))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 12)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            ForEach(WritingTool.allCases) { tool in
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
                            ForEach(InkColor.allCases) { color in
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

                        Menu {
                            ForEach([PageTemplate.ruled, .grid, .blank], id: \.self) { template in
                                Button(template.rawValue) {
                                    store.updateTemplate(template, notebookID: notebookID, pageIndex: pageIndex)
                                }
                            }
                        } label: {
                            Image(systemName: "rectangle.on.rectangle")
                        }
                        .disabled(page.backgroundImageName != nil)

                        Button {
                            exportPDF()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Export notebook as PDF")
                    }
                }
                .onAppear { loadPage(pageIndex) }
                .onChange(of: drawing.dataRepresentation()) { _, data in
                    scheduleSave(data, page: pageIndex)
                }
                .onDisappear {
                    saveTask?.cancel()
                    store.updateDrawing(drawing.dataRepresentation(), notebookID: notebookID, pageIndex: pageIndex, canvasSize: currentCanvasSize)
                }
                .sheet(item: $shareItem) { item in
                    ShareSheet(items: [item.url])
                }
                .alert("Could not export notebook", isPresented: $showingExportError) {
                    Button("OK", role: .cancel) { }
                } message: { Text(exportError ?? "Please try again.") }
            } else {
                ContentUnavailableView("Notebook unavailable", systemImage: "book.closed", description: Text("Return to the library and open a notebook again."))
            }
        }
    }

    private var activeTool: PKTool {
        switch selectedTool {
        case .pen:
            return PKInkingTool(.pen, color: inkColor.uiColor, width: 3)
        case .highlighter:
            return PKInkingTool(.marker, color: inkColor.uiColor.withAlphaComponent(0.38), width: 22)
        case .eraser:
            return PKEraserTool(.vector)
        }
    }

    private func loadPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        let data = pages[index].drawingData
        drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
    }

    private func movePage(to index: Int) {
        guard pages.indices.contains(index) else { return }
        saveTask?.cancel()
        store.updateDrawing(drawing.dataRepresentation(), notebookID: notebookID, pageIndex: pageIndex, canvasSize: currentCanvasSize)
        pageIndex = index
        loadPage(index)
    }

    private func scheduleSave(_ data: Data, page: Int) {
        saveTask?.cancel()
        let canvasSize = currentCanvasSize
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            store.updateDrawing(data, notebookID: notebookID, pageIndex: page, canvasSize: canvasSize)
        }
    }

    private func exportPDF() {
        do { shareItem = ShareItem(url: try store.exportNotebookPDF(id: notebookID)) }
        catch {
            exportError = error.localizedDescription
            showingExportError = true
        }
    }
}

private struct PaperBackground: View {
    let page: NotePage
    @ObservedObject var store: NotebookStore

    var body: some View {
        GeometryReader { geometry in
            if let image = store.backgroundImage(named: page.backgroundImageName) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ZStack {
                    Color.white
                    Canvas { context, size in
                        let lineColor = Color(red: 0.82, green: 0.87, blue: 0.95)
                        if page.template == .ruled {
                            for y in stride(from: 30.0, through: size.height, by: 28.0) {
                                var path = Path()
                                path.move(to: CGPoint(x: 20, y: y))
                                path.addLine(to: CGPoint(x: size.width - 20, y: y))
                                context.stroke(path, with: .color(lineColor), lineWidth: 0.7)
                            }
                        } else if page.template == .grid {
                            for x in stride(from: 24.0, through: size.width, by: 24.0) {
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(path, with: .color(lineColor), lineWidth: 0.55)
                            }
                            for y in stride(from: 24.0, through: size.height, by: 24.0) {
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(lineColor), lineWidth: 0.55)
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private enum WritingTool: String, CaseIterable, Identifiable {
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

private enum InkColor: String, CaseIterable, Identifiable, Hashable {
    case black, blue, red, green, yellow
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var uiColor: UIColor {
        switch self {
        case .black: return .black
        case .blue: return UIColor(red: 0.14, green: 0.34, blue: 0.82, alpha: 1)
        case .red: return UIColor(red: 0.78, green: 0.20, blue: 0.23, alpha: 1)
        case .green: return UIColor(red: 0.10, green: 0.48, blue: 0.31, alpha: 1)
        case .yellow: return UIColor.systemYellow
        }
    }
    var swiftUIColor: Color { Color(uiColor: uiColor) }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
