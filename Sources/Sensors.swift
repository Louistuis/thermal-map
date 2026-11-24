import Foundation
import IOKit

// MARK: - SMC (AppleSMC user client, selector 2)

struct SMCVer { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
struct SMCPLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct SMCKeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var attributes: UInt8 = 0; var p1: UInt8 = 0, p2: UInt8 = 0, p3: UInt8 = 0 }
typealias SMCBytes = (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)
struct SMCParam {
    var key: UInt32 = 0
    var vers = SMCVer()
    var pLimit = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func fourCCString(_ v: UInt32) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "????"
}

final class SMC {
    private var conn: io_connect_t = 0
    struct Key { let code: UInt32; let name: String; let type: String; let size: UInt32 }
    private(set) var tempKeys: [Key] = []
    private(set) var totalKeys = 0

    init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        enumerate()
    }
    deinit { IOServiceClose(conn) }

    private func call(_ input: inout SMCParam) -> SMCParam? {
        var out = SMCParam(); var size = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCParam>.stride, &out, &size)
        return (r == KERN_SUCCESS && out.result == 0) ? out : nil
    }
    private func info(_ k: UInt32) -> SMCKeyInfo? { var p = SMCParam(); p.key = k; p.data8 = 9; return call(&p)?.keyInfo }
    private func raw(_ k: UInt32, size: UInt32) -> [UInt8]? {
        var p = SMCParam(); p.key = k; p.keyInfo.dataSize = size; p.data8 = 5
        guard var o = call(&p) else { return nil }
        return withUnsafeBytes(of: &o.bytes) { Array($0.prefix(Int(size))) }
    }
    private func keyAt(_ i: UInt32) -> UInt32? { var p = SMCParam(); p.data8 = 8; p.data32 = i; return call(&p)?.key }

    private func enumerate() {
        let k = fourCC("#KEY")
        guard let ki = info(k), let b = raw(k, size: ki.dataSize) else { return }
        let n = b.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        totalKeys = Int(n)
        for i in 0..<n {
            guard let code = keyAt(i) else { continue }
            let name = fourCCString(code)
            guard name.hasPrefix("T"), let inf = info(code) else { continue }
            let type = fourCCString(inf.dataType)
            guard ["flt ", "sp78", "ioft", "fp88"].contains(type) else { continue }
            tempKeys.append(Key(code: code, name: name, type: type, size: inf.dataSize))
        }
    }

    func read(_ key: Key) -> Double? {
        guard let b = raw(key.code, size: key.size) else { return nil }
        switch key.type {
        case "flt " where b.count == 4: return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "sp78" where b.count == 2: return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "fp88" where b.count == 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 256
        case "ioft" where b.count == 8: return Double(b.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }) / 65536
        default: return nil
        }
    }
}

// MARK: - IOHIDEventSystem temperature services (private API, read-only)

typealias HIDClientRef = OpaquePointer
typealias HIDServiceRef = OpaquePointer
typealias HIDEventRef = OpaquePointer
@_silgen_name("IOHIDEventSystemClientCreate") private func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> HIDClientRef?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func IOHIDEventSystemClientSetMatching(_ c: HIDClientRef, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func IOHIDEventSystemClientCopyServices(_ c: HIDClientRef) -> CFArray?
@_silgen_name("IOHIDServiceClientCopyProperty") private func IOHIDServiceClientCopyProperty(_ s: HIDServiceRef, _ k: CFString) -> CFTypeRef?
@_silgen_name("IOHIDServiceClientCopyEvent") private func IOHIDServiceClientCopyEvent(_ s: HIDServiceRef, _ t: Int64, _ a: Int32, _ b: Int64) -> HIDEventRef?
@_silgen_name("IOHIDEventGetFloatValue") private func IOHIDEventGetFloatValue(_ e: HIDEventRef, _ f: Int32) -> Double

final class HIDThermal {
    struct Service { let id: String; let name: String; let ref: HIDServiceRef }
    private var client: HIDClientRef?
    private var services: [AnyObject] = []
    private(set) var list: [Service] = []

    init() {
        guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return }
        client = c
        _ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let arr = IOHIDEventSystemClientCopyServices(c) as? [AnyObject] else { return }
        services = arr
        var seen: [String: Int] = [:]
        for s in arr {
            let ref = OpaquePointer(Unmanaged.passUnretained(s).toOpaque())
            let name = (IOHIDServiceClientCopyProperty(ref, "Product" as CFString) as? String) ?? "HID sensor"
            let loc = (IOHIDServiceClientCopyProperty(ref, "LocationID" as CFString) as? NSNumber)?.intValue ?? 0
            seen[name, default: 0] += 1
            list.append(Service(id: "hid:\(name):\(loc)", name: name, ref: ref))
        }
        // disambiguate duplicate product names (e.g. six "gas gauge battery" services)
        var idx: [String: Int] = [:]
        list = list.sorted { $0.id < $1.id }.map { s in
            guard (seen[s.name] ?? 0) > 1 else { return s }
            idx[s.name, default: 0] += 1
            return Service(id: s.id, name: "\(s.name) #\(idx[s.name]!)", ref: s.ref)
        }
    }

    func read(_ s: Service) -> Double? {
        guard let e = IOHIDServiceClientCopyEvent(s.ref, 15, 0, 0) else { return nil }
        return IOHIDEventGetFloatValue(e, 15 << 16)
    }
}
