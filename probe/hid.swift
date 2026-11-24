import Foundation
import IOKit

typealias IOHIDEventSystemClientRef = OpaquePointer
typealias IOHIDServiceClientRef = OpaquePointer
typealias IOHIDEventRef = OpaquePointer
@_silgen_name("IOHIDEventSystemClientCreate") func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> IOHIDEventSystemClientRef
@_silgen_name("IOHIDEventSystemClientSetMatching") func IOHIDEventSystemClientSetMatching(_ c: IOHIDEventSystemClientRef, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") func IOHIDEventSystemClientCopyServices(_ c: IOHIDEventSystemClientRef) -> CFArray?
@_silgen_name("IOHIDServiceClientCopyProperty") func IOHIDServiceClientCopyProperty(_ s: IOHIDServiceClientRef, _ k: CFString) -> CFTypeRef?
@_silgen_name("IOHIDServiceClientCopyEvent") func IOHIDServiceClientCopyEvent(_ s: IOHIDServiceClientRef, _ t: Int64, _ a: Int32, _ b: Int64) -> IOHIDEventRef?
@_silgen_name("IOHIDEventGetFloatValue") func IOHIDEventGetFloatValue(_ e: IOHIDEventRef, _ f: Int32) -> Double

let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
_ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
let arr = IOHIDEventSystemClientCopyServices(c)! as NSArray
var out: [(String, Double)] = []
for s in arr {
  let sc = OpaquePointer(Unmanaged<AnyObject>.passUnretained(s as AnyObject).toOpaque())
  let name = (IOHIDServiceClientCopyProperty(sc, "Product" as CFString) as? String) ?? "?"
  let loc = (IOHIDServiceClientCopyProperty(sc, "LocationID" as CFString) as? NSNumber)?.stringValue ?? ""
  if let e = IOHIDServiceClientCopyEvent(sc, 15, 0, 0) {
    out.append((name + " [" + loc + "]", IOHIDEventGetFloatValue(e, 15 << 16)))
  }
}
for (n, v) in out.sorted(by: {$0.0 < $1.0}) { print(String(format: "%-40@ %.2f", n as NSString, v)) }
print("count", out.count)
