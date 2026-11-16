// Reproducible, synthetic workflow illustrations. No user screenshots or data.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let ink = NSColor(srgbRed: 0.075, green: 0.22, blue: 0.18, alpha: 1)
let muted = NSColor(srgbRed: 0.37, green: 0.44, blue: 0.40, alpha: 1)
let cream = NSColor(srgbRed: 0.98, green: 0.97, blue: 0.92, alpha: 1)
let pale = NSColor(srgbRed: 0.87, green: 0.92, blue: 0.84, alpha: 1)
let lime = NSColor(srgbRed: 0.78, green: 0.92, blue: 0.40, alpha: 1)
let brand = NSImage(contentsOfFile: "docs/assets/app-icon.png")!
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 12) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func label(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 16, color: NSColor = ink, bold: Bool = false) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: color])
}
func line(_ points: [NSPoint], _ color: NSColor, width: CGFloat = 3) {
    let path = NSBezierPath(); path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
    color.setStroke();path.stroke()
}
func cursor(_ x: CGFloat, _ y: CGFloat) {
    let path = NSBezierPath();path.move(to: NSPoint(x: x, y: y))
    for p in [(0.0,22.0),(6.0,16.0),(12.0,27.0),(17.0,24.0),(11.0,14.0),(20.0,13.0)] {
        path.line(to: NSPoint(x: x+p.0, y: y+p.1))
    }
    path.close(); ink.setFill();path.fill();NSColor.white.setStroke();path.lineWidth=1.3;path.stroke()
}
func header(_ title: String, width: CGFloat) {
    brand.draw(in: NSRect(x: 22, y: 15, width: 34, height: 34))
    label("HandyMinis", 63, 22, 17, bold: true)
    label("操作示意", width-89, 24, 12, color: muted)
    label(title, 28, 68, 24, bold: true)
}
func clipboard(_ step: Int, _ width: CGFloat, _ height: CGFloat) {
    header("复制过的，随时找回来。", width: width)
    let x: CGFloat = 28, y: CGFloat = 116, w = width-56
    box(x,y,w,height-190,.white)
    for (i,t) in ["历史","常用语","文件暂存"].enumerated() {
        let selected = step == 2 ? 1 : step == 3 ? 2 : 0
        let tabWidth = (w-32)/3
        if i == selected { box(x+16+CGFloat(i)*tabWidth,y+16,tabWidth-4,31,pale,radius:7) }
        label(t,x+24+CGFloat(i)*tabWidth,y+21,14,bold:i==selected)
    }
    box(x+16,y+61,w-32,32,cream,radius:7)
    label(step == 1 ? "搜索：项目" : "搜索文本、图片和文件",x+28,y+68,13,color:muted)
    let rows: [(String,String)]
    switch step {
    case 1: rows=[("项目讨论纪要","明天下午 14:00，同步项目进展。")]
    case 2: rows=[("常用回复","收到，我会尽快确认后回复。"),("会议通知","请提前准备本周项目进展。")]
    case 3: rows=[("项目资料.pdf","文件暂存 · 拖到目标应用"),("截图示例.png","文件暂存 · 随时取用")]
    default: rows=[("项目讨论纪要","明天下午 14:00，同步项目进展。"),("发布清单","检查安装包与版本说明。"),("example.com","刚刚复制的链接")]
    }
    for (i,row) in rows.enumerated() {
        let yy=y+108+CGFloat(i)*64
        if i==0 {box(x+16,yy,w-32,57,pale,radius:8)}
        label(row.0,x+30,yy+7,15,bold:true)
        label(row.1,x+30,yy+31,12,color:muted)
    }
    let captions=["⌘⇧C 打开历史，↑ ↓ 选择记录","输入关键词，回车粘贴到原来的应用","⌃↵ 存为常用语，下次直接取用","暂存文件，需要时拖到目标应用"]
    label(captions[step],28,height-50,14,bold:true)
}
func screenshot(_ step: Int, _ width: CGFloat, _ height: CGFloat) {
    header("截图、遮挡、识别，一次完成。", width:width)
    box(28,112,width-56,height-190,pale)
    let x: CGFloat=112,y: CGFloat=144,w=width-224,h: CGFloat=190
    box(x,y,w,h,.white,radius:6)
    label("发布检查",x+28,y+22,22,bold:true)
    label("Release checklist",x+28,y+60,16)
    label("测试安装，核对 SHA-256",x+28,y+96,17)
    label("内部编号：HM-2026-01",x+28,y+137,16)
    if step>=1 {
        let border=NSBezierPath(rect:NSRect(x:x-5,y:y-5,width:w+10,height:h+10))
        ink.setStroke();border.lineWidth=2;border.stroke()
        for xx in [x-5,x+w+1] {for yy in [y-5,y+h+1] {box(xx,yy,5,5,ink,radius:0)}}
        box(x+20,y+h+17,w-40,32,.white,radius:8)
        label("V  □  ○  ↗  P  T  M  B  X     复制  保存",x+31,y+h+25,13)
    }
    if step>=2 {box(x+26,y+134,260,24,ink,radius:2)}
    if step>=3 {
        line([NSPoint(x:x+w-36,y:y+110),NSPoint(x:x+270,y:y+108)],.systemRed)
        line([NSPoint(x:x+280,y:y+102),NSPoint(x:x+270,y:y+108),NSPoint(x:x+280,y:y+114)],.systemRed)
    }
    if step>=4 {
        box(x+25,y+94,235,25,lime,radius:2)
        label("测试安装，核对 SHA-256",x+28,y+96,17)
    }
    cursor(step==0 ? x-6 : x+w-50,step==0 ? y-6 : y+110)
    let captions=["⌃⌘A 开始截图，拖动框选区域","确认选区，使用工具栏添加标记","B 实心遮挡；M 马赛克保护敏感内容","A 添加箭头，指出需要关注的位置","X 在本机识别中英文，拖动选择文字","⌘C 复制选中文字，或保存截图 PNG"]
    label(captions[step],28,height-48,16,bold:true)
}
func window(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ title:String) {
    box(x,y,w,h,.white,radius:9)
    box(x,y,w,28,NSColor(white:0.96,alpha:1),radius:9)
    for (i,c) in [NSColor.systemRed,.systemYellow,.systemGreen].enumerated() {
        box(x+10+CGFloat(i)*12,y+10,7,7,c,radius:4)
    }
    label(title,x+57,y+6,11)
    label("HandyMinis",x+18,y+48,18,bold:true)
    label("小工具，每天都用得上。",x+18,y+78,12,color:muted)
}
func windows(_ step:Int,_ width:CGFloat,_ height:CGFloat) {
    header("窗口排好，一键回到工作状态。",width:width)
    let x:CGFloat=28,y:CGFloat=114,w=width-56,h=height-190
    box(x,y,w,h,pale)
    box(x,y,w,24,NSColor.white.withAlphaComponent(0.6),radius:8)
    label("HM",x+w-43,y+4,12,bold:true)
    let half=(w-30)/2
    if step==0 {window(x+90,y+65,300,h-85,"备忘录");cursor(x+240,y+76)}
    else if step==1 {
        box(x+10,y+34,half,h-44,lime)
        window(x+30,y+55,300,h-75,"备忘录");cursor(x+180,y+66)
    } else if step==2 {window(x+10,y+34,half,h-44,"备忘录")}
    else if step==5 {
        window(x+45,y+50,300,h-70,"备忘录");window(x+330,y+75,300,h-95,"浏览器")
    } else {
        window(x+10,y+34,half,h-44,"备忘录");window(x+20+half,y+34,half,h-44,"浏览器")
    }
    if step==3 || step==4 || step==6 {
        box(x+w-276,y+24,258,124,ink,radius:10)
        label("窗口布局",x+w-258,y+38,15,color:cream,bold:true)
        label(step==3 ? "保存当前布局…" : "✓ 工作台",x+w-258,y+76,15,color:lime,bold:true)
        label(step==3 ? "记录当前窗口位置与大小" : "恢复已打开窗口的位置与大小",x+w-258,y+110,12,color:cream)
    }
    let captions=["拖动窗口标题栏，靠近屏幕边缘","出现半屏预览后松开鼠标","窗口自动贴靠，留出另一半工作空间","HM → 窗口布局 → 保存当前布局…","命名为「工作台」，保存这组窗口位置","窗口移动后，重新打开相应应用窗口","选择「工作台」，恢复已保存的布局","继续工作，常用窗口各归其位"]
    label(captions[step],28,height-48,16,bold:true)
}
func gif(_ name:String,width:Int,height:Int,count:Int,draw:(Int,CGFloat,CGFloat)->Void) throws {
    let url=URL(fileURLWithPath:"docs/demos/\(name).gif")
    let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.gif.identifier as CFString,count,nil)!
    CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    for step in 0..<count {
        let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x:0,y:CGFloat(height));context.scaleBy(x:1,y:-1)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
        box(0,0,CGFloat(width),CGFloat(height),cream,radius:0)
        draw(step,CGFloat(width),CGFloat(height))
        NSGraphicsContext.restoreGraphicsState()
        CGImageDestinationAddImage(destination,context.makeImage()!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.8]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else {fatalError("Cannot write \(name)")}
    print("Generated \(name).gif (\(count) illustrative frames)")
}
try gif("clipboard-workflow",width:460,height:520,count:4,draw:clipboard)
try gif("clipboard",width:800,height:520,count:4,draw:clipboard)
for name in ["screenshot-ocr","screenshot-workflow"] {
    try gif(name,width:800,height:480,count:6,draw:screenshot)
}
for name in ["window-layout-demo","window-workflow","window-tiling"] {
    try gif(name,width:800,height:480,count:8,draw:windows)
}
