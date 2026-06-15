/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Compression
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension Array where Element: BinaryFloatingPoint {
    /// The average value of all the items in the array
    var average: Double {
        if self.isEmpty {
            return 0.0
        }
        let sum = self.reduce(0, +)
        return Double(sum) / Double(self.count)
    }
}

extension String {
    func split(by length: Int) -> [String] {
        var startIndex = self.startIndex
        var results = [Substring]()

        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex ..< endIndex])
            startIndex = endIndex
        }

        return results.map { String($0) }
    }
    
    func trimmed(maxLength: inout Int) -> String {
        let utf8Count = utf8.count
        if utf8Count <= maxLength {
            maxLength -= utf8Count
            return self
        } else {
            defer { maxLength = 0 }
            return String(bytes: utf8.prefix(maxLength), encoding: .utf8)!
        }
    }

    var separatedByWords: String {
        enum My {
            static let regex = try! NSRegularExpression(pattern: "([A-Z]+)[a-zA-Z]|(?<=_).")
        }

        return My.regex.stringByReplacingMatches(in: self, range: NSRange(0 ..< self.utf16.count), withTemplate: " $0").trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    func contains(exactWord: String) -> Bool {
        return self.range(of: "\\b\(exactWord)\\b", options: .regularExpression) != nil
    }

    var isHexNumber: Bool {
        filter(\.isHexDigit).count == count
    }
}

extension Data {
    func zlibDecompress(expectedSize: Int? = nil) -> Data {
        let size = expectedSize ?? (count * 30) // zlib compresses 3-5 times normally
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size) { buffer in
            self.subdata(in: 2 ..< self.count).withUnsafeBytes {
                let read = compression_decode_buffer(buffer.baseAddress!, buffer.count,
                                                     $0.baseAddress!, $0.count, nil, COMPRESSION_ZLIB)
                return Data(buffer[..<read])
            }
        }
    }
    
    init?(hex: String) {
        let utf8 = hex.utf8
        guard utf8.count % 2 == 0 else { return nil }
        let prefix = hex.hasPrefix("0x") ? 2 : 0
        var result = Data()
        result.reserveCapacity((utf8.count - prefix) / 2)
        var current: UInt8? = nil
        for char in utf8.suffix(from: utf8.index(utf8.startIndex, offsetBy: prefix)) {
            let v: UInt8
            switch char {
            case let c where c >= 48 && c <= 57: v = c - 48 // 0-9
            case let c where c >= 65 && c <= 70: v = c - 55 // A-F
            case let c where c >= 97 && c <= 102: v = c - 87 // a-f
            default: return nil
            }
            if let val = current {
                result.append(val << 4 | v)
                current = nil
            } else {
                current = v
            }
        }
        self = result
    }

    func hex(prefix: Bool = false) -> String {
        withUnsafeBytes { data in
            var result = Data()
            result.reserveCapacity(data.count * 2 + (prefix ? 2 : 0))
            if prefix {
                result.append(UInt8(ascii: "0"))
                result.append(UInt8(ascii: "x"))
            }
            Self._hexCharacters.withUnsafeBytes { (hex: UnsafeRawBufferPointer) in
                for byte in data {
                    result.append(hex[Int(byte >> 4)])
                    result.append(hex[Int(byte & 0x0F)])
                }
            }
            return String(bytes: result, encoding: .ascii)!
        }
    }
    
    private static let _hexCharacters = Data("0123456789abcdef".utf8)
}

#if canImport(UIKit) && !os(watchOS)
extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
#endif

extension FileHandle {
    fileprivate func fdZero(_ set: inout fd_set) {
        set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    fileprivate func fdSet(_ fd: Int32, set: inout fd_set) {
        let intOffset = Int32(fd / 32)
        let bitOffset = fd % 32
        let mask = Int32(1) << bitOffset
        switch intOffset {
            case 0: set.fds_bits.0 = set.fds_bits.0 | mask
            case 1: set.fds_bits.1 = set.fds_bits.1 | mask
            case 2: set.fds_bits.2 = set.fds_bits.2 | mask
            case 3: set.fds_bits.3 = set.fds_bits.3 | mask
            case 4: set.fds_bits.4 = set.fds_bits.4 | mask
            case 5: set.fds_bits.5 = set.fds_bits.5 | mask
            case 6: set.fds_bits.6 = set.fds_bits.6 | mask
            case 7: set.fds_bits.7 = set.fds_bits.7 | mask
            case 8: set.fds_bits.8 = set.fds_bits.8 | mask
            case 9: set.fds_bits.9 = set.fds_bits.9 | mask
            case 10: set.fds_bits.10 = set.fds_bits.10 | mask
            case 11: set.fds_bits.11 = set.fds_bits.11 | mask
            case 12: set.fds_bits.12 = set.fds_bits.12 | mask
            case 13: set.fds_bits.13 = set.fds_bits.13 | mask
            case 14: set.fds_bits.14 = set.fds_bits.14 | mask
            case 15: set.fds_bits.15 = set.fds_bits.15 | mask
            case 16: set.fds_bits.16 = set.fds_bits.16 | mask
            case 17: set.fds_bits.17 = set.fds_bits.17 | mask
            case 18: set.fds_bits.18 = set.fds_bits.18 | mask
            case 19: set.fds_bits.19 = set.fds_bits.19 | mask
            case 20: set.fds_bits.20 = set.fds_bits.20 | mask
            case 21: set.fds_bits.21 = set.fds_bits.21 | mask
            case 22: set.fds_bits.22 = set.fds_bits.22 | mask
            case 23: set.fds_bits.23 = set.fds_bits.23 | mask
            case 24: set.fds_bits.24 = set.fds_bits.24 | mask
            case 25: set.fds_bits.25 = set.fds_bits.25 | mask
            case 26: set.fds_bits.26 = set.fds_bits.26 | mask
            case 27: set.fds_bits.27 = set.fds_bits.27 | mask
            case 28: set.fds_bits.28 = set.fds_bits.28 | mask
            case 29: set.fds_bits.29 = set.fds_bits.29 | mask
            case 30: set.fds_bits.30 = set.fds_bits.30 | mask
            case 31: set.fds_bits.31 = set.fds_bits.31 | mask
            default: break
        }
    }

    fileprivate func fdIsSet(_ fd: Int32, set: inout fd_set) -> Bool {
        let intOffset = Int(fd / 32)
        let bitOffset = fd % 32
        let mask = Int32(1) << bitOffset
        switch intOffset {
            case 0: return set.fds_bits.0 & mask != 0
            case 1: return set.fds_bits.1 & mask != 0
            case 2: return set.fds_bits.2 & mask != 0
            case 3: return set.fds_bits.3 & mask != 0
            case 4: return set.fds_bits.4 & mask != 0
            case 5: return set.fds_bits.5 & mask != 0
            case 6: return set.fds_bits.6 & mask != 0
            case 7: return set.fds_bits.7 & mask != 0
            case 8: return set.fds_bits.8 & mask != 0
            case 9: return set.fds_bits.9 & mask != 0
            case 10: return set.fds_bits.10 & mask != 0
            case 11: return set.fds_bits.11 & mask != 0
            case 12: return set.fds_bits.12 & mask != 0
            case 13: return set.fds_bits.13 & mask != 0
            case 14: return set.fds_bits.14 & mask != 0
            case 15: return set.fds_bits.15 & mask != 0
            case 16: return set.fds_bits.16 & mask != 0
            case 17: return set.fds_bits.17 & mask != 0
            case 18: return set.fds_bits.18 & mask != 0
            case 19: return set.fds_bits.19 & mask != 0
            case 20: return set.fds_bits.20 & mask != 0
            case 21: return set.fds_bits.21 & mask != 0
            case 22: return set.fds_bits.22 & mask != 0
            case 23: return set.fds_bits.23 & mask != 0
            case 24: return set.fds_bits.24 & mask != 0
            case 25: return set.fds_bits.25 & mask != 0
            case 26: return set.fds_bits.26 & mask != 0
            case 27: return set.fds_bits.27 & mask != 0
            case 28: return set.fds_bits.28 & mask != 0
            case 29: return set.fds_bits.29 & mask != 0
            case 30: return set.fds_bits.30 & mask != 0
            case 31: return set.fds_bits.31 & mask != 0
            default: return false
        }
    }

    var isReadable: Bool {
        var fdset = fd_set()
        fdZero(&fdset)
        fdSet(fileDescriptor, set: &fdset)
        var tmout = timeval()
        let status = select(fileDescriptor + 1, &fdset, nil, nil, &tmout)

        let actualResult = status > 0 ? fdIsSet(fileDescriptor, set: &fdset) : false

        return actualResult
    }
}

private func djb2Hash(_ string: String) -> Int {
    let unicodeScalars = string.unicodeScalars.map { $0.value }
    return unicodeScalars.reduce(5381) {
        ($0 << 5) &+ $0 &+ Int($1)
    }
}

extension Dictionary where Key == String, Value == String {
    var stableHash: Int {
        let concatenatedString = self.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let hashedData = djb2Hash(concatenatedString)
        return hashedData
    }
}

extension Bundle {
    @inlinable
    var name: String {
        bundleURL.deletingPathExtension().lastPathComponent
    }
    
    @inlinable
    var version: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    @inlinable
    static var testBundle: Bundle? {
        Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }
    }
    
    static var sdk: Bundle { Bundle(for: DDTestMonitor.self) }

    /// Value-type view of a bundle, so the product-under-test selection policy
    /// can be unit-tested without live `Bundle` objects.
    struct UnderTestInfo: Equatable {
        /// Standardized path of the bundle's parent directory.
        let directory: String
        /// Standardized path of the bundle itself.
        let path: String
        let identifier: String?
        let name: String
        let version: String?

        init(directory: String, path: String, identifier: String?, name: String, version: String?) {
            self.directory = directory
            self.path = path
            self.identifier = identifier
            self.name = name
            self.version = version
        }

        init(bundle: Bundle) {
            let url = bundle.bundleURL.standardizedFileURL
            self.init(directory: url.deletingLastPathComponent().path,
                      path: url.path,
                      identifier: bundle.bundleIdentifier,
                      name: bundle.name,
                      version: bundle.version)
        }
    }

    /// Resolves the `(name, version)` describing the product being tested.
    ///
    /// The process `main` bundle is only the product when tests are hosted by a
    /// real app (unit tests injected into the app, or UI tests running in it);
    /// otherwise it is the bare `xctest` runner and carries no useful version.
    ///
    /// The product *name* is always taken from the resolved bundle; only the
    /// version honors `versionOverride` (the `DD_VERSION` escape hatch), since
    /// that is the value users most often need to correct.
    ///
    /// Version resolution order — validated against macOS, simulator and device builds:
    ///  0. `versionOverride` (e.g. `DD_VERSION`), when set, wins outright. It is
    ///     the only reliable answer for statically-linked products (see step 3).
    ///  1. `main` is an `.app` → the app *is* the product.
    ///  2. Host-less `.xctest`: a dynamically-linked product framework is copied
    ///     next to the `.xctest` bundle (sibling — including on device, where the
    ///     whole test root is uploaded) or, in some layouts, embedded inside it.
    ///     Match the one named after the scheme and report its version.
    ///  3. Fall back to the `.xctest` bundle itself. Statically-linked products
    ///     (static frameworks, SPM source targets) are merged into the test binary
    ///     and expose no separate framework here; the xctest version is the best
    ///     available (and is frequently unset, e.g. for SPM).
    static func productUnderTest(
        main: UnderTestInfo,
        test: UnderTestInfo?,
        frameworks: [UnderTestInfo],
        schemeName: String?,
        versionOverride: String? = nil
    ) -> (name: String, version: String) {
        let pick: UnderTestInfo
        if main.path.hasSuffix(".app") {
            pick = main
        } else if let test = test, let schemeName = schemeName,
                  let framework = frameworks.first(where: {
                      $0.name == schemeName &&
                      ($0.directory == test.directory || $0.path.hasPrefix(test.path + "/"))
                  })
        {
            pick = framework
        } else {
            pick = test ?? main
        }
        // Version priority: explicit override → the resolved bundle's own version
        // → the `.xctest` bundle version (when the product version can't be
        // determined, e.g. a matched-but-versionless or statically-linked product)
        // → unknown.
        let name = pick.identifier ?? pick.name
        let version = versionOverride ?? pick.version ?? test?.version ?? "<unknown>"
        return (name, version)
    }

    /// Wires the live process bundles into `productUnderTest(main:test:frameworks:schemeName:versionOverride:)`.
    static func productUnderTest(schemeName: String?, versionOverride: String? = nil) -> (name: String, version: String) {
        let test = Bundle.testBundle
        // When the version is supplied explicitly there is nothing to discover —
        // skip enumerating loaded frameworks and probing the disk entirely.
        var frameworks: [UnderTestInfo] = []
        if versionOverride == nil, let schemeName = schemeName {
            // Loaded (dynamically-linked) frameworks matching the scheme. Only
            // these need their Info.plist read, so we avoid touching every loaded
            // system framework.
            frameworks += Bundle.allFrameworks
                .filter { $0.name == schemeName }
                .map(UnderTestInfo.init)
            // On-disk `<scheme>.framework` sitting next to the `.xctest` bundle.
            // A statically-linked framework is merged into the test binary and is
            // never loaded into memory, but its bundle still ships in the products
            // folder (reachable at runtime on simulator/macOS) and carries the
            // version in its Info.plist. Listed after the loaded ones so a dynamic
            // framework is always preferred.
            if let test = test {
                let onDiskURL = test.bundleURL.deletingLastPathComponent()
                    .appendingPathComponent("\(schemeName).framework")
                if FileManager.default.fileExists(atPath: onDiskURL.path),
                   let onDisk = Bundle(url: onDiskURL)
                {
                    frameworks.append(UnderTestInfo(bundle: onDisk))
                }
            }
        }
        return productUnderTest(
            main: UnderTestInfo(bundle: .main),
            test: test.map(UnderTestInfo.init),
            frameworks: frameworks,
            schemeName: schemeName,
            versionOverride: versionOverride
        )
    }
}

extension Sequence where Iterator.Element: Hashable {
    @inlinable
    var asSet: Set<Element> { Set(self) }
    
    func unique() -> [Iterator.Element] {
        var seen: Set<Iterator.Element> = []
        return filter { seen.insert($0).inserted }
    }
}

extension Dictionary where Value: AnyObject {
    mutating func get(key: Key, or create: @autoclosure () throws -> Value) rethrows -> Value {
        if let value = self[key] { return value }
        let value = try create()
        self[key] = value
        return value
    }
}

extension Dictionary {
    mutating func get<R>(
        key: Key,
        or create: @autoclosure () throws -> Value,
        _ cb: (inout Value) throws -> R
    ) rethrows -> R {
        var value = try self[key] ?? create()
        let result = try cb(&value)
        self[key] = value
        return result
    }
}

extension FixedWidthInteger {
    func checkedAdd(_ right: Self, max: Self = .max, min: Self = .min) -> Self? {
        let (sum, overflow) = self.addingReportingOverflow(right)
        guard !overflow, sum <= max, sum >= min else { return nil }
        return sum
    }
}
