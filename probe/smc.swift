import Foundation
import IOKit

struct KeyDataVer { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var attributes: UInt8 = 0; var p1: UInt8 = 0, p2: UInt8 = 0, p3: UInt8 = 0 }
typealias B32 = (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)
struct SMCParam {
  var key: UInt32 = 0
  var vers = KeyDataVer()
  var pLimit = PLimit()
  var keyInfo = KeyInfo()
  var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: B32 = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
func fcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func str(_ v: UInt32) -> String { String(bytes: [24,16,8,0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "?" }

print("stride", MemoryLayout<SMCParam>.stride, MemoryLayout<SMCParam>.offset(of: \SMCParam.result)!)
var conn: io_connect_t = 0
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
precondition(IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS)
func call(_ i: inout SMCParam) -> SMCParam? {
  var o = SMCParam(); var sz = MemoryLayout<SMCParam>.stride
  let r = IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<SMCParam>.stride, &o, &sz)
  return r == KERN_SUCCESS && o.result == 0 ? o : nil
}
func info(_ k: UInt32) -> KeyInfo? { var p = SMCParam(); p.key = k; p.data8 = 9; return call(&p)?.keyInfo }
func read(_ k: UInt32) -> (KeyInfo, [UInt8])? {
  guard let ki = info(k) else { return nil }
  var p = SMCParam(); p.key = k; p.keyInfo.dataSize = ki.dataSize; p.data8 = 5
  guard let o = call(&p) else { return nil }
  var b = o.bytes; let arr = withUnsafeBytes(of: &b) { Array($0.prefix(Int(ki.dataSize))) }
  return (ki, arr)
}
func keyAt(_ i: UInt32) -> UInt32? { var p = SMCParam(); p.data8 = 8; p.data32 = i; return call(&p)?.key }
let (_, nb) = read(fcc("#KEY"))!
let n = nb.reduce(0) { UInt32($0) << 8 | UInt32($1) }
print("total keys", n)
var cnt = 0
for i in 0..<n {
  guard let k = keyAt(i) else { continue }
  let s = str(k)
  guard s.hasPrefix("T"), let (ki, b) = read(k) else { continue }
  let t = str(ki.dataType)
  var v = Double.nan
  if t == "flt " && b.count == 4 { v = Double(b.withUnsafeBytes { $0.load(as: Float.self) }) }
  else if t == "sp78" && b.count == 2 { v = Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 }
  else if t == "ioft" && b.count == 8 { v = Double(b.withUnsafeBytes { $0.load(as: UInt64.self) }) / 65536 }
  if !v.isNaN { print(s, t, String(format: "%.2f", v)); cnt += 1 } else { print(s, t, b) }
}
print("temp-like", cnt)
