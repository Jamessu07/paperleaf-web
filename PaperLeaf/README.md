# PaperLeaf for iPad

## Web version

The `preview/index.html` file is now a browser-first PaperLeaf MVP. It can import multiple PDFs at once, search the library, open PDFs in a reader view, and keep imported files in the current browser using IndexedDB. It is designed for static hosting and works on iPad Safari, desktop browsers, and tablets.

This first web version is not cloud sync yet: documents remain in the browser where they were imported. Add authentication plus object storage when the same library needs to follow a user across devices.

PaperLeaf is an original, offline-first iPad note-taking starter app for handwriting, highlighting, and PDF books. It uses Apple's PencilKit for writing tools and PDFKit for PDF import. It does not use Goodnotes code, branding, or account services.

## Included in this starter

- Local notebook library with ruled, grid, and blank pages
- Apple Pencil or touch handwriting, colored pen, translucent highlighter, and vector eraser
- Import one or many PDF books at once as local notebooks while preserving the original PDF text and page quality
- Search your local notebook library by title
- PDF pinch zoom, continuous page reading, PDF text search/selection, and PencilKit markups
- Local autosave inside the app's Documents folder
- PDF export through the iPad share sheet

Imported PDFs are copied into the app's local Documents area; PencilKit drawings are saved per page in the local library file. The app does not sync these changes to other devices. Export a marked-up copy through the share sheet. Keep a backup of important PDFs; deleting the app removes its local copies and markups unless you exported them.

This starter imports PDF files; EPUB books are not supported yet. PDF text search depends on the source PDF containing a text layer, so scanned pages without OCR remain image-only.

There is no built-in three-PDF cap: each imported PDF is stored as its own local notebook in the app's Documents folder. If a multi-file import contains one unreadable file, the readable files are kept and the skipped names are reported.

## Open and run on your iPad

1. On a Mac, install Xcode and unzip this project.
2. Open `PaperLeaf.xcodeproj`.
3. Connect the iPad to the Mac, unlock it, and trust the computer if prompted.
4. In Xcode, select the `PaperLeaf` scheme and your iPad as the run destination.
5. In **Signing & Capabilities**, select your Apple Account under **Team**. Change the bundle identifier if Xcode asks for a unique one.
6. Press **Run**. If iPadOS asks, enable Developer Mode and restart the iPad.

A free Apple Account is enough for personal device testing through Xcode. A free provisioning profile expires after seven days, so Xcode may need to reinstall the app periodically. You do not need an internet connection to use the notebooks after installation.

If you do not have a Mac, the source can still be edited on Windows. To install this native SwiftUI app on an iPad, use Swift Playgrounds on the iPad if the project is adapted into a Playground app, or use access to a Mac/cloud Mac to open the Xcode project and sign it. This starter itself is an Xcode project and cannot be compiled or signed by Windows alone.

## Next feature candidates

Handwriting search, bookmarks, folders, and multi-device sync are not included yet. This starter does not include AI features, subscriptions, or accounts.
