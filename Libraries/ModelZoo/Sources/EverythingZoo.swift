import Foundation
import Upscaler

public struct EverythingZoo: DownloadZoo {
  public struct Specification {
    public var name: String
    public var file: String
    public var parsenet: String?
    public var backbone: String?
    public init(name: String, file: String, parsenet: String? = nil, backbone: String? = nil) {
      self.name = name
      self.file = file
      self.parsenet = parsenet
      self.backbone = backbone
    }
  }

  private static let fileSHA256: [String: String] = [
    "restoreformer_v1.0_f16.ckpt":
      "35347003c19fc22a27d09170401abfa9bcb21043ad84af87bba6367e11656b91",
    "parsenet_v1.0_f16.ckpt":
      "db663901a8e4c016920da090856898b948b4773691c29a0e75720f6b741c4f90",
    "dis_v1.0_f16.ckpt": "6fa78bbb6478d5edd084bb904b6621772aad0f143065e936a06cb6ca6378748d",
    "depth_anything_v1.0_f16.ckpt":
      "98d969335504787ca7a539b0e5582a95f6e6a2c7167e66f8085bfc00bb7ed2ea",
    "dino_v2_f16.ckpt": "0307862ca24f4021e585f2a6f849a8ec97fbede35d08568344e860ba7f0bdd9d",
    "is_net_v1.1_fp16.ckpt": "979e667a1ab7f9600b875dedc528c855ec6f12af1f8e8bfed477a785abd694a5",
    "film_1.0_f16.ckpt": "6716ef2f07e1479b5b2d6d5d3756ca221da6674f2c2a632c421d0fa41676f9c3",

  ]

  static let builtinSpecifications: [Specification] = [
    Specification(
      name: "RestoreFormer", file: "restoreformer_v1.0_f16.ckpt", parsenet: "parsenet_v1.0_f16.ckpt"
    ),
    Specification(name: "Dichotomous Image Segmentation", file: "dis_v1.0_f16.ckpt"),
    Specification(
      name: "Depth Anything", file: "depth_anything_v1.0_f16.ckpt", backbone: "dino_v2_f16.ckpt"
    ),
    Specification(name: "IS Net 1.1", file: "is_net_v1.1_fp16.ckpt"),
    Specification(name: "FILM", file: "film_1.0_f16.ckpt"),
  ]

  public static var availableSpecifications: [Specification] { builtinSpecifications }

  private static var specificationMapping: [String: Specification] = {
    var mapping = [String: Specification]()
    for specification in availableSpecifications {
      mapping[specification.file] = specification
    }
    return mapping
  }()

  public static func filePathForModelDownloaded(_ name: String) -> String {
    return ModelZoo.filePathForModelDownloaded(name)
  }

  public static func parsenetForModel(_ name: String) -> String {
    guard let specification = specificationMapping[name] else { return "" }
    return specification.parsenet ?? ""
  }

  public static func backboneForModel(_ name: String) -> String {
    guard let specification = specificationMapping[name] else { return "" }
    return specification.backbone ?? ""
  }

  public static func isModelDownloaded(_ name: String) -> Bool {
    return ModelZoo.isModelDownloaded(name)
  }

  public static func modelsToDownload(_ name: String) -> [(
    name: String, subtitle: String, file: String, sha256: String?
  )] {
    guard let specification = specificationMapping[name] else {
      return [(name: name, subtitle: "", file: name, sha256: Self.filePathForModelDownloaded(name))]
    }
    var models = [(name: String, subtitle: String, file: String, sha256: String?)]()
    if !isModelDownloaded(specification.file) {
      models.append(
        (
          name: specification.name, subtitle: "", file: specification.file,
          sha256: Self.filePathForModelDownloaded(specification.file)
        ))
    }
    if let parsenet = specification.parsenet, !isModelDownloaded(parsenet) {
      models.append(
        (
          name: specification.name, subtitle: "", file: parsenet,
          sha256: Self.filePathForModelDownloaded(parsenet)
        ))
    }
    if let backbone = specification.backbone, !isModelDownloaded(backbone) {
      models.append(
        (
          name: specification.name, subtitle: "", file: backbone,
          sha256: Self.filePathForModelDownloaded(backbone)
        ))
    }
    return models
  }

  public static func humanReadableNameForModel(_ name: String) -> String {
    guard let specification = specificationMapping[name] else { return name }
    return specification.name
  }

  public static func fileSHA256ForModelDownloaded(_ name: String) -> String? {
    return fileSHA256[name]
  }

  public static func availableFiles(excluding file: String?) -> Set<String> {
    var files = Set<String>()
    for specification in availableSpecifications {
      guard specification.file != file, EverythingZoo.isModelDownloaded(specification.file) else {
        continue
      }
      files.insert(specification.file)
      if let parsenet = specification.parsenet {
        files.insert(parsenet)
      }
      if let backbone = specification.backbone {
        files.insert(backbone)
      }
    }
    return files
  }
}
