// Connected components of "light" pixels (r,g,b > thr) in a PNG: prints bbox, area, stroke estimate.
import AppKit
let a = CommandLine.arguments
let rep = NSBitmapImageRep(data: NSImage(contentsOfFile: a[1])!.tiffRepresentation!)!
let thr = Double(a.count > 2 ? a[2] : "0.78")!
let dark = a.count > 3 && a[3] == "dark"
let w = rep.pixelsWide, h = rep.pixelsHigh
var m = [Bool](repeating: false, count: w*h)
for y in 0..<h { for x in 0..<w {
  let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
  let v = min(c.redComponent, c.greenComponent, c.blueComponent)
  let mx = max(c.redComponent, c.greenComponent, c.blueComponent)
  m[y*w+x] = dark ? (mx < 1 - thr) : (v > thr)
}}
var seen = [Bool](repeating: false, count: w*h)
print("size", w, h)
for i in 0..<(w*h) where m[i] && !seen[i] {
  var st = [i]; seen[i] = true; var n = 0; var x0 = w, y0 = h, x1 = 0, y1 = 0
  while let j = st.popLast() { n += 1; let x = j % w, y = j / w
    x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] { let nx = x+dx, ny = y+dy
      if nx >= 0, ny >= 0, nx < w, ny < h { let k = ny*w+nx; if m[k] && !seen[k] { seen[k] = true; st.append(k) } } } }
  if n > 20 { print("cc bbox x \(x0)-\(x1) y \(y0)-\(y1) w \(x1-x0+1) h \(y1-y0+1) area \(n)") }
}
