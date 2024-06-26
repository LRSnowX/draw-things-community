import Fickling
import Foundation
import ZIPFoundation

public typealias PythonReader = ([String: TensorDescriptor], TensorArchive) throws -> Void

public enum ModelWeightFormat {
  case diffusers
  case generativeModels
}
public typealias ModelWeightMapper = (ModelWeightFormat) -> [String: [String]]

public enum UnpickleError: Error {
  case dataNotFound
  case tensorNotFound
  case noRootObject
}

extension Interpreter {
  public static var inflateInterrupter: (() -> Bool)? = nil
  public static func unpickle(zip archive: Archive) throws -> Interpreter.Dictionary {
    guard let entry = (archive.first { $0.path.hasSuffix("/data.pkl") }) else {
      throw UnpickleError.dataNotFound
    }
    var data = Data()
    let _ = try archive.extract(entry) { data.append($0) }
    let interpreter = Interpreter.from(data: data)
    interpreter.intercept(module: "UNPICKLER", function: "persistent_load") {
      module, function, args in
      guard args.count >= 5, let global = args[1] as? Interpreter.GlobalObject,
        let name = args[2] as? String, let size = args[4] as? Int
      else { return [nil] }
      guard
        global.function == "HalfStorage" || global.function == "FloatStorage"
          || global.function == "DoubleStorage" || global.function == "BFloat16Storage"
      else {
        return [nil]
      }
      let storage: Storage
      if global.function == "HalfStorage" {
        storage = Storage(name: name, size: size, dataType: .Float16, BF16: false)
      } else if global.function == "BFloat16Storage" {
        storage = Storage(name: name, size: size, dataType: .Float16, BF16: true)
      } else if global.function == "DoubleStorage" {
        storage = Storage(name: name, size: size, dataType: .Float64, BF16: false)
      } else {
        storage = Storage(name: name, size: size, dataType: .Float32, BF16: false)
      }
      return [storage]
    }
    interpreter.intercept(module: "torch.nn.modules.container", function: "ParameterDict") {
      module, function, _ in
      return [Interpreter.Dictionary(.unordered)]
    }
    interpreter.intercept(module: "torch._utils", function: "_rebuild_tensor_v2") {
      module, function, args in
      guard args.count >= 5, let storage = args[0] as? Storage, let storageOffset = args[1] as? Int,
        let shape = args[2] as? [Int],
        let strides = args[3] as? [Int]
      else { return [nil] }
      let storeageOffsetInBytes: Int
      switch storage.dataType {
      case .Float16:
        storeageOffsetInBytes = storageOffset * 2
      case .Float32:
        storeageOffsetInBytes = storageOffset * 4
      case .Float64:
        storeageOffsetInBytes = storageOffset * 8
      case .UInt8, .Int32, .Int64:
        fatalError()
      }
      let tensorDescriptor = TensorDescriptor(
        storage: storage, storageOffset: storeageOffsetInBytes, shape: shape, strides: strides)
      return [tensorDescriptor]
    }
    interpreter.intercept(module: "torch._utils", function: "_rebuild_parameter") { _, _, args in
      guard let tensorDescriptor = args.first as? TensorDescriptor else { return [nil] }
      return [tensorDescriptor]
    }
    while try interpreter.step() {}
    guard let rootObject = (interpreter.rootObject as? Interpreter.Dictionary) else {
      throw UnpickleError.noRootObject
    }
    return rootObject
  }
}
