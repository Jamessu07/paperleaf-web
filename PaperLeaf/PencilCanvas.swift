import PencilKit
import SwiftUI

struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let tool: PKTool
    let drawingPolicy: PKCanvasViewDrawingPolicy

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = drawingPolicy
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.tool = tool
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let currentData = canvas.drawing.dataRepresentation()
        let bindingData = drawing.dataRepresentation()
        if currentData != bindingData { canvas.drawing = drawing }
        canvas.tool = tool
        canvas.drawingPolicy = drawingPolicy
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        init(_ parent: PencilCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
