import Foundation

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("anyconvert-folder-test-\(UUID().uuidString)")
try fm.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
try fm.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
try fm.createDirectory(at: root.appendingPathComponent("Example.app/Contents"), withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let files = ["letter.DOCX", "report.pdf", "notes.md", "data.csv", "record.json", "slides.pptx", "photo.nef", "art.svg", "nested/table.xlsx", ".hidden/secret.docx", "Example.app/Contents/ignored.pdf", "unrelated.xyz"]
for file in files { try Data("test".utf8).write(to: root.appendingPathComponent(file)) }
let found = Set(FileUtilities.expand(urls: [root]).map { $0.lastPathComponent })
let expected = Set(["letter.DOCX", "report.pdf", "notes.md", "data.csv", "record.json", "slides.pptx", "photo.nef", "art.svg", "table.xlsx"])
guard found == expected else { fputs("Folder scan mismatch: \(found)\n", stderr); exit(1) }
let direct = FileUtilities.expand(urls: [root.appendingPathComponent("unrelated.xyz")])
guard direct.count == 1 else { fputs("Direct file behavior changed\n", stderr); exit(1) }
print("PASS folder scanning: documents, media, nesting, hidden and app packages")
