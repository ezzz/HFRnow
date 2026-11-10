// Median of strongly orange pixels inside a rectangle: x0 y0 x1 y1
import AppKit
let a = CommandLine.arguments
let rep = NSBitmapImageRep(data: NSImage(contentsOfFile: a[1])!.tiffRepresentation!)!
let (x0, y0, x1, y1) = (Int(a[2])!, Int(a[3])!, Int(a[4])!, Int(a[5])!)
var rs = [Int](), gs = [Int](), bs = [Int]()
for y in y0...y1 { for x in x0...x1 {
  let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
  let r = Int(c.redComponent*255), g = Int(c.greenComponent*255), b = Int(c.blueComponent*255)
  if r > 200 && g > 90 && g < 190 && b < 90 { rs.append(r); gs.append(g); bs.append(b) }
}}
func med(_ v: [Int]) -> Int { v.sorted()[v.count/2] }
print("n", rs.count, String(format: "median #%02X%02X%02X", med(rs), med(gs), med(bs)))
