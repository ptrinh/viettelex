// gen-english-frequency — bước 1 của Scripts/gen-english-frequency.py (bảng EnglishFrequency).
//
// Gõ từng từ của enlexicon.bin bằng Telex với cấu hình MẶC ĐỊNH của app (bỏ dấu tự do, kiểm tra
// chính tả, khôi phục sớm, ngữ cảnh tiếng Anh, collision ưu tiên tiếng Việt, teencode tắt), từ
// đứng một mình, rồi in ra stdout một dòng / từ:
//
//   <từ>\t<composed trước khi chốt>\t<chữ chốt ra>\t<1 nếu composed là âm tiết Việt hợp lệ, 0 nếu không>
//
// Script Python đọc dòng này, tra tần suất âm tiết (vnlexicon.bin) theo khoá Telex của composed và
// sinh TelexCore/Sources/TelexCore/EnglishFrequency.swift. Đừng chạy tay — chạy script.
import Foundation
import TelexCore

let args = CommandLine.arguments
guard args.count >= 2, let blob = FileManager.default.contents(atPath: args[1]) else {
    FileHandle.standardError.write("usage: gen-english-frequency <enlexicon.bin>\n".data(using: .utf8)!)
    exit(1)
}
let bytes = [UInt8](blob)
guard bytes.count > 8, bytes[0..<4] == [0x56, 0x54, 0x45, 0x31] else {
    FileHandle.standardError.write("not an enlexicon (VTE1) file\n".data(using: .utf8)!)
    exit(1)
}
let total = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
var out = ""
var p = 8
for _ in 0..<total {
    let len = Int(bytes[p]); p += 2
    let w = String(decoding: bytes[p..<(p + len)], as: UTF8.self)
    p += len
    guard w.utf8.allSatisfy({ $0 >= 0x61 && $0 <= 0x7A }) else { continue }
    var e = TelexEngine()
    e.freeMarking = true
    e.liveSpellCheck = true
    e.eagerEnglishRestore = true
    e.teencode = false
    e.contextualEnglish = true
    e.collisionPrefersVietnamese = true
    for ch in w { _ = e.feed(ch) }
    let composed = e.composed
    let valid = SyllableValidator.isValidSyllable(composed.lowercased(), teencode: false)
    let committed = e.commitText(autoRestore: true)
    out += "\(w)\t\(composed)\t\(committed)\t\(valid ? 1 : 0)\n"
}
FileHandle.standardOutput.write(out.data(using: .utf8)!)
