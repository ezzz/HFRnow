import AppKit
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
var i = 2
while i + 1 < a.count {
  let x = Int(a[i])!, y = Int(a[i+1])!
  let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
  print(x, y, String(format: "#%02X%02X%02X", Int(round(c.redComponent*255)), Int(round(c.greenComponent*255)), Int(round(c.blueComponent*255))))
  i += 2
}
