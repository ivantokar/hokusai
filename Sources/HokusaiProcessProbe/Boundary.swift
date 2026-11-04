import Foundation
import Hokusai

// Boundary values for the public API (#111). A Swift or native trap kills the
// process, so each case runs in its own process: the probe builds one
// pipeline with one extreme argument, evaluates it, and reports what happened.
// Any typed error is an acceptable outcome; a crash is not.

let extremeIntegers: [(String, Int)] = [
    ("Int.min", Int.min), ("-1", -1), ("0", 0), ("1", 1), ("10000000", 10_000_000), ("10000001", 10_000_001),
    ("Int32.max", Int(Int32.max)), ("Int32.max+1", Int(Int32.max) + 1), ("Int.max", Int.max),
]

let extremeDoubles: [(String, Double)] = [
    ("-inf", -.infinity), ("-1e308", -1e308), ("-1", -1), ("0", 0), ("1e-308", 1e-308), ("0.5", 0.5), ("1", 1),
    ("1e308", 1e308), ("inf", .infinity), ("nan", .nan),
]

typealias BoundaryBuild = (Hokusai) throws -> Hokusai

/// Every combination of one public operation, one parameter and one extreme value.
func boundaryCases() -> [(name: String, build: BoundaryBuild)] {
    var cases: [(String, BoundaryBuild)] = []
    // Built once, outside the closures: Swift 6.0 crashes while lowering a closure
    // that captures a function declared in main.swift.
    let source = tiff(width: 16, height: 16)
    func integer(_ name: String, _ build: @escaping (Hokusai, Int) throws -> Hokusai) {
        for (label, value) in extremeIntegers { cases.append(("\(name)=\(label)", { try build($0, value) })) }
    }
    func double(_ name: String, _ build: @escaping (Hokusai, Double) throws -> Hokusai) {
        for (label, value) in extremeDoubles { cases.append(("\(name)=\(label)", { try build($0, value) })) }
    }

    integer("resize.width") { try $0.resize(width: $1) }
    integer("resize.height") { try $0.resize(height: $1) }
    integer("extract.x") { try $0.extract(x: $1, y: 0, width: 8, height: 8) }
    integer("extract.y") { try $0.extract(x: 0, y: $1, width: 8, height: 8) }
    integer("extract.width") { try $0.extract(x: 0, y: 0, width: $1, height: 8) }
    integer("extract.height") { try $0.extract(x: 0, y: 0, width: 8, height: $1) }
    integer("extend.width") { try $0.extend(to: ImageSize(width: $1, height: 100)) }
    integer("extend.height") { try $0.extend(to: ImageSize(width: 100, height: $1)) }
    integer("extend.top") { try $0.extend(top: $1) }
    integer("extend.left") { try $0.extend(left: $1) }
    integer("extend.bottom") { try $0.extend(bottom: $1) }
    integer("extend.right") { try $0.extend(right: $1) }
    integer("smartCrop.width") { try $0.smartCrop(width: $1, height: 8) }
    integer("smartCrop.height") { try $0.smartCrop(width: 8, height: $1) }
    integer("clahe.width") { try $0.clahe(width: $1) }
    integer("clahe.height") { try $0.clahe(height: $1) }
    integer("clahe.maxSlope") { try $0.clahe(maxSlope: $1) }
    integer("median.size") { try $0.median(size: $1) }
    integer("affine.area.x") { try $0.affine(AffineMatrix(a: 1, b: 0, c: 0, d: 1), outputArea: AffineArea(x: $1, y: 0, width: 8, height: 8)) }
    integer("affine.area.y") { try $0.affine(AffineMatrix(a: 1, b: 0, c: 0, d: 1), outputArea: AffineArea(x: 0, y: $1, width: 8, height: 8)) }
    integer("affine.area.width") { try $0.affine(AffineMatrix(a: 1, b: 0, c: 0, d: 1), outputArea: AffineArea(x: 0, y: 0, width: $1, height: 8)) }
    integer("affine.area.height") { try $0.affine(AffineMatrix(a: 1, b: 0, c: 0, d: 1), outputArea: AffineArea(x: 0, y: 0, width: 8, height: $1)) }
    integer("composite.x") { try $0.composite([CompositeLayer($0, x: $1, y: 0)]) }
    integer("composite.y") { try $0.composite([CompositeLayer($0, x: 0, y: $1)]) }
    integer("composite.gravityOffsetX") { try $0.composite([CompositeLayer($0, placement: .gravity(.center, offsetX: $1, offsetY: 0))]) }
    integer("composite.gravityOffsetY") { try $0.composite([CompositeLayer($0, placement: .gravity(.center, offsetX: 0, offsetY: $1))]) }
    integer("jpeg.quality") { try $0.jpeg(quality: $1) }
    integer("png.compressionLevel") { try $0.png(compressionLevel: $1) }
    integer("webp.quality") { try $0.webp(quality: $1) }
    integer("webp.effort") { try $0.webp(effort: $1) }
    integer("text.fontSize") { try $0.drawText("Hi", style: TextStyle(fontSize: $1)) }
    integer("text.dpi") { try $0.drawText("Hi", style: TextStyle(dpi: $1)) }
    integer("text.layoutWidth") { try $0.drawText("Hi", layout: .width($1)) }
    integer("text.fitWidth") { try $0.drawText("Hi", layout: .fit(width: $1, height: 20)) }
    integer("text.fitHeight") { try $0.drawText("Hi", layout: .fit(width: 20, height: $1)) }
    integer("input.page") { try Hokusai(data: source, options: InputOptions(page: $1)) }
    integer("input.maxPixels") { try Hokusai(data: source, options: InputOptions(limits: InputLimits(maxPixels: $1))) }
    integer("input.maxBytes") { try Hokusai(data: source, options: InputOptions(limits: InputLimits(maxBytes: $1))) }

    double("rotate.degrees") { try $0.rotate(by: $1) }
    double("blur.sigma") { try $0.blur(sigma: $1) }
    double("blur.minAmplitude") { try $0.blur(minAmplitude: $1) }
    double("sharpen.sigma") { try $0.sharpen(sigma: $1) }
    double("normalize.lower") { try $0.normalize(lower: $1) }
    double("normalize.upper") { try $0.normalize(upper: $1) }
    double("gamma.value") { try $0.gamma($1) }
    double("threshold.level") { try $0.threshold($1) }
    double("modulate.brightness") { try $0.modulate(brightness: $1) }
    double("modulate.saturation") { try $0.modulate(saturation: $1) }
    double("modulate.hue") { try $0.modulate(hue: $1) }
    double("ensureAlpha.opacity") { try $0.ensureAlpha(opacity: $1) }
    double("trim.threshold") { try $0.trim(threshold: $1) }
    double("composite.opacity") { try $0.composite([CompositeLayer($0, x: 0, y: 0, opacity: $1)]) }
    double("affine.a") { try $0.affine(AffineMatrix(a: $1, b: 0, c: 0, d: 1)) }
    double("affine.d") { try $0.affine(AffineMatrix(a: 1, b: 0, c: 0, d: $1)) }
    double("affine.outputOffsetX") { try $0.affine(AffineMatrix(a: 1, b: 0, c: 0, d: 1), outputOffset: AffineOffset(x: $1, y: 0)) }
    double("pdf.maxEffectiveDPI") { try $0.pdf(maxEffectiveDPI: $1) }
    double("text.lineHeight") { try $0.drawText("Hi", style: TextStyle(lineHeight: $1)) }
    double("text.rotation") { try $0.drawText("Hi", style: TextStyle(rotation: $1)) }
    double("text.strokeWidth") { try $0.drawText("Hi", style: TextStyle(stroke: TextStroke(color: .white, width: $1))) }
    double("color.red") { try $0.flatten(background: Color(red: $1, green: 0, blue: 0)) }
    return cases
}

func runBoundary() async {
    let name = options["case"] ?? ""
    if name == "list" {
        for entry in boundaryCases() { print(entry.name) }
        return
    }
    guard let entry = boundaryCases().first(where: { $0.name == name }) else {
        FileHandle.standardError.write(Data("unknown boundary case \(name)\n".utf8))
        exit(64)
    }
    let source = tiff(width: 64, height: 48)
    do {
        let output = try await entry.build(Hokusai(data: source)).png().data()
        report(["outcome": "ok", "width": output.info.width, "height": output.info.height])
    } catch {
        report(["outcome": category(error)])
    }
}
