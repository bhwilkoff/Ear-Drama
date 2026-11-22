// Runs Core ML predictions for tools/convert_kokoro_coreml.py's check, through Core ML itself rather than
// coremltools' Python binding, which segfaults loading the Kokoro decoder (macOS 26 runner and macOS 27, 2026-11-22).
//
//     xcrun swiftc -O tools/kokoro_coreml_predict.swift -o PREDICT && PREDICT REQUEST.json RESULT.json
//
// REQUEST: {"units": "cpu|gpu|ane|all", "calls": [{"model": "X.mlpackage", "function": "f64",
//           "inputs": {"name": {"file": "raw.bin", "shape": [1, 640, 64], "dtype": "float32|int32"}},
//           "outputs": {"name": "out.bin"}}]}
// RESULT:  {"calls": [{"seconds": predict time, "outputs": {"name": {"file": "out.bin", "shape": [...]}}}],
//           "load_seconds": {"X.mlpackage#f64": s}}
// Outputs are written as little-endian float32, whatever the model's own type.
import CoreML
import Foundation

struct Input: Decodable { let file: String; let shape: [Int]; let dtype: String }
struct Call: Decodable { let model: String; let function: String; let inputs: [String: Input]; let outputs: [String: String] }
struct Request: Decodable { let units: String; let calls: [Call] }

func fail(_ why: String) -> Never {
    FileHandle.standardError.write(Data("kokoro_coreml_predict: \(why)\n".utf8))
    exit(1)
}

func floats(_ a: MLMultiArray) -> [Float] {
    switch a.dataType {
    case .float32: return MLShapedArray<Float>(a).scalars
    case .float16: return MLShapedArray<Float16>(a).scalars.map { Float($0) }
    case .double: return MLShapedArray<Double>(a).scalars.map { Float($0) }
    case .int32: return MLShapedArray<Int32>(a).scalars.map { Float($0) }
    default: fail("output type \(a.dataType.rawValue)")
    }
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: kokoro_coreml_predict REQUEST.json RESULT.json") }
let request: Request
do { request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: URL(filePath: args[1]))) } catch { fail("request: \(error)") }
let units: MLComputeUnits = switch request.units {
case "cpu": .cpuOnly
case "gpu": .cpuAndGPU
case "ane": .cpuAndNeuralEngine
default: .all
}

var compiled: [String: URL] = [:]
var models: [String: MLModel] = [:]
var loadSeconds: [String: Double] = [:]
var results: [[String: Any]] = []

for call in request.calls {
    let key = call.model + "#" + call.function
    if models[key] == nil {
        let t0 = Date()
        do {
            if compiled[call.model] == nil {
                compiled[call.model] = try MLModel.compileModel(at: URL(filePath: call.model))
            }
            let config = MLModelConfiguration()
            config.computeUnits = units
            config.functionName = call.function
            models[key] = try MLModel(contentsOf: compiled[call.model]!, configuration: config)
        } catch { fail("load \(key): \(error)") }
        loadSeconds[key] = Date().timeIntervalSince(t0)
    }
    var features: [String: MLFeatureValue] = [:]
    for (name, input) in call.inputs {
        let data: Data
        do { data = try Data(contentsOf: URL(filePath: input.file)) } catch { fail("\(input.file): \(error)") }
        let count = input.shape.reduce(1, *)
        guard data.count == count * 4 else { fail("\(name): \(data.count) bytes for shape \(input.shape)") }
        let array: MLMultiArray = data.withUnsafeBytes { raw in
            if input.dtype == "int32" {
                return MLMultiArray(MLShapedArray<Int32>(scalars: Array(raw.bindMemory(to: Int32.self).prefix(count)), shape: input.shape))
            }
            return MLMultiArray(MLShapedArray<Float>(scalars: Array(raw.bindMemory(to: Float.self).prefix(count)), shape: input.shape))
        }
        features[name] = MLFeatureValue(multiArray: array)
    }
    let provider: MLDictionaryFeatureProvider
    do { provider = try MLDictionaryFeatureProvider(dictionary: features) } catch { fail("inputs: \(error)") }
    let t0 = Date()
    let out: MLFeatureProvider
    do { out = try models[key]!.prediction(from: provider) } catch { fail("predict \(key): \(error)") }
    let seconds = Date().timeIntervalSince(t0)
    var written: [String: Any] = [:]
    for (name, file) in call.outputs {
        guard let a = out.featureValue(for: name)?.multiArrayValue else { fail("\(key): no output \(name)") }
        let values = floats(a)
        do { try values.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: URL(filePath: file)) } catch { fail("\(file): \(error)") }
        written[name] = ["file": file, "shape": a.shape.map(\.intValue)]
    }
    results.append(["seconds": seconds, "outputs": written])
}

do {
    let json = try JSONSerialization.data(withJSONObject: ["calls": results, "load_seconds": loadSeconds], options: [.sortedKeys])
    try json.write(to: URL(filePath: args[2]))
} catch { fail("result: \(error)") }
