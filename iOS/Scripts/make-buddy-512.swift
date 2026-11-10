#!/usr/bin/env swift
// Sinh atlas Bạn đồng hành 512 px (cạnh dài) cho BuddyView iOS: Keyboard/Resources/Buddies/buddy-<id>-v2-512.png.
// Android dùng CHÍNH các tệp này (chép byte-y-hệt vào android/app/src/main/assets/ — test BuddyPreviewSmokeTests).
//
//   swift iOS/Scripts/make-buddy-512.swift        (chạy từ gốc repo)
//
// Nguồn: ảnh gốc độ phân giải đầy đủ trong assets/companion/ (nguồn chuẩn — assets/companion/README.md; byte-y-hệt
// các buddy-<id>-v2.png từng bundle). Bản gốc mèo + gà con không còn bundle ở nền tảng nào (chỉ người nhảy Night
// Club cần bản gốc, mà chỉ cô gái / chàng trai). Thu nhỏ bằng ĐÚNG lệnh ImageIO mà BuddyView từng gọi lúc chạy
// (thumbnail, cạnh dài 512) ⇒ điểm ảnh y như trước, chỉ là làm sẵn lúc build thay vì giải trọn PNG 1536 px
// trên máy người dùng mỗi lần mở bàn phím. Đổi ảnh gốc ⇒ chạy lại script này rồi chép sang Android.
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sources = ["boy": "boy-v2-alpha.png", "cat": "cat-v2-source.png", "chick": "chick-v2-source.png",
               "girl": "girl-eight-source.png"]
let edge = 512
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let src = root.appendingPathComponent("assets/companion")
let dst = root.appendingPathComponent("iOS/Keyboard/Resources/Buddies")

var failed = false
for (id, file) in sources.sorted(by: { $0.key < $1.key }) {
    let input = src.appendingPathComponent(file)
    let output = dst.appendingPathComponent("buddy-\(id)-v2-512.png")
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary),
          let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write("lỗi: \(input.path)\n".data(using: .utf8)!)
        failed = true
        continue
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write("lỗi ghi: \(output.path)\n".data(using: .utf8)!)
        failed = true
        continue
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
    print("\(output.lastPathComponent): \(image.width)×\(image.height), \(size) B")
}
exit(failed ? 1 : 0)
