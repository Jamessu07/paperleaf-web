import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: NotebookStore
    @State private var isImportingPDF = false
    @State private var searchText = ""
    @State private var importMessage: String?
    @State private var showingImportError = false

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 18)]

    private var filteredNotebooks: [Notebook] {
        guard !searchText.isEmpty else { return store.notebooks }
        return store.notebooks.filter { $0.title.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    welcomeCard

                    HStack(alignment: .firstTextBaseline) {
                        Text("My notebooks")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        Spacer()
                        Text("\(filteredNotebooks.count) item\(filteredNotebooks.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if store.notebooks.isEmpty {
                        emptyState
                    } else if filteredNotebooks.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(filteredNotebooks) { notebook in
                                NavigationLink(value: notebook.id) {
                                    NotebookCard(notebook: notebook)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1050)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("PaperLeaf")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search notebooks")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isImportingPDF = true
                    } label: {
                        Label("Import PDFs", systemImage: "doc.badge.plus")
                    }
                    Button {
                        _ = store.createNotebook()
                    } label: {
                        Label("New notebook", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationDestination(for: UUID.self) { notebookID in
                if store.notebook(id: notebookID)?.pdfFileName != nil {
                    PDFBookEditor(notebookID: notebookID)
                } else {
                    NotebookEditor(notebookID: notebookID)
                }
            }
            .fileImporter(
                isPresented: $isImportingPDF,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                do {
                    let urls = try result.get()
                    let summary = store.importPDFs(from: urls)
                    if !summary.skipped.isEmpty {
                        let names = summary.skipped.joined(separator: ", ")
                        importMessage = summary.imported > 0
                            ? "Imported \(summary.imported) PDF\(summary.imported == 1 ? "" : "s"). Skipped: \(names)."
                            : "No PDFs were imported. Skipped: \(names)."
                        showingImportError = true
                    }
                } catch {
                    importMessage = error.localizedDescription
                    showingImportError = true
                }
            }
            .alert("Could not import PDF", isPresented: $showingImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importMessage ?? "Please try another PDF.")
            }
        }
    }

    private var welcomeCard: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.17))
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 42, weight: .medium))
            }
            .frame(width: 82, height: 82)

            VStack(alignment: .leading, spacing: 8) {
                Text("A calmer place for your notes")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Write, organize, and mark up PDFs. Your notebooks stay on this iPad.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [Color(red: 0.20, green: 0.32, blue: 0.69), Color(red: 0.38, green: 0.52, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Your library is ready")
                .font(.headline)
            Text("Create a notebook or import a PDF to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("New notebook", systemImage: "plus") { _ = store.createNotebook() }
                    .buttonStyle(.borderedProminent)
                Button("Import PDFs", systemImage: "doc.badge.plus") { isImportingPDF = true }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct NotebookCard: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Color(red: 0.96, green: 0.97, blue: 1), Color(red: 0.88, green: 0.91, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.12))
                            .frame(height: 2)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color(red: 0.25, green: 0.39, blue: 0.75))
                    .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
            }
            .frame(height: 165)

            VStack(alignment: .leading, spacing: 5) {
                Text(notebook.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s")  ·  \(notebook.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }
}
