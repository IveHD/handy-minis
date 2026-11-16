// Real application views rendered with isolated sample data. No desktop capture.
import AppKit
import ImageIO
import UniformTypeIdentifiers

func snapshot(_ view: NSView) -> NSImage {
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    let result = NSImage(size: view.bounds.size); result.addRepresentation(rep); return result
}
func text(_ value: String, _ point: NSPoint, _ size: CGFloat = 16) {
    (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.labelColor])
}
func gif(_ names: [String], _ frames: [(NSImage,String)], width: Int, height: Int) {
    let url = URL(fileURLWithPath: "docs/demos/\(names[0]).gif")
    let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(out, [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    for (index, frame) in frames.enumerated() {
        let image = NSImage(size:NSSize(width:width,height:height)); image.lockFocus()
        NSColor.windowBackgroundColor.setFill(); NSRect(x:0,y:0,width:width,height:height).fill()
        let scale = min(CGFloat(width-32)/frame.0.size.width,CGFloat(height-86)/frame.0.size.height)
        let size = NSSize(width:frame.0.size.width*scale,height:frame.0.size.height*scale)
        frame.0.draw(in:NSRect(x:(CGFloat(width)-size.width)/2,y:66,width:size.width,height:size.height))
        text("\(index+1)/\(frames.count)  \(frame.1)",NSPoint(x:18,y:36),15)
        text("HandyMinis · 示例数据 / 实际界面",NSPoint(x:18,y:14),11)
        image.unlockFocus()
        CGImageDestinationAddImage(out,image.cgImage(forProposedRect:nil,context:nil,hints:nil)!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:2.2]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(out))
    for name in names.dropFirst() { let dest=URL(fileURLWithPath:"docs/demos/\(name).gif");try? FileManager.default.removeItem(at:dest);try! FileManager.default.copyItem(at:url,to:dest) }
    print("Rendered \(names.joined(separator:", ")): \(frames.count) frames")
}
@main struct Demo {
static func main() {
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named:.aqua)
    let clipboard = [("clipboard-light","⌘⇧C 打开历史"),("clipboard-next","↓ 选择下一条，展开完整预览"),("clipboard-search","输入「会议」筛选历史"),("release-phrases","→ 切换常用语，选择已保存的回复"),("release-files","→ 切换文件暂存，集中管理待用文件")].map { (NSImage(contentsOfFile:".build/tests/\($0.0).png")!,$0.1) }
    gif(["clipboard-workflow","clipboard"],clipboard,width:540,height:650)
    let sample = NSImage(size:NSSize(width:900,height:560));sample.lockFocus()
    NSColor.white.setFill();NSRect(x:0,y:0,width:900,height:560).fill()
    text("项目发布检查",NSPoint(x:120,y:415),28)
    text("Release checklist",NSPoint(x:120,y:370),22)
    text("核对版本与安装包，确认文档链接。",NSPoint(x:120,y:320),22)
    text("内部编号：HM-DEMO-2026",NSPoint(x:120,y:265),20)
    text("演示内容，不含个人数据",NSPoint(x:120,y:210),18)
    sample.unlockFocus()
    let view = CaptureView(frame:NSRect(x:0,y:0,width:900,height:560),image:sample.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
    let win = NSWindow(contentRect:view.bounds,styleMask:.borderless,backing:.buffered,defer:false);let canvas=NSView(frame:view.bounds); let backdrop=NSImageView(frame:view.bounds); backdrop.image=sample; backdrop.imageScaling = .scaleAxesIndependently; canvas.addSubview(backdrop); canvas.addSubview(view); win.contentView=canvas
    func mouse(_ type:NSEvent.EventType,_ x:CGFloat,_ y:CGFloat) -> NSEvent { NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:560-y),modifierFlags:[],timestamp:0,windowNumber:win.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)! }
    func drag(_ x:CGFloat,_ y:CGFloat,_ xx:CGFloat,_ yy:CGFloat) { view.mouseDown(with:mouse(.leftMouseDown,x,y));view.mouseDragged(with:mouse(.leftMouseDragged,xx,yy));view.mouseUp(with:mouse(.leftMouseUp,xx,yy)) }
    func key(_ s:String) {view.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:win.windowNumber,context:nil,characters:s,charactersIgnoringModifiers:s,isARepeat:false,keyCode:0)!)}
    var frames:[(NSImage,String)]=[(snapshot(canvas),"⌃⌘A 进入截图，准备框选")]
    drag(85,90,800,380);frames.append((snapshot(canvas),"拖动框选内容，显示真实标注工具栏"))
    key("b");drag(115,273,440,300);frames.append((snapshot(canvas),"B 实心遮挡，隐藏内部编号"))
    key("a");drag(660,240,525,240);frames.append((snapshot(canvas),"A 添加箭头，指出需要关注的内容"))
    key("x")
    let deadline=Date().addingTimeInterval(8)
    while Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.1))}
    frames.append((snapshot(canvas),"X 使用本机 OCR 识别中英文"))
    drag(121,171,345,185);frames.append((snapshot(canvas),"拖动选择识别文字，可点击「复制文字」"))
    gif(["screenshot-ocr","screenshot-workflow"],frames,width:900,height:646)
    // Native demo windows illustrate positioning without moving the user's windows.
    let desktop=NSView(frame:NSRect(x:0,y:0,width:900,height:520));desktop.wantsLayer=true;desktop.layer?.backgroundColor=NSColor(calibratedWhite:0.91,alpha:1).cgColor
    var windows:[NSWindow]=[]
    for (title,body) in [("项目笔记","今日计划\n\n核对发布清单\n整理用户反馈\n更新使用说明"),("发布清单","HandyMinis\n\n✓ 构建通用安装包\n✓ 验证常用语与文件暂存\n✓ 更新文档")]{
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:410,height:410),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);w.title=title
        let t=NSTextView(frame:w.contentView!.bounds);t.string=body;t.font=NSFont.systemFont(ofSize:20);t.textContainerInset=NSSize(width:24,height:24);w.contentView=t;windows.append(w)
    }
    func scene(_ positions:[NSRect])->NSImage {
        for v in desktop.subviews {v.removeFromSuperview()}
        for (w,rect) in zip(windows,positions) {w.setContentSize(rect.size);let image=NSImageView(frame:rect);image.image=snapshot(w.contentView!.superview!);image.imageScaling = .scaleAxesIndependently;desktop.addSubview(image)}
        return snapshot(desktop)
    }
    let scattered=[NSRect(x:50,y:70,width:430,height:360),NSRect(x:390,y:20,width:440,height:360)]
    let aligned=[NSRect(x:8,y:8,width:438,height:490),NSRect(x:454,y:8,width:438,height:490)]
    let wf=[(scene(scattered),"窗口位置示意：两个示例窗口待整理"),(scene([aligned[0],scattered[1]]),"拖向屏幕左侧，窗口贴靠左半屏"),(scene(aligned),"另一窗口贴靠右半屏，形成并排工作区"),(scene(aligned),"菜单栏 → 窗口布局 → 保存当前布局…"),(scene(scattered),"工作中移动窗口，布局发生变化"),(scene(aligned),"选择已保存布局，恢复已打开窗口的位置")]
    gif(["window-layout-demo","window-workflow","window-tiling"],wf,width:900,height:606)
}
}
