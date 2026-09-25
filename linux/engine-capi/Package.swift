// swift-tools-version: 5.9
// libtelexcore — the TelexCore engine exported through a C ABI for the Linux
// frontends (Fcitx5 addon, IBus engine). See linux/docs/LINUX-SPEC.md §2.
//
// Sources/TelexCoreEngine holds SYMLINKS to ../../TelexCore/Sources/TelexCore/*.swift
// (every file except ClientPolicy.swift, the only one importing Foundation), so the
// Linux library compiles the exact engine the Mac/iOS apps ship — no fork, no copy —
// and stays Foundation-free (small, self-contained .so with --static-swift-stdlib).
// `scripts/check-engine-links.sh` fails the build when TelexCore gains a file that is
// not linked here.
//
// Build (Linux):  swift build -c release --static-swift-stdlib
//   → .build/release/libtelexcore.so   (C header: include/telexcore.h)
import PackageDescription

let package = Package(
    name: "TelexCoreCAPI",
    products: [
        .library(name: "telexcore", type: .dynamic, targets: ["TelexCoreC"]),
    ],
    targets: [
        .target(
            name: "TelexCoreEngine",
            path: "Sources/TelexCoreEngine"
        ),
        .target(
            name: "TelexCoreC",
            dependencies: ["TelexCoreEngine"],
            path: "Sources/TelexCoreC",
            linkerSettings: [
                // Export only the vt_* C ABI from the .so (Swift runtime stays private).
                .unsafeFlags(["-Xlinker", "--version-script=\(Context.packageDirectory)/exports.map"],
                             .when(platforms: [.linux])),
            ]
        ),
    ]
)
