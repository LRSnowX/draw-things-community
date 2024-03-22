import NNC

public struct TextEncoder<FloatType: TensorNumeric & BinaryFloatingPoint> {
  public let filePaths: [String]
  public let version: ModelVersion
  public let usesFlashAttention: Bool
  public let injectEmbeddings: Bool
  public let maxLength: Int
  public let clipSkip: Int
  public let lora: [LoRAConfiguration]
  public let externalOnDemand: Bool
  public init(
    filePaths: [String], version: ModelVersion, usesFlashAttention: Bool, injectEmbeddings: Bool,
    externalOnDemand: Bool, maxLength: Int = 77, clipSkip: Int = 1, lora: [LoRAConfiguration] = []
  ) {
    self.filePaths = filePaths
    self.version = version
    self.usesFlashAttention = usesFlashAttention
    self.injectEmbeddings = injectEmbeddings
    self.externalOnDemand = externalOnDemand
    self.maxLength = maxLength
    self.clipSkip = clipSkip
    self.lora = lora.filter { $0.version == version }
  }
}

extension TextEncoder {
  private func encodeKandinsky(
    tokens: [DynamicGraph.Tensor<Int32>], positions: [DynamicGraph.Tensor<Int32>]
  ) -> ([DynamicGraph.Tensor<FloatType>], [Model]) {
    let graph = tokens[0].graph
    let tokensTensor = tokens[0]
    var unconditionalTokenLength: Int? = nil
    var tokenLength: Int? = nil
    for i in 0..<77 {
      if tokensTensor[i] == 2 && unconditionalTokenLength == nil {
        unconditionalTokenLength = i + 1
      }
      if tokensTensor[i + 77] == 2 && tokenLength == nil {
        tokenLength = i + 1
      }
    }
    let attentionMask = graph.variable(.CPU, .NHWC(2, 1, 1, 77), of: FloatType.self)
    for i in 0..<77 {
      attentionMask[0, 0, 0, i] = 0
      attentionMask[1, 0, 0, i] = 0
    }
    if let unconditionalTokenLength = unconditionalTokenLength {
      for i in unconditionalTokenLength..<77 {
        attentionMask[0, 0, 0, i] = -FloatType.greatestFiniteMagnitude
      }
    }
    if let tokenLength = tokenLength {
      for i in tokenLength..<77 {
        attentionMask[1, 0, 0, i] = -FloatType.greatestFiniteMagnitude
      }
    }
    var causalAttentionMask = Tensor<FloatType>(
      Array(repeating: 0, count: maxLength * maxLength), .CPU, .NHWC(1, 1, maxLength, maxLength)
    )
    for i in 0..<(maxLength - 1) {
      for j in (i + 1)..<maxLength {
        causalAttentionMask[0, 0, i, j] = -FloatType.greatestFiniteMagnitude
      }
    }
    var fullEmb: DynamicGraph.Tensor<FloatType>? = nil
    var poolEmb: DynamicGraph.Tensor<FloatType>? = nil
    let externalData: DynamicGraph.Store.Codec =
      externalOnDemand ? .externalOnDemand : .externalData
    graph.openStore(
      filePaths[0], flags: .readOnly,
      externalStore: TensorData.externalStore(filePath: filePaths[0])
    ) {
      let tokensTensorGPU = tokensTensor.toGPU(0)
      let positionTensorGPU = positions[0].toGPU(0)
      let tokenTypesTensor = graph.variable(.CPU, .C(2 * 77), of: Int32.self)
      for i in 0..<(2 * 77) {
        tokenTypesTensor[i] = 0
      }
      let tokenTypesTensorGPU = tokenTypesTensor.toGPU(0)
      let attentionMaskGPU = attentionMask.toGPU(0)
      let textEncoder = XLMRobertaTextEmbedding(
        FloatType.self, prefix: "model.transformer.embeddings", vocabularySize: 250_002,
        maxLength: 514, tokenTypes: 1, embeddingSize: 1_024)
      textEncoder.compile(inputs: tokensTensorGPU, positionTensorGPU, tokenTypesTensorGPU)
      $0.read("embedding", model: textEncoder, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
      let embeddings = textEncoder(inputs: tokensTensorGPU, positionTensorGPU, tokenTypesTensorGPU)[
        0
      ].as(of: FloatType.self)
      let layer = XLMRobertaModel(numberOfLayers: 24, k: 64, h: 16, b: 2, t: 77)
      layer.compile(inputs: embeddings, attentionMaskGPU)
      $0.read("roberta", model: layer, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
      let textEncoderEmb = layer(inputs: embeddings, attentionMaskGPU)[0].as(of: FloatType.self)
        .reshaped(.HWC(2, 77, 1024))
      fullEmb = textEncoderEmb
      let poolingMask = graph.variable(.CPU, .HWC(2, 1, 77), of: FloatType.self)
      let weightedMask = graph.variable(.CPU, .HWC(2, 1, 1), of: FloatType.self)
      for i in 0..<77 {
        poolingMask[0, 0, i] = i < (unconditionalTokenLength ?? 77) ? 1 : 0
        poolingMask[1, 0, i] = i < (tokenLength ?? 77) ? 1 : 0
      }
      weightedMask[0, 0, 0] = FloatType(1 / Float(unconditionalTokenLength ?? 77))
      weightedMask[1, 0, 0] = FloatType(1 / Float(tokenLength ?? 77))
      let middlePoolEmb = weightedMask.toGPU(0) .* (poolingMask.toGPU(0) * textEncoderEmb)
      let linearTransformation = Dense(count: 768)
      linearTransformation.compile(inputs: middlePoolEmb)
      $0.read(
        "linear_transformation", model: linearTransformation,
        codec: [.jit, .q6p, .q8p, .ezm7, externalData])
      poolEmb = linearTransformation(inputs: middlePoolEmb)[0].as(of: FloatType.self)
    }
    var CLIPTextEmb: DynamicGraph.Tensor<FloatType>? = nil
    var CLIPTextEnc: DynamicGraph.Tensor<FloatType>? = nil
    graph.openStore(
      filePaths[1], flags: .readOnly,
      externalStore: TensorData.externalStore(filePath: filePaths[1])
    ) { store in
      let tokensTensor = tokens[1]
      var unconditionalTokenLength = 77
      var tokenLength = 77
      for i in 0..<77 {
        if tokensTensor[i] == 49407 && unconditionalTokenLength == 77 {
          unconditionalTokenLength = i + 1
        }
        if tokensTensor[i + 77] == 49407 && tokenLength == 77 {
          tokenLength = i + 1
        }
      }
      let CLIPTokensTensorGPU = tokensTensor.toGPU(0)
      let CLIPPositionTensorGPU = positions[1].toGPU(0)
      let causalAttentionMaskGPU = graph.variable(causalAttentionMask.toGPU())
      let textModel = CLIPTextModel(
        FloatType.self, injectEmbeddings: false,
        vocabularySize: 49408, maxLength: 77, maxTokenLength: maxLength, embeddingSize: 768,
        numLayers: 12, numHeads: 12, batchSize: 3, intermediateSize: 3072,
        usesFlashAttention: usesFlashAttention
      ).0
      textModel.compile(inputs: CLIPTokensTensorGPU, CLIPPositionTensorGPU, causalAttentionMaskGPU)
      if lora.count > 0 {
        LoRALoader<FloatType>.openStore(graph, lora: lora) { loader in
          if clipSkip > 1 {
            store.read(
              "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
            ) { name, _, _, shape in
              // Retrieve the right final layer norm parameters.
              var name = name
              if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-0]" {
                name = "__text_model__[t-98-0]"
              } else if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-1]" {
                name = "__text_model__[t-98-1]"
              }
              return loader.mergeLoRA(graph, name: name, store: store, shape: shape)
            }
          } else {
            store.read(
              "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
            ) { name, _, _, shape in
              return loader.mergeLoRA(graph, name: name, store: store, shape: shape)
            }
          }
        }
      } else {
        if clipSkip > 1 {
          store.read(
            "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
          ) { name, _, _, _ in
            // Retrieve the right final layer norm parameters.
            var name = name
            if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-0]" {
              name = "__text_model__[t-98-0]"
            } else if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-1]" {
              name = "__text_model__[t-98-1]"
            }
            return .continue(name)
          }
        } else {
          store.read(
            "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
        }
      }
      let c = textModel(inputs: CLIPTokensTensorGPU, CLIPPositionTensorGPU, causalAttentionMaskGPU)[
        0
      ].as(of: FloatType.self)
      let tensorIndex = graph.variable(.CPU, .C(3), of: Int32.self)
      tensorIndex[0] = Int32(unconditionalTokenLength) - 1
      tensorIndex[1] = Int32(tokenLength) + 77 - 1
      tensorIndex[2] = 77 * 2 + 1
      CLIPTextEmb = Functional.indexSelect(
        input: c.reshaped(.WC(3 * 77, 768)), index: tensorIndex.toGPU(0))
      CLIPTextEnc = c.reshaped(.HWC(3, 77, 768))
    }
    return ([fullEmb!, poolEmb!, CLIPTextEnc!, CLIPTextEmb!], [])
  }

  private func encodeSDXL(
    tokens: [DynamicGraph.Tensor<Int32>], positions: [DynamicGraph.Tensor<Int32>],
    mask: [DynamicGraph.Tensor<FloatType>], injectedEmbeddings: [DynamicGraph.Tensor<FloatType>],
    lengthsOfUncond: [Int], lengthsOfCond: [Int], textModels existingTextModels: [Model?]
  )
    -> ([DynamicGraph.Tensor<FloatType>], [Model])
  {
    var causalAttentionMask = Tensor<FloatType>(
      Array(repeating: 0, count: 2 * maxLength * maxLength), .CPU, .NHWC(2, 1, maxLength, maxLength)
    )
    for i in 0..<(maxLength - 1) {
      for j in (i + 1)..<maxLength {
        causalAttentionMask[0, 0, i, j] = -FloatType.greatestFiniteMagnitude
        causalAttentionMask[1, 0, i, j] = -FloatType.greatestFiniteMagnitude
      }
    }
    var j = 0
    var prefixLength = 0
    for i in 0..<maxLength {
      // Mask out anything before this, except padding / ending.
      guard j < lengthsOfUncond.count else { break }
      if i - 1 >= lengthsOfUncond[j] + prefixLength {
        prefixLength += lengthsOfUncond[j]
        j += 1
      }
      if prefixLength > 0 && j < lengthsOfUncond.count {
        for k in 1..<(prefixLength + 1) {
          causalAttentionMask[0, 0, i, k] = -FloatType.greatestFiniteMagnitude
        }
      }
    }
    j = 0
    prefixLength = 0
    for i in 0..<maxLength {
      // Mask out anything before this, except padding / ending.
      guard j < lengthsOfCond.count else { break }
      if i - 1 >= lengthsOfCond[j] + prefixLength {
        prefixLength += lengthsOfCond[j]
        j += 1
      }
      if prefixLength > 0 && j < lengthsOfCond.count {
        for k in 1..<(prefixLength + 1) {
          causalAttentionMask[1, 0, i, k] = -FloatType.greatestFiniteMagnitude
        }
      }
    }
    let graph = tokens[0].graph
    let tokens0TensorGPU = tokens[0].toGPU(0)
    let positionTensorGPU = positions[0].toGPU(0)
    let causalAttentionMaskGPU = graph.variable(causalAttentionMask.toGPU())
    let maskGPU = mask.map { $0.toGPU(0) }
    let injectedEmbeddingsGPU = injectedEmbeddings.map { $0.toGPU(0) }
    let externalData: DynamicGraph.Store.Codec =
      externalOnDemand ? .externalOnDemand : .externalData
    var textModel: Model
    textModel =
      CLIPTextModel(
        FloatType.self, injectEmbeddings: injectEmbeddings,
        vocabularySize: 49408, maxLength: 77, maxTokenLength: maxLength, embeddingSize: 768,
        numLayers: 13 - min(max(clipSkip, 1), 12), numHeads: 12, batchSize: 2,
        intermediateSize: 3072, usesFlashAttention: usesFlashAttention, noFinalLayerNorm: true
      ).0
    if let maskGPU = maskGPU.first, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.first {
      textModel.compile(
        inputs: tokens0TensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
        injectedEmbeddingsGPU)
    } else {
      textModel.compile(inputs: tokens0TensorGPU, positionTensorGPU, causalAttentionMaskGPU)
    }
    let c0: DynamicGraph.Tensor<FloatType>
    if filePaths.count > 1 {
      graph.openStore(
        filePaths[1], flags: .readOnly,
        externalStore: TensorData.externalStore(filePath: filePaths[1])
      ) { store in
        if lora.count > 0 {
          LoRALoader<FloatType>.openStore(graph, lora: lora) { loader in
            store.read(
              "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
            ) { name, _, _, shape in
              var name = name
              if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-0]" {
                name = "__text_model__[t-98-0]"
              } else if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-1]" {
                name = "__text_model__[t-98-1]"
              }
              return loader.mergeLoRA(graph, name: name, store: store, shape: shape)
            }
          }
        } else {
          if clipSkip > 1 {
            store.read(
              "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
            ) { name, _, _, _ in
              // Retrieve the right final layer norm parameters.
              var name = name
              if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-0]" {
                name = "__text_model__[t-98-0]"
              } else if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-1]" {
                name = "__text_model__[t-98-1]"
              }
              return .continue(name)
            }
          } else {
            store.read(
              "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
          }
        }
      }
      if let maskGPU = maskGPU.first, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.first {
        c0 = textModel(
          inputs: tokens0TensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
          injectedEmbeddingsGPU)[0].as(
            of: FloatType.self
          ).reshaped(.HWC(2, maxLength, 768))
      } else {
        c0 = textModel(
          inputs: tokens0TensorGPU, positionTensorGPU, causalAttentionMaskGPU)[0].as(
            of: FloatType.self
          ).reshaped(.HWC(2, maxLength, 768))
      }
    } else {
      c0 = graph.variable(.GPU(0), .HWC(2, maxLength, 768))
      c0.full(0)
    }
    let tokens1TensorGPU = tokens[1].toGPU(0)
    if let existingTextModel = existingTextModels[0] {
      textModel = existingTextModel
    } else {
      textModel =
        OpenCLIPTextModel(
          FloatType.self, injectEmbeddings: injectEmbeddings,
          vocabularySize: 49408, maxLength: 77, maxTokenLength: maxLength, embeddingSize: 1280,
          numLayers: 32 - min(max(clipSkip - 1, 0), 30), numHeads: 20, batchSize: 2,
          intermediateSize: 5120, usesFlashAttention: usesFlashAttention, outputPenultimate: true
        ).0
    }
    if let maskGPU = maskGPU.last, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.last {
      textModel.compile(
        inputs: tokens1TensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
        injectedEmbeddingsGPU)
    } else {
      textModel.compile(
        inputs: tokens1TensorGPU, positionTensorGPU, causalAttentionMaskGPU)
    }
    let textProjection = graph.variable(.GPU(0), .WC(1280, 1280), of: FloatType.self)
    graph.openStore(
      filePaths[0], flags: .readOnly,
      externalStore: TensorData.externalStore(filePath: filePaths[0])
    ) { store in
      if lora.count > 0 {
        LoRALoader<FloatType>.openStore(graph, lora: lora) { loader in
          store.read(
            "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
          ) { name, _, _, shape in
            // Retrieve the right final layer norm parameters.
            var name = name
            if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-0]" {
              name = "__text_model__[t-258-0]"
            } else if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-1]" {
              name = "__text_model__[t-258-1]"
            }
            return loader.mergeLoRA(graph, name: name, store: store, shape: shape, prefix: "__te2")
          }
        }
      } else if clipSkip > 1 {
        store.read("text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]) {
          name, _, _, _ in
          // Retrieve the right final layer norm parameters.
          var name = name
          if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-0]" {
            name = "__text_model__[t-258-0]"
          } else if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-1]" {
            name = "__text_model__[t-258-1]"
          }
          return .continue(name)
        }
      } else {
        store.read("text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
      }
      store.read(
        "text_projection", variable: textProjection, codec: [.q6p, .q8p, .ezm7, .externalData])
    }
    let c1Out: [DynamicGraph.Tensor<FloatType>]
    if let maskGPU = maskGPU.last, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.last {
      c1Out = textModel(
        inputs: tokens1TensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
        injectedEmbeddingsGPU
      ).map { $0.as(of: FloatType.self) }
    } else {
      c1Out = textModel(
        inputs: tokens1TensorGPU, positionTensorGPU, causalAttentionMaskGPU
      ).map { $0.as(of: FloatType.self) }
    }
    let c1 = c1Out[0].reshaped(.HWC(2, maxLength, 1280))
    var pooled = graph.variable(.GPU(0), .WC(2, 1280), of: FloatType.self)
    var unconditionalTokenEnd: Int? = nil
    var tokenEnd: Int? = nil
    if mask.count > 1 {
      for i in 0..<maxLength {
        if tokens[1][i] == 49407 && mask[1][i, 0] > 0 && unconditionalTokenEnd == nil {
          unconditionalTokenEnd = i
        }
        if tokens[1][i + maxLength] == 49407 && mask[1][i + maxLength, 0] > 0 && tokenEnd == nil {
          tokenEnd = i
        }
      }
    } else {
      for i in 0..<maxLength {
        if tokens[1][i] == 49407 && unconditionalTokenEnd == nil {
          unconditionalTokenEnd = i
        }
        if tokens[1][i + maxLength] == 49407 && tokenEnd == nil {
          tokenEnd = i
        }
      }
    }
    if let unconditionalTokenEnd = unconditionalTokenEnd, let tokenEnd = tokenEnd {
      pooled[0..<1, 0..<1280] =
        c1Out[1][unconditionalTokenEnd..<(unconditionalTokenEnd + 1), 0..<1280] * textProjection
      pooled[1..<2, 0..<1280] =
        c1Out[1][(maxLength + tokenEnd)..<(maxLength + tokenEnd + 1), 0..<1280] * textProjection
    }
    return ([c0, c1, pooled], [textModel])
  }

  private func encodeI2v(
    image: [DynamicGraph.Tensor<FloatType>], textModels existingTextModels: [Model?]
  ) -> ([DynamicGraph.Tensor<FloatType>], [Model]) {
    let graph = image[0].graph
    let vit: Model
    let mean = graph.variable(
      Tensor<FloatType>(
        [
          FloatType(2 * 0.48145466 - 1), FloatType(2 * 0.4578275 - 1),
          FloatType(2 * 0.40821073 - 1),
        ], .GPU(0), .NHWC(1, 1, 1, 3)))
    let invStd = graph.variable(
      Tensor<FloatType>(
        [
          FloatType(0.5 / 0.26862954), FloatType(0.5 / 0.26130258), FloatType(0.5 / 0.27577711),
        ],
        .GPU(0), .NHWC(1, 1, 1, 3)))
    var input = image[0]
    let inputHeight = input.shape[1]
    let inputWidth = input.shape[2]
    precondition(input.shape[3] == 3)
    if inputHeight != 224 || inputWidth != 224 {
      input =
        (Upsample(
          .bilinear, widthScale: Float(224) / Float(inputWidth),
          heightScale: Float(224) / Float(inputHeight))(input) - mean) .* invStd
    } else {
      input = (input - mean) .* invStd
    }
    let externalData: DynamicGraph.Store.Codec =
      externalOnDemand ? .externalOnDemand : .externalData
    if existingTextModels.count >= 1, let existingTextModel = existingTextModels[0] {
      vit = existingTextModel
    } else {
      vit = VisionTransformer(
        FloatType.self, grid: 16, width: 1280, outputDim: 1024, layers: 32, heads: 16, batchSize: 1)
      vit.compile(inputs: input)
      graph.openStore(
        filePaths[0], flags: .readOnly,
        externalStore: TensorData.externalStore(filePath: filePaths[0])
      ) {
        $0.read("vision_model", model: vit, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
      }
    }
    let imageEmbeds = vit(inputs: input)[0].as(of: FloatType.self).reshaped(.CHW(1, 1, 1280))
    let visualProj: Model
    if existingTextModels.count >= 2, let existingTextModel = existingTextModels[1] {
      visualProj = existingTextModel
    } else {
      visualProj = Dense(count: 1024, noBias: true)
      visualProj.compile(inputs: imageEmbeds)
      graph.openStore(
        filePaths[1], flags: .readOnly,
        externalStore: TensorData.externalStore(filePath: filePaths[1])
      ) {
        $0.read("visual_proj", model: visualProj, codec: [.jit, .q6p, .q8p, .ezm7, .externalData])
      }
    }
    let imageProj = visualProj(inputs: imageEmbeds)[0].as(of: FloatType.self)
    return ([imageProj], [vit, visualProj])
  }

  private func encodeWurstchen(
    tokens: [DynamicGraph.Tensor<Int32>], positions: [DynamicGraph.Tensor<Int32>],
    mask: [DynamicGraph.Tensor<FloatType>], injectedEmbeddings: [DynamicGraph.Tensor<FloatType>],
    lengthsOfUncond: [Int], lengthsOfCond: [Int], textModels existingTextModels: [Model?]
  )
    -> ([DynamicGraph.Tensor<FloatType>], [Model])
  {
    var causalAttentionMask = Tensor<FloatType>(
      Array(repeating: 0, count: 2 * maxLength * maxLength), .CPU, .NHWC(2, 1, maxLength, maxLength)
    )
    var unconditionalTokenEnd: Int? = nil
    var tokenEnd: Int? = nil
    if mask.count > 1 {
      for i in 0..<maxLength {
        if tokens[0][i] == 49407 && mask[0][i, 0] > 0 && unconditionalTokenEnd == nil {
          unconditionalTokenEnd = i
        }
        if tokens[0][i + maxLength] == 49407 && mask[0][i + maxLength, 0] > 0 && tokenEnd == nil {
          tokenEnd = i
        }
      }
    } else {
      for i in 0..<maxLength {
        if tokens[0][i] == 49407 && unconditionalTokenEnd == nil {
          unconditionalTokenEnd = i
        }
        if tokens[0][i + maxLength] == 49407 && tokenEnd == nil {
          tokenEnd = i
        }
      }
    }
    for i in 0..<maxLength {
      for j in (i + 1)..<maxLength {
        causalAttentionMask[0, 0, i, j] = -FloatType.greatestFiniteMagnitude
        causalAttentionMask[1, 0, i, j] = -FloatType.greatestFiniteMagnitude
      }
      // For Wurstchen, padding tokens are masked out.
      if tokens[0][i] == 49407, let unconditionalTokenEnd = unconditionalTokenEnd,
        i > unconditionalTokenEnd
      {
        for j in (unconditionalTokenEnd + 1)..<(i + 1) {
          causalAttentionMask[0, 0, i, j] = -FloatType.greatestFiniteMagnitude
        }
      }
      if tokens[0][i + maxLength] == 49407, let tokenEnd = tokenEnd, i > tokenEnd {
        for j in (tokenEnd + 1)..<(i + 1) {
          causalAttentionMask[1, 0, i, j] = -FloatType.greatestFiniteMagnitude
        }
      }
    }
    var j = 0
    var prefixLength = 0
    for i in 0..<maxLength {
      // Mask out anything before this, except padding / ending.
      guard j < lengthsOfUncond.count else { break }
      if i - 1 >= lengthsOfUncond[j] + prefixLength {
        prefixLength += lengthsOfUncond[j]
        j += 1
      }
      if prefixLength > 0 && j < lengthsOfUncond.count {
        for k in 1..<(prefixLength + 1) {
          causalAttentionMask[0, 0, i, k] = -FloatType.greatestFiniteMagnitude
        }
      }
    }
    j = 0
    prefixLength = 0
    for i in 0..<maxLength {
      // Mask out anything before this, except padding / ending.
      guard j < lengthsOfCond.count else { break }
      if i - 1 >= lengthsOfCond[j] + prefixLength {
        prefixLength += lengthsOfCond[j]
        j += 1
      }
      if prefixLength > 0 && j < lengthsOfCond.count {
        for k in 1..<(prefixLength + 1) {
          causalAttentionMask[1, 0, i, k] = -FloatType.greatestFiniteMagnitude
        }
      }
    }
    let graph = tokens[0].graph
    let tokensTensorGPU = tokens[0].toGPU(0)
    let positionTensorGPU = positions[0].toGPU(0)
    let causalAttentionMaskGPU = graph.variable(causalAttentionMask.toGPU())
    let maskGPU = mask.map { $0.toGPU(0) }
    let injectedEmbeddingsGPU = injectedEmbeddings.map { $0.toGPU(0) }
    let textModel: Model
    let externalData: DynamicGraph.Store.Codec =
      externalOnDemand ? .externalOnDemand : .externalData
    if let existingTextModel = existingTextModels[0] {
      textModel = existingTextModel
    } else {
      textModel =
        OpenCLIPTextModel(
          FloatType.self, injectEmbeddings: injectEmbeddings,
          vocabularySize: 49408, maxLength: 77, maxTokenLength: maxLength, embeddingSize: 1280,
          numLayers: 32 - min(max(clipSkip - 1, 0), 30), numHeads: 20, batchSize: 2,
          intermediateSize: 5120, usesFlashAttention: usesFlashAttention, outputHiddenState: true
        ).0
    }
    if let maskGPU = maskGPU.last, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.last {
      textModel.compile(
        inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
        injectedEmbeddingsGPU)
    } else {
      textModel.compile(
        inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU)
    }
    let textProjection = graph.variable(.GPU(0), .WC(1280, 1280), of: FloatType.self)
    graph.openStore(
      filePaths[0], flags: .readOnly,
      externalStore: TensorData.externalStore(filePath: filePaths[0])
    ) { store in
      if lora.count > 0 {
        LoRALoader<FloatType>.openStore(graph, lora: lora) { loader in
          store.read(
            "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
          ) { name, _, _, shape in
            // Retrieve the right final layer norm parameters.
            var name = name
            if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-0]" {
              name = "__text_model__[t-258-0]"
            } else if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-1]" {
              name = "__text_model__[t-258-1]"
            }
            return loader.mergeLoRA(graph, name: name, store: store, shape: shape, prefix: "__te2")
          }
        }
      } else if clipSkip > 1 {
        store.read("text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]) {
          name, _, _, _ in
          // Retrieve the right final layer norm parameters.
          var name = name
          if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-0]" {
            name = "__text_model__[t-258-0]"
          } else if name == "__text_model__[t-\(258 - (min(clipSkip, 31) - 1) * 8)-1]" {
            name = "__text_model__[t-258-1]"
          }
          return .continue(name)
        }
      } else {
        store.read("text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
      }
      store.read(
        "text_projection", variable: textProjection, codec: [.q6p, .q8p, .ezm7, .externalData])
    }
    let cOut: [DynamicGraph.Tensor<FloatType>]
    if let maskGPU = maskGPU.last, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.last {
      cOut = textModel(
        inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
        injectedEmbeddingsGPU
      ).map { $0.as(of: FloatType.self) }
    } else {
      cOut = textModel(
        inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU
      ).map { $0.as(of: FloatType.self) }
    }
    let c = cOut[0].reshaped(.HWC(2, maxLength, 1280))
    var pooled = graph.variable(.GPU(0), .WC(2, 1280), of: FloatType.self)
    if let unconditionalTokenEnd = unconditionalTokenEnd, let tokenEnd = tokenEnd {
      pooled[0..<1, 0..<1280] =
        cOut[1][unconditionalTokenEnd..<(unconditionalTokenEnd + 1), 0..<1280] * textProjection
      pooled[1..<2, 0..<1280] =
        cOut[1][(maxLength + tokenEnd)..<(maxLength + tokenEnd + 1), 0..<1280] * textProjection
    }
    return ([c, pooled], [textModel])
  }

  public func encode(
    tokens: [DynamicGraph.Tensor<Int32>], positions: [DynamicGraph.Tensor<Int32>],
    mask: [DynamicGraph.Tensor<FloatType>], injectedEmbeddings: [DynamicGraph.Tensor<FloatType>],
    image: [DynamicGraph.Tensor<FloatType>], lengthsOfUncond: [Int], lengthsOfCond: [Int],
    textModels existingTextModels: [Model?]
  )
    -> ([DynamicGraph.Tensor<FloatType>], [Model])
  {
    let conditionalLength: Int
    switch version {
    case .v1:
      conditionalLength = 768
    case .v2:
      conditionalLength = 1024
    case .kandinsky21:
      return encodeKandinsky(tokens: tokens, positions: positions)
    case .sdxlBase, .sdxlRefiner, .ssd1b:
      return encodeSDXL(
        tokens: tokens, positions: positions, mask: mask, injectedEmbeddings: injectedEmbeddings,
        lengthsOfUncond: lengthsOfUncond, lengthsOfCond: lengthsOfCond,
        textModels: existingTextModels)
    case .svdI2v:
      return encodeI2v(image: image, textModels: existingTextModels)
    case .wurstchenStageC, .wurstchenStageB:
      return encodeWurstchen(
        tokens: tokens, positions: positions, mask: mask, injectedEmbeddings: injectedEmbeddings,
        lengthsOfUncond: lengthsOfUncond, lengthsOfCond: lengthsOfCond,
        textModels: existingTextModels)
    }
    var causalAttentionMask = Tensor<FloatType>(
      Array(repeating: 0, count: 2 * maxLength * maxLength), .CPU, .NHWC(2, 1, maxLength, maxLength)
    )
    for i in 0..<(maxLength - 1) {
      for j in (i + 1)..<maxLength {
        causalAttentionMask[0, 0, i, j] = -FloatType.greatestFiniteMagnitude
        causalAttentionMask[1, 0, i, j] = -FloatType.greatestFiniteMagnitude
      }
    }
    var j = 0
    var prefixLength = 0
    for i in 0..<maxLength {
      // Mask out anything before this, except padding / ending.
      guard j < lengthsOfUncond.count else { break }
      if i - 1 >= lengthsOfUncond[j] + prefixLength {
        prefixLength += lengthsOfUncond[j]
        j += 1
      }
      if prefixLength > 0 && j < lengthsOfUncond.count {
        for k in 1..<(prefixLength + 1) {
          causalAttentionMask[0, 0, i, k] = -FloatType.greatestFiniteMagnitude
        }
      }
    }
    j = 0
    prefixLength = 0
    for i in 0..<maxLength {
      // Mask out anything before this, except padding / ending.
      guard j < lengthsOfCond.count else { break }
      if i - 1 >= lengthsOfCond[j] + prefixLength {
        prefixLength += lengthsOfCond[j]
        j += 1
      }
      if prefixLength > 0 && j < lengthsOfCond.count {
        for k in 1..<(prefixLength + 1) {
          causalAttentionMask[1, 0, i, k] = -FloatType.greatestFiniteMagnitude
        }
      }
    }
    let graph = tokens[0].graph
    let tokensTensorGPU = tokens[0].toGPU(0)
    let positionTensorGPU = positions[0].toGPU(0)
    let causalAttentionMaskGPU = graph.variable(causalAttentionMask.toGPU())
    let maskGPU = mask.map { $0.toGPU(0) }
    let injectedEmbeddingsGPU = injectedEmbeddings.map { $0.toGPU(0) }
    let textModel: Model
    let externalData: DynamicGraph.Store.Codec =
      externalOnDemand ? .externalOnDemand : .externalData
    if let existingTextModel = existingTextModels[0] {
      textModel = existingTextModel
    } else {
      switch version {
      case .v1:
        textModel =
          CLIPTextModel(
            FloatType.self, injectEmbeddings: injectEmbeddings,
            vocabularySize: 49408, maxLength: 77, maxTokenLength: maxLength, embeddingSize: 768,
            numLayers: 13 - min(max(clipSkip, 1), 12), numHeads: 12, batchSize: 2,
            intermediateSize: 3072, usesFlashAttention: usesFlashAttention
          ).0
      case .v2:
        textModel =
          OpenCLIPTextModel(
            FloatType.self, injectEmbeddings: injectEmbeddings,
            vocabularySize: 49408, maxLength: 77, maxTokenLength: maxLength, embeddingSize: 1024,
            numLayers: 24 - min(max(clipSkip, 1), 23), numHeads: 16, batchSize: 2,
            intermediateSize: 4096, usesFlashAttention: usesFlashAttention
          ).0
      case .kandinsky21, .sdxlBase, .sdxlRefiner, .ssd1b, .svdI2v, .wurstchenStageC,
        .wurstchenStageB:
        fatalError()
      }
      if let maskGPU = maskGPU.first, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.first {
        textModel.compile(
          inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
          injectedEmbeddingsGPU)
      } else {
        textModel.compile(inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU)
      }
      graph.openStore(
        filePaths[0], flags: .readOnly,
        externalStore: TensorData.externalStore(filePath: filePaths[0])
      ) { store in
        if lora.count > 0 {
          LoRALoader<FloatType>.openStore(graph, lora: lora) { loader in
            if clipSkip > 1 {
              store.read(
                "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
              ) { name, _, _, shape in
                // Retrieve the right final layer norm parameters.
                var name = name
                switch version {
                case .v1:
                  if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-0]" {
                    name = "__text_model__[t-98-0]"
                  } else if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-1]" {
                    name = "__text_model__[t-98-1]"
                  }
                case .v2:
                  if name == "__text_model__[t-\(186 - (min(clipSkip, 23) - 1) * 8)-0]" {
                    name = "__text_model__[t-186-0]"
                  } else if name == "__text_model__[t-\(186 - (min(clipSkip, 23) - 1) * 8)-1]" {
                    name = "__text_model__[t-186-1]"
                  }
                case .kandinsky21, .sdxlBase, .sdxlRefiner, .ssd1b, .svdI2v, .wurstchenStageC,
                  .wurstchenStageB:
                  fatalError()
                }
                return loader.mergeLoRA(graph, name: name, store: store, shape: shape)
              }
            } else {
              store.read(
                "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
              ) { name, _, _, shape in
                return loader.mergeLoRA(graph, name: name, store: store, shape: shape)
              }
            }
          }
        } else {
          if clipSkip > 1 {
            store.read(
              "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData]
            ) { name, _, _, _ in
              // Retrieve the right final layer norm parameters.
              var name = name
              switch version {
              case .v1:
                if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-0]" {
                  name = "__text_model__[t-98-0]"
                } else if name == "__text_model__[t-\(98 - (min(clipSkip, 12) - 1) * 8)-1]" {
                  name = "__text_model__[t-98-1]"
                }
              case .v2:
                if name == "__text_model__[t-\(186 - (min(clipSkip, 23) - 1) * 8)-0]" {
                  name = "__text_model__[t-186-0]"
                } else if name == "__text_model__[t-\(186 - (min(clipSkip, 23) - 1) * 8)-1]" {
                  name = "__text_model__[t-186-1]"
                }
              case .kandinsky21, .sdxlBase, .sdxlRefiner, .ssd1b, .svdI2v, .wurstchenStageC,
                .wurstchenStageB:
                fatalError()
              }
              return .continue(name)
            }
          } else {
            store.read(
              "text_model", model: textModel, codec: [.jit, .q6p, .q8p, .ezm7, externalData])
          }
        }
      }
    }
    if let maskGPU = maskGPU.first, let injectedEmbeddingsGPU = injectedEmbeddingsGPU.first {
      return (
        [
          textModel(
            inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU, maskGPU,
            injectedEmbeddingsGPU)[0].as(
              of: FloatType.self
            ).reshaped(.HWC(2, maxLength, conditionalLength))
        ], [textModel]
      )
    } else {
      return (
        [
          textModel(
            inputs: tokensTensorGPU, positionTensorGPU, causalAttentionMaskGPU)[0].as(
              of: FloatType.self
            ).reshaped(.HWC(2, maxLength, conditionalLength))
        ], [textModel]
      )
    }
  }
}
