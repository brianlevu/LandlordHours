// Draws mark B (design/brand/logo/mark-b.svg, colour) as a 112×112 pt vector PDF for
// LaunchScreen.storyboard. Usage: swift scripts/launch/make_launch_mark.swift <out.pdf>
import CoreGraphics
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var box = CGRect(x: 0, y: 0, width: 112, height: 112)
let ctx = CGContext(out as CFURL, mediaBox: &box, nil)!
ctx.beginPDFPage(nil)
let s: CGFloat = 112 / 1024
// SVG space (y down) → PDF space (y up), plus the mark's optical offset translate(10 -11.5).
ctx.translateBy(x: 0, y: 112)
ctx.scaleBy(x: s, y: -s)
ctx.translateBy(x: 10, y: -11.5)
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
ctx.setLineCap(.round); ctx.setLineJoin(.round)
// Drafted (cyan linework)
ctx.setStrokeColor(rgb(0x8FD3FF)); ctx.setLineWidth(26)
ctx.move(to: CGPoint(x: 512, y: 232)); ctx.addLine(to: CGPoint(x: 836, y: 486))
ctx.move(to: CGPoint(x: 770, y: 436)); ctx.addLine(to: CGPoint(x: 770, y: 700))
ctx.strokePath()
ctx.addPath(CGPath(roundedRect: CGRect(x: 588, y: 540, width: 120, height: 96), cornerWidth: 12, cornerHeight: 12, transform: nil))
ctx.strokePath()
// Built plaster
ctx.setFillColor(rgb(0xF4EFE6))
ctx.addPath(CGPath(roundedRect: CGRect(x: 222, y: 808, width: 580, height: 40), cornerWidth: 10, cornerHeight: 10, transform: nil))
ctx.addRect(CGRect(x: 250, y: 470, width: 262, height: 342))
ctx.addRect(CGRect(x: 512, y: 690, width: 258, height: 122))
ctx.fillPath()
// Terracotta roof slope
ctx.setStrokeColor(rgb(0xC8553D)); ctx.setLineWidth(66)
ctx.move(to: CGPoint(x: 512, y: 232)); ctx.addLine(to: CGPoint(x: 188, y: 486)); ctx.strokePath()
// Timber door
ctx.setFillColor(rgb(0xE0A458))
ctx.move(to: CGPoint(x: 382, y: 812)); ctx.addLine(to: CGPoint(x: 382, y: 683))
ctx.addArc(center: CGPoint(x: 429, y: 683), radius: 47, startAngle: .pi, endAngle: 0, clockwise: false)
ctx.addLine(to: CGPoint(x: 476, y: 812)); ctx.closePath(); ctx.fillPath()
ctx.endPDFPage()
ctx.closePDF()
