import Foundation
import NNC

public struct DPMPPSDESampler<
  FloatType: TensorNumeric & BinaryFloatingPoint, UNet: UNetProtocol,
  Discretization: Denoiser.Discretization
>
where UNet.FloatType == FloatType {
  public let filePath: String
  public let modifier: SamplerModifier
  public let version: ModelVersion
  public let usesFlashAttention: Bool
  public let upcastAttention: Bool
  public let externalOnDemand: Bool
  public let injectControls: Bool
  public let injectT2IAdapters: Bool
  public let injectIPAdapterLengths: [Int]
  public let lora: [LoRAConfiguration]
  public let classifierFreeGuidance: Bool
  public let is8BitModel: Bool
  public let canRunLoRASeparately: Bool
  public let conditioning: Denoiser.Conditioning
  public let tiledDiffusion: TiledDiffusionConfiguration
  private let discretization: Discretization
  public init(
    filePath: String, modifier: SamplerModifier, version: ModelVersion, usesFlashAttention: Bool,
    upcastAttention: Bool, externalOnDemand: Bool, injectControls: Bool,
    injectT2IAdapters: Bool, injectIPAdapterLengths: [Int], lora: [LoRAConfiguration],
    classifierFreeGuidance: Bool, is8BitModel: Bool, canRunLoRASeparately: Bool,
    conditioning: Denoiser.Conditioning, tiledDiffusion: TiledDiffusionConfiguration,
    discretization: Discretization
  ) {
    self.filePath = filePath
    self.modifier = modifier
    self.version = version
    self.usesFlashAttention = usesFlashAttention
    self.upcastAttention = upcastAttention
    self.externalOnDemand = externalOnDemand
    self.injectControls = injectControls
    self.injectT2IAdapters = injectT2IAdapters
    self.injectIPAdapterLengths = injectIPAdapterLengths
    self.lora = lora
    self.classifierFreeGuidance = classifierFreeGuidance
    self.is8BitModel = is8BitModel
    self.canRunLoRASeparately = canRunLoRASeparately
    self.conditioning = conditioning
    self.tiledDiffusion = tiledDiffusion
    self.discretization = discretization
  }
}

extension DPMPPSDESampler: Sampler {
  public func sample(
    _ x_T: DynamicGraph.Tensor<FloatType>, unets existingUNets: [UNet?],
    sample: DynamicGraph.Tensor<FloatType>?, maskedImage: DynamicGraph.Tensor<FloatType>?,
    depthImage: DynamicGraph.Tensor<FloatType>?,
    mask: DynamicGraph.Tensor<FloatType>?, negMask: DynamicGraph.Tensor<FloatType>?,
    conditioning c: [DynamicGraph.Tensor<FloatType>], tokenLengthUncond: Int, tokenLengthCond: Int,
    extraProjection: DynamicGraph.Tensor<FloatType>?,
    injectedControls: [(
      model: ControlModel<FloatType>, hints: [([DynamicGraph.Tensor<FloatType>], Float)]
    )],
    textGuidanceScale: Float, imageGuidanceScale: Float,
    startStep: (integral: Int, fractional: Float), endStep: (integral: Int, fractional: Float),
    originalSize: (width: Int, height: Int), cropTopLeft: (top: Int, left: Int),
    targetSize: (width: Int, height: Int), aestheticScore: Float,
    negativeOriginalSize: (width: Int, height: Int), negativeAestheticScore: Float,
    zeroNegativePrompt: Bool, refiner: Refiner?, fpsId: Int, motionBucketId: Int, condAug: Float,
    startFrameCfg: Float, sharpness: Float, sampling: Sampling,
    feedback: (Int, Tensor<FloatType>?) -> Bool
  ) -> Result<SamplerOutput<FloatType, UNet>, Error> {
    var x = x_T
    var c0 = c[0]
    let batchSize = x.shape[0]
    let startHeight = x.shape[1]
    let startWidth = x.shape[2]
    let channels = x.shape[3]
    let graph = x.graph
    var isCfgEnabled =
      classifierFreeGuidance
      && isCfgEnabled(
        textGuidanceScale: textGuidanceScale, startFrameCfg: startFrameCfg, version: version)
    let cfgChannels: Int
    let inChannels: Int
    if version == .svdI2v {
      cfgChannels = 1
      inChannels = channels * 2
    } else {
      switch modifier {
      case .inpainting:
        cfgChannels = isCfgEnabled ? 2 : 1
        inChannels = channels * 2 + 1
      case .depth:
        cfgChannels = isCfgEnabled ? 2 : 1
        inChannels = channels + 1
      case .editing:
        cfgChannels = 3
        inChannels = channels * 2
        isCfgEnabled = true
      case .none:
        cfgChannels = isCfgEnabled ? 2 : 1
        inChannels = channels
      }
    }
    var xIn = graph.variable(
      .GPU(0), .NHWC(cfgChannels * batchSize, startHeight, startWidth, inChannels),
      of: FloatType.self
    )
    switch modifier {
    case .inpainting:
      let maskedImage = maskedImage!
      let mask = mask!
      for i in 0..<batchSize {
        xIn[i..<(i + 1), 0..<startHeight, 0..<startWidth, channels..<(channels + 1)] = mask
        xIn[i..<(i + 1), 0..<startHeight, 0..<startWidth, (channels + 1)..<(channels * 2 + 1)] =
          maskedImage
        if isCfgEnabled {
          xIn[
            (batchSize + i)..<(batchSize + i + 1), 0..<startHeight, 0..<startWidth,
            channels..<(channels + 1)] = mask
          xIn[
            (batchSize + i)..<(batchSize + i + 1), 0..<startHeight, 0..<startWidth,
            (channels + 1)..<(channels * 2 + 1)] =
            maskedImage
        }
      }
    case .editing:
      let maskedImage = maskedImage!
      for i in 0..<batchSize {
        xIn[i..<(i + 1), 0..<startHeight, 0..<startWidth, channels..<(channels * 2)] = maskedImage
        xIn[
          (batchSize + i)..<(batchSize + i + 1), 0..<startHeight, 0..<startWidth,
          channels..<(channels * 2)] =
          maskedImage
        xIn[
          (batchSize * 2 + i)..<(batchSize * 2 + i + 1), 0..<startHeight, 0..<startWidth,
          channels..<(channels * 2)
        ]
        .full(0)
      }
      let oldC = c0
      c0 = graph.variable(
        .GPU(0), .HWC(3 * batchSize, oldC.shape[1], oldC.shape[2]), of: FloatType.self)
      // Expanding c.
      c0[0..<(batchSize * 2), 0..<oldC.shape[1], 0..<oldC.shape[2]] = oldC
      c0[(batchSize * 2)..<(batchSize * 3), 0..<oldC.shape[1], 0..<oldC.shape[2]] =
        oldC[0..<batchSize, 0..<oldC.shape[1], 0..<oldC.shape[2]]
    case .depth:
      let depthImage = depthImage!
      for i in 0..<batchSize {
        xIn[i..<(i + 1), 0..<startHeight, 0..<startWidth, channels..<(channels + 1)] = depthImage
        if isCfgEnabled {
          xIn[
            (batchSize + i)..<(batchSize + i + 1), 0..<startHeight, 0..<startWidth,
            channels..<(channels + 1)] =
            depthImage
        }
      }
    case .none:
      break
    }
    var c = c
    var extraProjection = extraProjection
    var tokenLengthUncond = tokenLengthUncond
    if !isCfgEnabled && version != .svdI2v {
      for i in 0..<c.count {
        let shape = c[i].shape
        if shape.count == 3 {
          let conditionalLength = version == .kandinsky21 ? shape[1] : tokenLengthCond
          // Only tokenLengthCond is used.
          c[i] = c[i][batchSize..<(batchSize * 2), 0..<conditionalLength, 0..<shape[2]].copied()
        } else if shape.count == 2 {
          c[i] = c[i][batchSize..<(batchSize * 2), 0..<shape[1]].copied()
        }
      }
      if var projection = extraProjection {
        let shape = projection.shape
        if shape.count == 3 {
          // Only tokenLengthCond is used.
          projection = projection[batchSize..<(batchSize * 2), 0..<shape[1], 0..<shape[2]].copied()
        } else if shape.count == 2 {
          projection = projection[batchSize..<(batchSize * 2), 0..<shape[1]].copied()
        }
        extraProjection = projection
      }
      // There is no tokenLengthUncond any more.
      tokenLengthUncond = tokenLengthCond
    }
    let oldC = c
    let fixedEncoder = UNetFixedEncoder<FloatType>(
      filePath: filePath, version: version, usesFlashAttention: usesFlashAttention,
      zeroNegativePrompt: zeroNegativePrompt)
    let injectedControlsC: [[DynamicGraph.Tensor<FloatType>]]
    if c.count >= 2 || version == .svdI2v {
      let vector = fixedEncoder.vector(
        textEmbedding: c[c.count - 1], originalSize: originalSize,
        cropTopLeft: cropTopLeft,
        targetSize: targetSize, aestheticScore: aestheticScore,
        negativeOriginalSize: negativeOriginalSize, negativeAestheticScore: negativeAestheticScore,
        fpsId: fpsId, motionBucketId: motionBucketId, condAug: condAug)
      let (encodings, weightMapper) = fixedEncoder.encode(
        textEncoding: c, batchSize: batchSize, startHeight: startHeight, startWidth: startWidth,
        tokenLengthUncond: tokenLengthUncond, tokenLengthCond: tokenLengthCond, lora: lora)
      c = vector + encodings
      injectedControlsC = injectedControls.map {
        $0.model.encode(
          textEncoding: oldC, vector: vector.first, batchSize: batchSize, startHeight: startHeight,
          startWidth: startWidth, tokenLengthUncond: tokenLengthUncond,
          tokenLengthCond: tokenLengthCond, zeroNegativePrompt: zeroNegativePrompt,
          mainUNetFixed: (fixedEncoder.filePath, weightMapper))
      }
    } else {
      injectedControlsC = injectedControls.map {
        $0.model.encode(
          textEncoding: oldC, vector: nil, batchSize: batchSize, startHeight: startHeight,
          startWidth: startWidth, tokenLengthUncond: tokenLengthUncond,
          tokenLengthCond: tokenLengthCond, zeroNegativePrompt: zeroNegativePrompt,
          mainUNetFixed: (fixedEncoder.filePath, nil))
      }
    }
    var unet = existingUNets[0] ?? UNet()
    var controlNets = [Model?](repeating: nil, count: injectedControls.count)
    if existingUNets[0] == nil {
      let firstTimestep =
        discretization.timesteps - discretization.timesteps / Float(sampling.steps) + 1
      let t = unet.timeEmbed(
        graph: graph, batchSize: cfgChannels * batchSize, timestep: firstTimestep, version: version)
      let (injectedControls, injectedT2IAdapters, injectedIPAdapters) =
        ControlModel<FloatType>
        .emptyInjectedControlsAndAdapters(
          injecteds: injectedControls, step: 0, version: version, inputs: xIn)
      let newC: [DynamicGraph.Tensor<FloatType>]
      if version == .svdI2v {
        newC = Array(c[0..<(1 + (c.count - 1) / 2)])
      } else {
        newC = c
      }
      let _ = unet.compileModel(
        filePath: filePath, externalOnDemand: externalOnDemand, version: version,
        upcastAttention: upcastAttention, usesFlashAttention: usesFlashAttention,
        injectControls: injectControls, injectT2IAdapters: injectT2IAdapters,
        injectIPAdapterLengths: injectIPAdapterLengths, lora: lora,
        is8BitModel: is8BitModel, canRunLoRASeparately: canRunLoRASeparately,
        inputs: xIn, t, newC,
        tokenLengthUncond: tokenLengthUncond, tokenLengthCond: tokenLengthCond,
        extraProjection: extraProjection, injectedControls: injectedControls,
        injectedT2IAdapters: injectedT2IAdapters, injectedIPAdapters: injectedIPAdapters,
        tiledDiffusion: tiledDiffusion)
    }
    let alphasCumprod = discretization.alphasCumprod(steps: sampling.steps, shift: sampling.shift)
    let sigmas = alphasCumprod.map { ((1.0 - $0) / $0).squareRoot() }
    let noise = graph.variable(
      .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
    var brownianNoise = graph.variable(
      .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
    brownianNoise.randn(std: 1, mean: 0)
    let condAugFrames: DynamicGraph.Tensor<FloatType>?
    let textGuidanceVector: DynamicGraph.Tensor<FloatType>?
    if version == .svdI2v {
      let scaleCPU = graph.variable(.CPU, .NHWC(batchSize, 1, 1, 1), of: FloatType.self)
      for i in 0..<batchSize {
        scaleCPU[i, 0, 0, 0] = FloatType(
          Float(i) * (textGuidanceScale - startFrameCfg) / Float(batchSize - 1) + startFrameCfg)
      }
      textGuidanceVector = scaleCPU.toGPU(0)
      let maskedImage = maskedImage!
      var frames = graph.variable(
        .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
      for i in 0..<batchSize {
        frames[i..<(i + 1), 0..<startHeight, 0..<startWidth, 0..<channels] = maskedImage
      }
      if condAug > 0 {
        let noise = graph.variable(like: frames)
        noise.randn(std: condAug)
        frames = frames .+ noise
      }
      condAugFrames = frames
    } else {
      textGuidanceVector = nil
      condAugFrames = nil
    }
    let blur: Model?
    if sharpness > 0 {
      blur = Blur(filters: channels, sigma: 3.0, size: 13, input: x)
    } else {
      blur = nil
    }
    let streamContext = StreamContext(.GPU(0))
    let injecteds = injectedControls
    var refinerKickIn = refiner.map { (1 - $0.start) * discretization.timesteps } ?? -1
    var unets: [UNet?] = [unet]
    var currentModelVersion = version
    let result: Result<SamplerOutput<FloatType, UNet>, Error> = graph.withStream(streamContext) {
      // Now do DPM++ SDE Karras sampling.
      if startStep.fractional == 0 {
        x = Float(sigmas[0]) * x
      }
      var oldDenoised: DynamicGraph.Tensor<FloatType>? = nil
      for i in startStep.integral..<endStep.integral {
        let sigma: Double
        if i == startStep.integral && Float(startStep.integral) != startStep.fractional {
          let lowTimestep = discretization.timestep(
            for: alphasCumprod[max(0, min(Int(startStep.integral), alphasCumprod.count - 1))])
          let highTimestep = discretization.timestep(
            for: alphasCumprod[
              max(0, min(Int(startStep.fractional.rounded(.up)), alphasCumprod.count - 1))])
          let timestep =
            lowTimestep
            + Float(highTimestep - lowTimestep) * (startStep.fractional - Float(startStep.integral))
          let alphaCumprod = discretization.alphaCumprod(timestep: timestep, shift: sampling.shift)
          sigma = ((1.0 - alphaCumprod) / alphaCumprod).squareRoot()
        } else {
          sigma = sigmas[i]
        }
        if i == startStep.integral {
          brownianNoise = Float(sigma.squareRoot()) * brownianNoise
        }
        let alphaCumprod = 1.0 / (sigma * sigma + 1)
        let sqrtAlphaCumprod = alphaCumprod.squareRoot()
        let input: DynamicGraph.Tensor<FloatType>
        switch discretization.objective {
        case .v, .epsilon:
          input = Float(sqrtAlphaCumprod) * x
        case .edm(let sigmaData):
          input = Float(1.0 / (sigma * sigma + sigmaData * sigmaData).squareRoot()) * x
        }
        let rawValue: Tensor<FloatType>? =
          (i > max(startStep.integral, sampling.steps / 2) || i % 5 == 4)
          ? (oldDenoised.map { unet.decode($0) })?.rawValue.toCPU() : nil
        if i % 5 == 4, let rawValue = rawValue {
          if isNaN(rawValue) {
            return .failure(SamplerError.isNaN)
          }
        }
        guard feedback(i - startStep.integral, rawValue) else {
          return .failure(SamplerError.cancelled)
        }
        let timestep = discretization.timestep(for: alphaCumprod)
        if timestep < refinerKickIn, let refiner = refiner {
          unets = [nil]
          let fixedEncoder = UNetFixedEncoder<FloatType>(
            filePath: refiner.filePath, version: refiner.version,
            usesFlashAttention: usesFlashAttention, zeroNegativePrompt: zeroNegativePrompt)
          if oldC.count >= 2 {
            let vector = fixedEncoder.vector(
              textEmbedding: oldC[oldC.count - 1], originalSize: originalSize,
              cropTopLeft: cropTopLeft,
              targetSize: targetSize, aestheticScore: aestheticScore,
              negativeOriginalSize: negativeOriginalSize,
              negativeAestheticScore: negativeAestheticScore, fpsId: fpsId,
              motionBucketId: motionBucketId, condAug: condAug)
            c =
              vector
              + fixedEncoder.encode(
                textEncoding: oldC, batchSize: batchSize, startHeight: startHeight,
                startWidth: startWidth, tokenLengthUncond: tokenLengthUncond,
                tokenLengthCond: tokenLengthCond, lora: lora
              ).0
          }
          unet = UNet()
          currentModelVersion = refiner.version
          let firstTimestep =
            discretization.timesteps - discretization.timesteps / Float(sampling.steps) + 1
          let t = unet.timeEmbed(
            graph: graph, batchSize: cfgChannels * batchSize, timestep: firstTimestep,
            version: currentModelVersion)
          let (injectedControls, injectedT2IAdapters, injectedIPAdapters) =
            ControlModel<FloatType>
            .emptyInjectedControlsAndAdapters(
              injecteds: injectedControls, step: 0, version: refiner.version, inputs: xIn)
          let newC: [DynamicGraph.Tensor<FloatType>]
          if version == .svdI2v {
            newC = Array(c[0..<(1 + (c.count - 1) / 2)])
          } else {
            newC = c
          }
          let _ = unet.compileModel(
            filePath: refiner.filePath, externalOnDemand: refiner.externalOnDemand,
            version: refiner.version, upcastAttention: upcastAttention,
            usesFlashAttention: usesFlashAttention, injectControls: injectControls,
            injectT2IAdapters: injectT2IAdapters, injectIPAdapterLengths: injectIPAdapterLengths,
            lora: lora, is8BitModel: refiner.is8BitModel,
            canRunLoRASeparately: canRunLoRASeparately,
            inputs: xIn, t, newC,
            tokenLengthUncond: tokenLengthUncond, tokenLengthCond: tokenLengthCond,
            extraProjection: extraProjection, injectedControls: injectedControls,
            injectedT2IAdapters: injectedT2IAdapters, injectedIPAdapters: injectedIPAdapters,
            tiledDiffusion: tiledDiffusion)
          refinerKickIn = -1
          unets.append(unet)
        }
        let cNoise: Float
        switch conditioning {
        case .noise:
          cNoise = discretization.noise(for: alphaCumprod)
        case .timestep:
          cNoise = timestep
        }
        let t = unet.timeEmbed(
          graph: graph, batchSize: cfgChannels * batchSize, timestep: cNoise,
          version: currentModelVersion)
        let et: DynamicGraph.Tensor<FloatType>
        if version == .svdI2v, let textGuidanceVector = textGuidanceVector,
          let condAugFrames = condAugFrames
        {
          xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] = input
          xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, channels..<(channels * 2)] =
            condAugFrames
          let (injectedControls, injectedT2IAdapters, injectedIPAdapters) = ControlModel<FloatType>
            .injectedControlsAndAdapters(
              injecteds: injectedControls, step: i, version: unet.version,
              usesFlashAttention: usesFlashAttention, inputs: xIn, t, injectedControlsC,
              tokenLengthUncond: tokenLengthUncond, tokenLengthCond: tokenLengthCond,
              mainUNetAndWeightMapper: unet.modelAndWeightMapper, controlNets: &controlNets)
          let cCond = Array(c[0..<(1 + (c.count - 1) / 2)])
          var etCond = unet(
            timestep: cNoise, inputs: xIn, t, cCond, extraProjection: extraProjection,
            injectedControls: injectedControls, injectedT2IAdapters: injectedT2IAdapters,
            injectedIPAdapters: injectedIPAdapters, tiledDiffusion: tiledDiffusion)
          let alpha =
            0.001 * sharpness * (discretization.timesteps - timestep)
            / discretization.timesteps
          if isCfgEnabled {
            xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, channels..<(channels * 2)].full(0)
            let cUncond = Array([c[0]] + c[(1 + (c.count - 1) / 2)...])
            let etUncond = unet(
              timestep: cNoise, inputs: xIn, t, cUncond, extraProjection: extraProjection,
              injectedControls: injectedControls, injectedT2IAdapters: injectedT2IAdapters,
              injectedIPAdapters: injectedIPAdapters, tiledDiffusion: tiledDiffusion)
            if let blur = blur {
              let etCondDegraded = blur(inputs: etCond)[0].as(of: FloatType.self)
              etCond = Functional.add(
                left: etCondDegraded, right: etCond, leftScalar: alpha, rightScalar: 1 - alpha)
            }
            et = etUncond + textGuidanceVector .* (etCond - etUncond)
          } else {
            if let blur = blur {
              let etCondDegraded = blur(inputs: etCond)[0].as(of: FloatType.self)
              etCond = Functional.add(
                left: etCondDegraded, right: etCond, leftScalar: alpha, rightScalar: 1 - alpha)
            }
            et = etCond
          }
        } else {
          xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] = input
          if isCfgEnabled {
            xIn[batchSize..<(batchSize * 2), 0..<startHeight, 0..<startWidth, 0..<channels] = input
            if modifier == .editing {
              xIn[
                (batchSize * 2)..<(batchSize * 3), 0..<startHeight, 0..<startWidth, 0..<channels] =
                input
            }
          }
          let (injectedControls, injectedT2IAdapters, injectedIPAdapters) = ControlModel<FloatType>
            .injectedControlsAndAdapters(
              injecteds: injecteds, step: i, version: unet.version,
              usesFlashAttention: usesFlashAttention, inputs: xIn, t, injectedControlsC,
              tokenLengthUncond: tokenLengthUncond, tokenLengthCond: tokenLengthCond,
              mainUNetAndWeightMapper: unet.modelAndWeightMapper, controlNets: &controlNets)
          var etOut = unet(
            timestep: cNoise, inputs: xIn, t, c, extraProjection: extraProjection,
            injectedControls: injectedControls, injectedT2IAdapters: injectedT2IAdapters,
            injectedIPAdapters: injectedIPAdapters, tiledDiffusion: tiledDiffusion)
          let alpha =
            0.001 * sharpness * (discretization.timesteps - timestep)
            / discretization.timesteps
          if isCfgEnabled {
            var etUncond = graph.variable(
              .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
            var etCond = graph.variable(
              .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
            etUncond[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] =
              etOut[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels]
            etCond[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] =
              etOut[batchSize..<(batchSize * 2), 0..<startHeight, 0..<startWidth, 0..<channels]
            if let blur = blur {
              let etCondDegraded = blur(inputs: etCond)[0].as(of: FloatType.self)
              etCond = Functional.add(
                left: etCondDegraded, right: etCond, leftScalar: alpha, rightScalar: 1 - alpha)
            }
            if modifier == .editing {
              var etAllUncond = graph.variable(
                .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
              etAllUncond[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] =
                etOut[
                  (batchSize * 2)..<(batchSize * 3), 0..<startHeight, 0..<startWidth, 0..<channels]
              et =
                etAllUncond + textGuidanceScale * (etCond - etUncond) + imageGuidanceScale
                * (etUncond - etAllUncond)
            } else {
              et = etUncond + textGuidanceScale * (etCond - etUncond)
            }
          } else {
            if let blur = blur {
              let etOutDegraded = blur(inputs: etOut)[0].as(of: FloatType.self)
              etOut = Functional.add(
                left: etOutDegraded, right: etOut, leftScalar: alpha, rightScalar: 1 - alpha)
            }
            et = etOut
          }
        }
        if i < sampling.steps - 1 {
          var denoised: DynamicGraph.Tensor<FloatType>
          switch discretization.objective {
          case .v:
            denoised = Functional.add(
              left: x, right: et, leftScalar: Float(1.0 / (sigma * sigma + 1)),
              rightScalar: Float(-sigma * sqrtAlphaCumprod))
          case .epsilon:
            denoised = Functional.add(left: x, right: et, leftScalar: 1, rightScalar: Float(-sigma))
            if version == .kandinsky21 {
              denoised = clipDenoised(denoised)
            }
          case .edm(let sigmaData):
            let sigmaData2 = sigmaData * sigmaData
            denoised = Functional.add(
              left: x, right: et, leftScalar: Float(sigmaData2 / (sigma * sigma + sigmaData2)),
              rightScalar: Float(sigma * sigmaData / (sigma * sigma + sigmaData2).squareRoot()))
          }
          let sigmaS = (sigma * sigmas[i + 1]).squareRoot()  // exp(log(sigma) - h / 2) == exp(log(sigma) / 2 + log(sigmas[i + 1]) / 2) == sqrt(exp(log(sigma) + log(sigma[i + 1]))
          let sigmaUp1 = min(
            sigmaS,
            1.0
              * ((sigmaS * sigmaS) * (sigma * sigma - sigmaS * sigmaS)
              / (sigma * sigma)).squareRoot())
          let sigmaDown1 = (sigmaS * sigmaS - sigmaUp1 * sigmaUp1).squareRoot()
          let w1 = sigmaDown1 / sigma
          var x2 = Functional.add(
            left: x, right: denoised, leftScalar: Float(w1), rightScalar: Float(1 - w1))
          // Now do brownian sampling to sigma -> sigmaS (right), needs to compute sigmaS -> 0 (left).
          // Formulation borrowed from: https://github.com/google-research/torchsde/blob/master/torchsde/_brownian/brownian_interval.py#L181
          // Because we do brownian sampling, meaning there is a dependency between this observation and the next one.
          // We need to keep leftW and leftW2 in memory (leftW2 in next round) as we split the observations further.
          let leftDiffOverH = sigmaS / sigma
          let rightDiff = sigma - sigmaS
          noise.randn(std: 1, mean: 0)
          let leftW = Functional.add(
            left: brownianNoise, right: noise, leftScalar: Float(leftDiffOverH),
            rightScalar: Float((rightDiff * leftDiffOverH).squareRoot()))
          let rightW = brownianNoise - leftW
          x2 = Functional.add(
            left: x2, right: rightW, leftScalar: 1,
            rightScalar: Float(sigmaUp1 / (sigma - sigmaS).squareRoot()))
          // Now run the model again.
          let alphaSCumprod = 1.0 / (sigmaS * sigmaS + 1)
          let sqrtAlphaSCumprod = alphaSCumprod.squareRoot()
          let input: DynamicGraph.Tensor<FloatType>
          switch discretization.objective {
          case .v, .epsilon:
            input = Float(sqrtAlphaSCumprod) * x2
          case .edm(let sigmaData):
            input = Float(1.0 / (sigma * sigma + sigmaData * sigmaData).squareRoot()) * x2
          }
          let et: DynamicGraph.Tensor<FloatType>
          let timestep: Float
          switch conditioning {
          case .noise:
            timestep = discretization.noise(for: alphaSCumprod)
          case .timestep:
            timestep = discretization.timestep(for: alphaSCumprod)
          }
          let t = unet.timeEmbed(
            graph: graph, batchSize: cfgChannels * batchSize, timestep: timestep,
            version: currentModelVersion)
          if version == .svdI2v, let textGuidanceVector = textGuidanceVector,
            let condAugFrames = condAugFrames
          {
            xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] = input
            xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, channels..<(channels * 2)] =
              condAugFrames
            let (injectedControls, injectedT2IAdapters, injectedIPAdapters) = ControlModel<
              FloatType
            >
            .injectedControlsAndAdapters(
              injecteds: injectedControls, step: i, version: unet.version,
              usesFlashAttention: usesFlashAttention, inputs: xIn, t, injectedControlsC,
              tokenLengthUncond: tokenLengthUncond, tokenLengthCond: tokenLengthCond,
              mainUNetAndWeightMapper: unet.modelAndWeightMapper, controlNets: &controlNets)
            let cCond = Array(c[0..<(1 + (c.count - 1) / 2)])
            var etCond = unet(
              timestep: timestep, inputs: xIn, t, cCond, extraProjection: extraProjection,
              injectedControls: injectedControls, injectedT2IAdapters: injectedT2IAdapters,
              injectedIPAdapters: injectedIPAdapters, tiledDiffusion: tiledDiffusion)
            let alpha =
              0.001 * sharpness * (discretization.timesteps - timestep)
              / discretization.timesteps
            if isCfgEnabled {
              xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, channels..<(channels * 2)].full(0)
              let cUncond = Array([c[0]] + c[(1 + (c.count - 1) / 2)...])
              let etUncond = unet(
                timestep: timestep, inputs: xIn, t, cUncond, extraProjection: extraProjection,
                injectedControls: injectedControls, injectedT2IAdapters: injectedT2IAdapters,
                injectedIPAdapters: injectedIPAdapters, tiledDiffusion: tiledDiffusion)
              if let blur = blur {
                let etCondDegraded = blur(inputs: etCond)[0].as(of: FloatType.self)
                etCond = Functional.add(
                  left: etCondDegraded, right: etCond, leftScalar: alpha, rightScalar: 1 - alpha)
              }
              et = etUncond + textGuidanceVector .* (etCond - etUncond)
            } else {
              if let blur = blur {
                let etCondDegraded = blur(inputs: etCond)[0].as(of: FloatType.self)
                etCond = Functional.add(
                  left: etCondDegraded, right: etCond, leftScalar: alpha, rightScalar: 1 - alpha)
              }
              et = etCond
            }
          } else {
            xIn[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] = input
            if isCfgEnabled {
              xIn[batchSize..<(batchSize * 2), 0..<startHeight, 0..<startWidth, 0..<channels] =
                input
              if modifier == .editing {
                xIn[
                  (batchSize * 2)..<(batchSize * 3), 0..<startHeight, 0..<startWidth, 0..<channels] =
                  input
              }
            }
            let (injectedControls, injectedT2IAdapters, injectedIPAdapters) = ControlModel<
              FloatType
            >
            .injectedControlsAndAdapters(
              injecteds: injecteds, step: i, version: unet.version,
              usesFlashAttention: usesFlashAttention, inputs: xIn, t, injectedControlsC,
              tokenLengthUncond: tokenLengthUncond, tokenLengthCond: tokenLengthCond,
              mainUNetAndWeightMapper: unet.modelAndWeightMapper, controlNets: &controlNets)
            var etOut = unet(
              timestep: timestep, inputs: xIn, t, c, extraProjection: extraProjection,
              injectedControls: injectedControls, injectedT2IAdapters: injectedT2IAdapters,
              injectedIPAdapters: injectedIPAdapters, tiledDiffusion: tiledDiffusion)
            let alpha =
              0.001 * sharpness * (discretization.timesteps - timestep)
              / discretization.timesteps
            if isCfgEnabled {
              var etUncond = graph.variable(
                .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
              var etCond = graph.variable(
                .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
              etUncond[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] =
                etOut[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels]
              etCond[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] =
                etOut[batchSize..<(batchSize * 2), 0..<startHeight, 0..<startWidth, 0..<channels]
              if let blur = blur {
                let etCondDegraded = blur(inputs: etCond)[0].as(of: FloatType.self)
                etCond = Functional.add(
                  left: etCondDegraded, right: etCond, leftScalar: alpha, rightScalar: 1 - alpha)
              }
              if modifier == .editing {
                var etAllUncond = graph.variable(
                  .GPU(0), .NHWC(batchSize, startHeight, startWidth, channels), of: FloatType.self)
                etAllUncond[0..<batchSize, 0..<startHeight, 0..<startWidth, 0..<channels] =
                  etOut[
                    (batchSize * 2)..<(batchSize * 3), 0..<startHeight, 0..<startWidth, 0..<channels
                  ]
                et =
                  etAllUncond + textGuidanceScale * (etCond - etUncond) + imageGuidanceScale
                  * (etUncond - etAllUncond)
              } else {
                et = etUncond + textGuidanceScale * (etCond - etUncond)
              }
            } else {
              if let blur = blur {
                let etOutDegraded = blur(inputs: etOut)[0].as(of: FloatType.self)
                etOut = Functional.add(
                  left: etOutDegraded, right: etOut, leftScalar: alpha, rightScalar: 1 - alpha)
              }
              et = etOut
            }
          }
          var denoised2: DynamicGraph.Tensor<FloatType>
          switch discretization.objective {
          case .v:
            denoised2 = Functional.add(
              left: x2, right: et, leftScalar: Float(1.0 / (sigmaS * sigmaS + 1)),
              rightScalar: Float(-sigmaS * sqrtAlphaSCumprod))
          case .epsilon:
            denoised2 = Functional.add(
              left: x2, right: et, leftScalar: 1, rightScalar: Float(-sigmaS))
            if version == .kandinsky21 {
              denoised2 = clipDenoised(denoised2)
            }
          case .edm(let sigmaData):
            let sigmaData2 = sigmaData * sigmaData
            denoised2 = Functional.add(
              left: x2, right: et, leftScalar: Float(sigmaData2 / (sigmaS * sigmaS + sigmaData2)),
              rightScalar: Float(sigmaS * sigmaData / (sigmaS * sigmaS + sigmaData2).squareRoot()))
          }
          let sigmaUp2 = min(
            sigmas[i + 1],
            1.0
              * ((sigmas[i + 1] * sigmas[i + 1]) * (sigma * sigma - sigmas[i + 1] * sigmas[i + 1])
              / (sigma * sigma)).squareRoot())
          let sigmaDown2 = (sigmas[i + 1] * sigmas[i + 1] - sigmaUp2 * sigmaUp2).squareRoot()
          let denoisedD = denoised2
          let w2 = sigmaDown2 / sigma
          x = Functional.add(
            left: x, right: denoisedD, leftScalar: Float(w2), rightScalar: Float(1 - w2))
          let leftDiffOverH2 = sigmas[i + 1] / sigmaS
          let rightDiff2 = sigmaS - sigmas[i + 1]
          noise.randn(std: 1, mean: 0)
          let leftW2 = Functional.add(
            left: leftW, right: noise, leftScalar: Float(leftDiffOverH2),
            rightScalar: Float((rightDiff2 * leftDiffOverH2).squareRoot()))
          let rightW2 = leftW - leftW2 + rightW
          x = Functional.add(
            left: x, right: rightW2, leftScalar: 1,
            rightScalar: Float(sigmaUp2 / (sigma - sigmas[i + 1]).squareRoot()))
          brownianNoise = leftW2  // On next round, this is the only thing we care.
          oldDenoised = denoised
        } else {
          let dt = sigmas[i + 1] - sigma
          switch discretization.objective {
          case .v:
            // denoised = Float(1.0 / (sigma * sigma + 1)) * x - (sigma * sqrtAlphaCumprod) * et
            // d = (x - denoised) / sigma // (x - Float(1.0 / (sigma * sigma + 1)) * x + (sigma * sqrtAlphaCumprod) * et) / sigma = (sigma / (sigma * sigma + 1)) * x + sqrtAlphaCumprod * et
            let d = Functional.add(
              left: x, right: et, leftScalar: Float(sigma / (sigma * sigma + 1)),
              rightScalar: Float(sqrtAlphaCumprod))
            x = Functional.add(left: x, right: d, leftScalar: 1, rightScalar: Float(dt))
          case .epsilon:
            // denoised = x - sigma * et
            // d = (x - denoised) / sigma // (x - x + sigma * et) / sigma = et
            x = Functional.add(left: x, right: et, leftScalar: 1, rightScalar: Float(dt))
          case .edm(let sigmaData):
            let sigmaData2 = sigmaData * sigmaData
            // denoised = sigmaData2 / (sigma * sigma + sigmaData2) * x + (sigma * sigmaData / (sigma * sigma + sigmaData2).squareRoot()) * et
            // d = (x - denoised) / sigma // (x - sigmaData2 / (sigma * sigma + sigmaData2) * x - (sigma * sigmaData / (sigma * sigma + sigmaData2).squareRoot()) * et) / sigma
            let d = Functional.add(
              left: x, right: et, leftScalar: Float(sigma / (sigma * sigma + sigmaData2)),
              rightScalar: Float(-sigmaData / (sigma * sigma + sigmaData2).squareRoot()))
            x = Functional.add(left: x, right: d, leftScalar: 1, rightScalar: Float(dt))
          }
        }
        if i < endStep.integral - 1, let sample = sample, let mask = mask, let negMask = negMask {
          // If you check how we compute sigma, this is basically how we get back to alphaCumprod.
          // alphaPrev = 1 / (sigmas[i + 1] * sigmas[i + 1] + 1)
          // Then, we should compute qSample as alphaPrev.squareRoot() * sample + (1 - alphaPrev).squareRoot() * noise
          // However, because we will multiple back 1 / alphaPrev.squareRoot() again, this effectively become the following.
          noise.randn(std: 1, mean: 0)
          let qSample = sample + Float(sigmas[i + 1]) * noise
          x = qSample .* negMask + x .* mask
        }
        if i == endStep.integral - 1 {
          if isNaN(x.rawValue.toCPU()) {
            return .failure(SamplerError.isNaN)
          }
        }
      }
      return .success(SamplerOutput(x: x, unets: unets))
    }
    streamContext.joined()
    return result
  }

  public func timestep(for strength: Float, sampling: Sampling) -> (
    timestep: Float, startStep: Float, roundedDownStartStep: Int, roundedUpStartStep: Int
  ) {
    let tEnc = strength * discretization.timesteps
    let initTimestep = tEnc
    let alphasCumprod = discretization.alphasCumprod(steps: sampling.steps, shift: sampling.shift)
    var previousTimestep = discretization.timesteps
    for (i, alphaCumprod) in alphasCumprod.enumerated() {
      let timestep = discretization.timestep(for: alphaCumprod)
      if initTimestep >= timestep {
        guard i > 0 else {
          return (
            timestep: timestep, startStep: 0, roundedDownStartStep: 0, roundedUpStartStep: 0
          )
        }
        guard initTimestep > timestep + 1e-3 else {
          return (
            timestep: initTimestep, startStep: Float(i), roundedDownStartStep: i,
            roundedUpStartStep: i
          )
        }
        return (
          timestep: Float(initTimestep),
          startStep: Float(i - 1) + Float(initTimestep - previousTimestep)
            / Float(timestep - previousTimestep), roundedDownStartStep: i - 1, roundedUpStartStep: i
        )
      }
      previousTimestep = timestep
    }
    return (
      timestep: discretization.timestep(for: alphasCumprod[0]),
      startStep: Float(alphasCumprod.count - 1),
      roundedDownStartStep: alphasCumprod.count - 1, roundedUpStartStep: alphasCumprod.count - 1
    )
  }

  public func sampleScaleFactor(at step: Float, sampling: Sampling) -> Float {
    return 1
  }

  public func noiseScaleFactor(at step: Float, sampling: Sampling) -> Float {
    let alphasCumprod = discretization.alphasCumprod(steps: sampling.steps, shift: sampling.shift)
    let lowTimestep = discretization.timestep(
      for: alphasCumprod[max(0, min(Int(step.rounded(.down)), alphasCumprod.count - 1))])
    let highTimestep = discretization.timestep(
      for: alphasCumprod[max(0, min(Int(step.rounded(.up)), alphasCumprod.count - 1))])
    let timestep = lowTimestep + (highTimestep - lowTimestep) * (step - Float(step.rounded(.down)))
    let alphaCumprod = discretization.alphaCumprod(timestep: timestep, shift: sampling.shift)
    let sigma = ((1 - alphaCumprod) / alphaCumprod).squareRoot()
    return Float(sigma)
  }
}
