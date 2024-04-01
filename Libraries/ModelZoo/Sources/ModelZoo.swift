import DataModels
import Diffusion
import Foundation

public struct ModelZoo: DownloadZoo {
  public static func humanReadableNameForVersion(_ version: ModelVersion) -> String {
    switch version {
    case .v1:
      return "Stable Diffusion v1"
    case .v2:
      return "Stable Diffusion v2"
    case .kandinsky21:
      return "Kandinsky v2.1"
    case .sdxlBase:
      return "Stable Diffusion XL Base"
    case .sdxlRefiner:
      return "Stable Diffusion XL Refiner"
    case .ssd1b:
      return "Segmind Stable Diffusion XL 1B"
    case .svdI2v:
      return "Stable Video Diffusion"
    case .wurstchenStageC, .wurstchenStageB:
      return "Stable Cascade (Wurstchen v3.0)"
    }
  }

  public enum NoiseDiscretization: Codable {
    case edm(Denoiser.Parameterization.EDM)
    case ddpm(Denoiser.Parameterization.DDPM)
  }

  public struct Specification: Codable {
    public var name: String
    public var file: String
    public var prefix: String
    public var version: ModelVersion
    public var upcastAttention: Bool
    public var defaultScale: UInt16
    public var textEncoder: String?
    public var autoencoder: String?
    public var modifier: SamplerModifier?
    public var deprecated: Bool?
    public var imageEncoder: String?
    public var clipEncoder: String?
    public var diffusionMapping: String?
    public var highPrecisionAutoencoder: Bool?
    public var defaultRefiner: String?
    public var isConsistencyModel: Bool?
    public var conditioning: Denoiser.Conditioning?
    public var objective: Denoiser.Objective?
    public var noiseDiscretization: NoiseDiscretization?
    public var latentsMean: [Float]?
    public var latentsStd: [Float]?
    public var latentsScalingFactor: Float?
    public var stageModels: [String]?
    public init(
      name: String, file: String, prefix: String, version: ModelVersion,
      upcastAttention: Bool = false, defaultScale: UInt16 = 8, textEncoder: String? = nil,
      autoencoder: String? = nil, modifier: SamplerModifier? = nil, deprecated: Bool? = nil,
      imageEncoder: String? = nil, clipEncoder: String? = nil, diffusionMapping: String? = nil,
      highPrecisionAutoencoder: Bool? = nil, defaultRefiner: String? = nil,
      isConsistencyModel: Bool? = nil, conditioning: Denoiser.Conditioning? = nil,
      objective: Denoiser.Objective? = nil,
      noiseDiscretization: NoiseDiscretization? = nil, latentsMean: [Float]? = nil,
      latentsStd: [Float]? = nil, latentsScalingFactor: Float? = nil, stageModels: [String]? = nil
    ) {
      self.name = name
      self.file = file
      self.prefix = prefix
      self.version = version
      self.upcastAttention = upcastAttention
      self.defaultScale = defaultScale
      self.textEncoder = textEncoder
      self.autoencoder = autoencoder
      self.modifier = modifier
      self.deprecated = deprecated
      self.imageEncoder = imageEncoder
      self.clipEncoder = clipEncoder
      self.diffusionMapping = diffusionMapping
      self.highPrecisionAutoencoder = highPrecisionAutoencoder
      self.defaultRefiner = defaultRefiner
      self.isConsistencyModel = isConsistencyModel
      self.conditioning = conditioning
      self.objective = objective
      self.noiseDiscretization = noiseDiscretization
      self.latentsMean = latentsMean
      self.latentsStd = latentsStd
      self.latentsScalingFactor = latentsScalingFactor
      self.stageModels = stageModels
    }
    fileprivate var predictV: Bool? = nil
  }

  private static var fileSHA256: [String: String] = [
    "clip_vit_l14_f16.ckpt": "809bfd12c8d4b3d79c14e850b99130a70854f6fd8dedcacdf429417c02fa3007",
    "open_clip_vit_h14_f16.ckpt":
      "cdaa1b93cb099d4aff8831ba248780cebbb54bcd2810dd242513c4a8c70ba577",
    "sd_v1.4_f16.ckpt": "0e0d62f677aba5aae59d977e8a48b2ad87b6d47d519e92f11b7f988c882e5910",
    "vae_ft_mse_840000_f16.ckpt":
      "3b35514e11dd2b913e0579089babc1dfbd36589a77044c2e9b8065187e2f4154",
    "sd_v1.5_f16.ckpt": "bf867591702e4c5d86cb126a3601d7e494180cce956b8dfaf90e5093d2e7c0f6",
    "sd_v1.5_inpainting_f16.ckpt":
      "4e935e18e3d1be94378d96e0d9cb347fcd75de4821ff1d142c60640313b60ab2",
    "sd_v2.0_f16.ckpt": "73cbc76b4ecc4a8c33bf4c452d396c86c42c2f50361745bd649a98e9ea269a3b",
    "sd_v2.1_f16.ckpt": "2d9a7302668bacf3b801327bc23b116f24a441e6229cc4a4b7c39aaa4bf3c9f7",
    "sd_v2.0_inpainting_f16.ckpt":
      "d42b44d3614a0e22195aa5e4f94f417c7c755a99c463e8730ad8f7071c2c5a92",
    "sd_v2.0_depth_f16.ckpt": "64f907b7bf40954477439dda42dcf2cf864526b4c498279cd4274bce12fe896d",
    "sd_v2.0_768_v_f16.ckpt": "992be2b0b34e0a591b043a07b4fc32bf04210424872230a15169e68ef45cde43",
    "sd_v2.1_768_v_f16.ckpt": "04378818798ab37ce9adc189ea28c342d9edde8511194bf5a205f56bb38cf05c",
    "minisd_v1.4_f16.ckpt": "7aed73bf40b49083be32791de39e192f6ac4aa20fbc98e13d4cdca7b5bdd07bf",
    "wd_v1.3_f16.ckpt": "b6862eec82ec14cdb754c5df5c131631bae5e4664b5622a615629c42e7a43c05",
    "classicanim_v1_f16.ckpt": "168799472175b77492814ae3cf5e9f793a3d3d009592a9e5b03781626ea25590",
    "modi_v1_f16.ckpt": "ca76d84c1783ef367201e4eac2e1dddbce0c40afc6de62a229b80cb04ae7c4f0",
    "arcane_v3_f16.ckpt": "4c55d2239e1f0ff40cc6e1ae518737735f6d1b7613f8f7aca9239205f0be729a",
    "cyberpunk_anime_f16.ckpt": "df55b6c66704b51921e31711adaab9e37bd78fc10733fcd89e6f86426230ef41",
    "redshift_v1_f16.ckpt": "a7fc94bac178414d7caf844787afcaf8c6c273ebf9011fed75703de7839fc257",
    "redshift_768_v_f16.ckpt": "aa6520ae1fc447082230b2eb646c40e6f776f257c453134d0f064a89ac1de751",
    "redshift_768_v_open_clip_vit_h14_f16.ckpt":
      "9c7f1a65fe890f288c2d2ff7cef11b502bf10965a7eaa7d0d43362cab9f90eca",
    "dnd_30000_f16.ckpt": "3de9309cf4541168fb39d96eaba760146b42e7e9870a3096eb4cd097384ea1d9",
    "trnlgcy_f16.ckpt": "3ed86762dda66f5dc728ee1f67085d2ba9f3e3ea1b5b3464b8f3a791954cfa3c",
    "classicanim_v1_clip_vit_l14_f16.ckpt":
      "77cfbb6054a2a5581873c3b1be8c6457bed526d1f15d6cffb6e381401692a488",
    "modi_v1_clip_vit_l14_f16.ckpt":
      "e7907cbb2f7656bb2f6fb4ead4fcb030721e4218ca2a105976b88bce852f2860",
    "arcane_v3_clip_vit_l14_f16.ckpt":
      "954f1e1fb690dcb1820adaf83099b39057e2b1bcbbdc12ecfe37ac17bcad6fa7",
    "cyberpunk_anime_clip_vit_l14_f16.ckpt":
      "d62bb1de4b579d73111b3355cad72b1d8f3bf22519c4bfd1a224bdd952cd0279",
    "redshift_v1_clip_vit_l14_f16.ckpt":
      "95532a3275a81d909d657c98b73ef576809254e29052aaa809d9336c13f182a1",
    "dnd_30000_clip_vit_l14_f16.ckpt":
      "96c75d1c11030a51aa8dac5410cc6fa98b071b52f0f79a07097df022b20754dc",
    "trnlgcy_clip_vit_l14_f16.ckpt":
      "a99adbecbed4e370abcffc2574fac8e664a2530531fdc89b71d2f15711f40545",
    "mdjrny_v4_f16.ckpt": "a0d976948c18943f1281268cc3edbe1d1fa2a4098b5a290d9947a1a299976699",
    "mdjrny_v4_clip_vit_l14_f16.ckpt":
      "ad4e3d64c0a5e81d529c984dcfbdc6858d73e14ebe8788975e6b8c4fbfc17629",
    "nitro_v1_f16.ckpt": "2549d7220cce7f53311fe145878e1af8bcd52efaf15bcb81a2681c0abcddd6c3",
    "nitro_v1_clip_vit_l14_f16.ckpt":
      "2b5424697630a50ed2d1b8c2449e3fb5f613a6569d72d16dc59d1e28a8a0c07d",
    "anything_v3_f16.ckpt": "f4354727512d6b6a2d5e4cf783fdc8475e7981c50b9f387bc93317c22299e505",
    "anything_v3_clip_vit_l14_f16.ckpt":
      "5f1311561bdac6d43e4b3bacbee8c257bf788e6c86b3c69c68247a9abab1050d",
    "anything_v3_vae_f16.ckpt": "3b7d16260a7d211416739285f97d53354b332cfceadb2b7191817f4e1cfb5d57",
    "hassanblend_v1.4_f16.ckpt": "e3566b98cfa81660cd4833c01cd9a05a853e367726d840a5eb16098b53c042ae",
    "lvngvncnt_v2_f16.ckpt": "dbacd01fb82501895afde1bbcf3f16eefeea8043fa3463de640c09a9315460be",
    "lvngvncnt_v2_clip_vit_l14_f16.ckpt":
      "cbdaae485f60c7cb395e5725dd16e769816274b74498d0c45048962a49cc4a06",
    "spiderverse_v1_f16.ckpt": "8c8c80add2d663732e314c3a2fb49c1f2bd98f48190b79227d660ce687516b2d",
    "spiderverse_v1_clip_vit_l14_f16.ckpt":
      "bab7fcf0e615154ff91c88a8fbf9b18a548e8ba0a338fb030a3fedf17ce0602d",
    "eldenring_v3_f16.ckpt": "c6b79886e426d654c9e84cf53a7dd572fbb9e7083c47384a76d02702c54c50c3",
    "eldenring_v3_clip_vit_l14_f16.ckpt":
      "dcd2234e90f8df2c4eb706f665fa860ad54df2ae109cfcd8b235c1c420bd2d4d",
    "papercut_v1_f16.ckpt": "7b1d14757e1c58b1bef55220d0fd10ab4ad8e2670bb4e065e4b6c4e0b6a6395e",
    "papercut_v1_clip_vit_l14_f16.ckpt":
      "bc0c471e51bbe0649922dad862019b96e68d4abf724998bbfa9495e70bd2023d",
    "voxelart_v1_f16.ckpt": "e771d7acd484162377c62a6033b632ea290d4477bf3cb017a750f15ab5350ca7",
    "voxelart_v1_clip_vit_l14_f16.ckpt":
      "ebd3ce92b9ec831a6f217c42be0b8da887484867583156d0e2ceb3e48bae3be8",
    "balloonart_v1_f16.ckpt": "f73bcbd3a6db0dca10afb081a2066a7aea5b117962bd26efc37320dfc3b9b759",
    "balloonart_v1_clip_vit_l14_f16.ckpt":
      "6be250d1c38325f7ee80f3fcd99e1a490f28deb29a8f78188813e8157f1949b3",
    "f222_f16.ckpt": "ae19854df68e232c3bbda8b9322e9f56ccd2d96517a31a82694c40382003f8ae",
    "supermarionation_v2_f16.ckpt":
      "70e13769ee9c8b8c4d4b8240f23b8d8fcef154325fd9162174b75f67c5629440",
    "supermarionation_v2_clip_vit_l14_f16.ckpt":
      "e2da78a79ee90fe352e465326e2dc0c055888c27a84d465cfd9ea2987a83a131",
    "inkpunk_v2_f16.ckpt": "8957387975caf8c56caa6c4c2b9d8fff07bda7a8a2aadec840be3fd623d1d2fe",
    "inkpunk_v2_clip_vit_l14_f16.ckpt":
      "569d9796b5f3b33ed1ce65b27fa3fb4dfdb8ef2440555fa33f30fa8d118cc293",
    "samdoesart_v3_f16.ckpt": "5a55df0470437ac0f3f0c05d77098c6eb8577c61ce0e1b2dc898240fb49fd10e",
    "samdoesart_v3_clip_vit_l14_f16.ckpt":
      "6d84e79c05f9c89172f4b82821a7c8223d3bd6bacfd80934dd85dce71a8f2519",
    "ghibli_v1_f16.ckpt": "dfcf9358528e8892f82b4ba3d0c9245be928e2e920e746383bdaf1b9a3a93151",
    "ghibli_v1_clip_vit_l14_f16.ckpt":
      "bf7c353e5b2b34bff2216742e114ee707f0ad023cc0bfd5ebde779b3b3162a02",
    "analog_v1_f16.ckpt": "ffed9bb928a20f90f9881ac0d51e918c1580562f099fdd45c061c292dec63ab5",
    "analog_v1_clip_vit_l14_f16.ckpt":
      "f144ac4ad344c82c3b1dc69e46aba8d9c6bc20d24de9e48105a3db3e4437108d",
    "dnd_classes_and_species_f16.ckpt":
      "a6059246c1c06edc73646c77a1aa819ca641e0d8ceba0e25365938ab71311174",
    "dnd_classes_and_species_clip_vit_l14_f16.ckpt":
      "09fdf2d991591947e2743e8431e9d6eaf99fe2f524de9c752ebb7a4289225b02",
    "aloeveras_simpmaker_3k1_f16.ckpt":
      "562db3b5ca4961eed207e308073d99293d27f23f90e09dba58f2eb828a2f8e0c",
    "hna_3dkx_1.0b_f16.ckpt":
      "5e9246ff45380d6e0bd22506d559e2d6616b7aa0e42052a92c0270b89de2defa",
    "hna_3dkx_1.0b_clip_vit_l14_f16.ckpt":
      "7317f067a71f1e2a2a886c60574bb391bf31a559b4daa4901c45d1d5d2acc7d6",
    "seek_art_mega_v1_f16.ckpt":
      "0f10cfa16950fc5bb0a31b9974275c256c1a11f26f92ac26be6f7ea91e7019ac",
    "seek_art_mega_v1_clip_vit_l14_f16.ckpt":
      "9dd3af747d71b10d318b876a9285f8cc7c350806585146a3eaa660bcaf54bc7e",
    "instruct_pix2pix_22000_f16.ckpt":
      "ffe6548ff4e803c64f8ca2b84024058e88494329acff29583fbb9f45305dd410",
    "hassanblend_v1.5.1.2_f16.ckpt":
      "e5eb4e11fa1f882dc084a0e061abf6b7f5e7dd11c416ff14842c049b9727c5d1",
    "hassanblend_v1.5.1.2_clip_vit_l14_f16.ckpt":
      "0d572f5e379c48c88aa7ca1d6aff095d94cacaf8b90f6444f4af46a7d3d18f33",
    "hna_3dkx_1.1_f16.ckpt":
      "9e333094d9b73db3e0438f7520c0cd5deb2f0f6b3aa890ce464050cc7dd8d693",
    "hna_3dkx_1.1_clip_vit_l14_f16.ckpt":
      "5ce38e05ada7ec4488c600bc026db1386fb4cdca2882fe51561c49a1bc70da4d",
    "kandinsky_f16.ckpt":
      "563cbf6dd08c81063c45310a7a420b75004d6f226eb7e045f167d03d485fc36a",
    "kandinsky_diffusion_mapping_f16.ckpt":
      "6467fd6ac08bc4d851ed09286f2273f134fe5d6763086ef06551f1285de059f0",
    "kandinsky_movq_f16.ckpt":
      "f7ac86bd2f1b3bb7487a064df64e39fbf92905e40ebfbe943c3859ff05204071",
    "xlm_roberta_f16.ckpt":
      "772cd148b7254d16cd934aad380362cde8869edb34f787eb7cc4776a64e3d5a2",
    "image_vit_l14_f16.ckpt":
      "f75c2ac4b5f8e0c59001ce05ecf5b11ee893f7687b2154075c2ddd7c11fe9b32",
    "deliberate_v2_q6p_q8p.ckpt":
      "4441ea31f748a5af97021747bc457e78ae0c8d632f819a26cb8019610972c0f0",
    "deliberate_v2_clip_vit_l14_f16.ckpt":
      "79dc846fe47f4bd5188bce108c9791f36cc2927bed6f96c8dc7369b345539d81",
    "disney_pixar_cartoon_type_b_q6p_q8p.ckpt":
      "31f38b788e1acdde65288f1e3780c64df9c98cd5fa7fa38bce5bce085f633d95",
    "disney_pixar_cartoon_type_b_clip_vit_l14_f16.ckpt":
      "0401d93b66dff9de82521765bbcb2292904a247e22155158d91f83aef4b4d351",
    "realistic_vision_v3.0_q6p_q8p.ckpt":
      "6a4294760fb82295522cd7d610c95269070c403e5a4b41f67ce2db93fd93ee3a",
    "realistic_vision_v3.0_clip_vit_l14_f16.ckpt":
      "71f1c7726f842d72fe04a7e17ee468c32752d097b89e9114708c0dc13a0060a2",
    "dreamshaper_v6.31_q6p_q8p.ckpt":
      "14a9c0e4a5ebb4a66d4fd882135e60a3951e5d1d96e802cbf2106e91427e349f",
    "dreamshaper_v6.31_clip_vit_l14_f16.ckpt":
      "7384f31ea620891a7bca84c3b537beda7dbc5473873c90810b797e14ab263fc4",
    "open_clip_vit_bigg14_f16.ckpt":
      "1bc61283f12c3b923f4366a27d316742c0610aa934803481f0b5277124b9a8f4",
    "sd_xl_base_0.9_f16.ckpt": "e7613b7593f8f48b3799b3b9d2308ec2e4327cdd5f4904717d10846e0d13e661",
    "sd_xl_refiner_0.9_f16.ckpt":
      "b6e830f2d2084ca078178178aa67b31d85b17a772304e2ed39927e2f39487277",
    "sdxl_vae_f16.ckpt": "275decbdbe986f55bb20018bd636e3b0a8b0a6a3b8c28754262dcb84f33a62d7",
    "sdxl_vae_v1.0_f16.ckpt": "8ceb1b62fc9b88c20a171452fef55e3a5546cc621c943c78188f648351b4d7e4",
    "sd_xl_base_1.0_f16.ckpt": "741f813f9f7f17bf9e284885fa73b5098a30dc6db336179116e8749da10657a3",
    "sd_xl_refiner_1.0_f16.ckpt":
      "73abf6538793530fe3a2358a5789b7906db4e6dc30ce8d9d34b87a506fa2e34c",
    "sd_xl_base_1.0_q6p_q8p.ckpt":
      "796210c27eec08fd7ea01ad42eaf93efac5783b3f25df60906601a0a293a8f45",
    "sd_xl_refiner_1.0_q6p_q8p.ckpt":
      "be4f78ff34302d1cfbc91c1e83945e798bc58b0bc35ac08209d8d5a66b30c214",
    "ssd_1b_f16.ckpt": "8fed449f74cefadf9f10300eaa704d2fa0601bf087c1196560ce861aa6ab3d68",
    "ssd_1b_q6p_q8p.ckpt": "a4096821ac5fbc9c34be2fe86ca5b0e9d2f0cc64fd9c3ba47e1efe02cec5da09",
    "lcm_sd_xl_base_1.0_f16.ckpt":
      "937a0851d1c3fbb7b546d94edfad014db854721c596e0694d9e4ca7d6e8cd8de",
    "lcm_sd_xl_base_1.0_q6p_q8p.ckpt":
      "0830466d22f5304f415e2d96ab16244f21a2257d5e906ed63a467a393a38c250",
    "lcm_ssd_1b_f16.ckpt": "e1156cc6e6927a462102629d030e3d6377e373664201dad79fb1ff4928bb85b0",
    "lcm_ssd_1b_q6p_q8p.ckpt": "959d09951bdba0a73fafb6a69fed83b21012cbc4df78991463bbd84e283cc6fe",
    "sd_xl_turbo_f16.ckpt": "c85ea750f1ff5d17c032465c07f854eaf5f1551e27bd85dbe9c2d1025a41e004",
    "sd_xl_turbo_q6p_q8p.ckpt": "a8072ace4eb3d6590db8abe8fda6c0c22f4c3e68efb86f0e58a27dc4f68731ef",
    "open_clip_vit_h14_vision_model_f16.ckpt":
      "87b70da1898b05bfc7b53e3587fb5c0383fe4f48ccae286e8dde217bbee1e80d",
    "svd_i2v_1.0_f16.ckpt": "5751756a84bd9b6c91d2d6df7393d066d046e8ca939a8b8fa4ac358a07acaf94",
    "svd_i2v_1.0_q6p_q8p.ckpt": "5c8e4c1a1291456c5516c4c66d094eada0e11660c7b474cc39e45c9ceff27309",
    "svd_i2v_xt_1.0_f16.ckpt": "e5fd1a2f5fb7f1a13424e577a13c04dfd873b1cc6e3cdebc4c797d97d21a6865",
    "svd_i2v_xt_1.0_q6p_q8p.ckpt":
      "f3c4a06c1a1cb71a6b032e2ceb2d04e1d9c8457c455f8984f5324bbd8ba6d2e2",
    "fooocus_inpaint_sd_xl_v2.6_f16.ckpt":
      "f93886d787043cab976d31376b072bdc320185606331349ace9b48c41eeda867",
    "fooocus_inpaint_sd_xl_v2.6_q6p_q8p.ckpt":
      "f299e673da2d0da8ffccd6a01e9901261a9091a278032316c3218598ee9b5f2d",
    "svd_i2v_xt_1.1_f16.ckpt": "cd4d0c43c6cd3a3af51e35d465e2cec5292778f9cd12c92b64873f59de6ef314",
    "svd_i2v_xt_1.1_q6p_q8p.ckpt":
      "61c6fe0cce4d91fc1b83dd65f956624dc2c996fb21fdc4fa847fbf4bc97e0030",
    "wurstchen_3.0_stage_a_hq_f16.ckpt":
      "ad9d2b43ceb68f9bb9d269a6a5fd345a5f177a0f695189be82219cb4d2740277",
    "wurstchen_3.0_stage_b_q6p_q8p.ckpt":
      "b0611225cf2f2a7b9109ae18eaf12bfe04ae60010ac5ea715440d79708e578b8",
    "wurstchen_3.0_stage_c_f32_q6p_q8p.ckpt":
      "0e57d6f6c7749a34ea362a115558aeeb209da82e54b06e3b97433ed64b244439",
    "wurstchen_3.0_stage_b_f16.ckpt":
      "a541358038cb86064a4d43bd0b6dab1cb95129520fca67eb178bce3baccc1d02",
    "wurstchen_3.0_stage_c_f32_f16.ckpt":
      "aa05651d1920d1fd0b70d06397548bf9e77fac93ff4b4bc9bc98cea749e5a8db",
    "playground_v2.5_f16.ckpt": "9a8e167526a65d5caebfd6d5163705672cfd4d201cb273d11c174e46af041b4a",
    "playground_v2.5_q6p_q8p.ckpt":
      "18ddd151c7ae188b6a0036c72bf8b7cd395479472400a3ed4d1eb8e5e65b36e3",
    "open_clip_vit_h14_visual_proj_f16.ckpt":
      "ef03b8ac7805d5a862db048c452c4dbbd295bd95fed0bf5dae50a6e98815d30f",
  ]

  public static let defaultSpecification: Specification = builtinSpecifications[0]

  public static let builtinSpecifications: [Specification] = [
    Specification(
      name: "SDXL Base (v0.9)", file: "sd_xl_base_0.9_f16.ckpt", prefix: "", version: .sdxlBase,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "SDXL Refiner (v0.9)", file: "sd_xl_refiner_0.9_f16.ckpt", prefix: "",
      version: .sdxlRefiner, defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "SDXL Base (v1.0)", file: "sd_xl_base_1.0_f16.ckpt", prefix: "", version: .sdxlBase,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "SDXL Base v1.0 (8-bit)", file: "sd_xl_base_1.0_q6p_q8p.ckpt", prefix: "",
      version: .sdxlBase,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "SDXL Turbo", file: "sd_xl_turbo_f16.ckpt", prefix: "",
      version: .sdxlBase,
      defaultScale: 8, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", clipEncoder: "clip_vit_l14_f16.ckpt",
      isConsistencyModel: true),
    Specification(
      name: "SDXL Turbo (8-bit)", file: "sd_xl_turbo_q6p_q8p.ckpt", prefix: "",
      version: .sdxlBase,
      defaultScale: 8, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", clipEncoder: "clip_vit_l14_f16.ckpt",
      isConsistencyModel: true),
    Specification(
      name: "Stable Cascade (Würstchen v3.0)", file: "wurstchen_3.0_stage_c_f32_f16.ckpt",
      prefix: "",
      version: .wurstchenStageC, upcastAttention: false, defaultScale: 16,
      textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "wurstchen_3.0_stage_a_hq_f16.ckpt",
      stageModels: ["wurstchen_3.0_stage_b_f16.ckpt"]
    ),
    Specification(
      name: "Stable Cascade (Würstchen v3.0, 8-bit)",
      file: "wurstchen_3.0_stage_c_f32_q6p_q8p.ckpt",
      prefix: "",
      version: .wurstchenStageC, upcastAttention: false, defaultScale: 16,
      textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "wurstchen_3.0_stage_a_hq_f16.ckpt",
      stageModels: ["wurstchen_3.0_stage_b_q6p_q8p.ckpt"]
    ),
    Specification(
      name: "LCM SDXL Base (v1.0)", file: "lcm_sd_xl_base_1.0_f16.ckpt", prefix: "",
      version: .sdxlBase,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt",
      isConsistencyModel: true),
    Specification(
      name: "LCM SDXL Base v1.0 (8-bit)", file: "lcm_sd_xl_base_1.0_q6p_q8p.ckpt", prefix: "",
      version: .sdxlBase,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt",
      isConsistencyModel: true),
    Specification(
      name: "SDXL Refiner (v1.0)", file: "sd_xl_refiner_1.0_f16.ckpt", prefix: "",
      version: .sdxlRefiner, defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "SDXL Refiner v1.0 (8-bit)", file: "sd_xl_refiner_1.0_q6p_q8p.ckpt", prefix: "",
      version: .sdxlRefiner, defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "Fooocus Inpaint SDXL v2.6", file: "fooocus_inpaint_sd_xl_v2.6_f16.ckpt", prefix: "",
      version: .sdxlBase, defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", modifier: .inpainting,
      clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "Fooocus Inpaint SDXL v2.6 (8-bit)", file: "fooocus_inpaint_sd_xl_v2.6_q6p_q8p.ckpt",
      prefix: "", version: .sdxlBase, defaultScale: 16,
      textEncoder: "open_clip_vit_bigg14_f16.ckpt", autoencoder: "sdxl_vae_v1.0_f16.ckpt",
      modifier: .inpainting, clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "Generic (Stable Diffusion v1.4)", file: "sd_v1.4_f16.ckpt", prefix: "", version: .v1,
      deprecated: true),
    Specification(
      name: "Generic (Stable Diffusion v1.5)", file: "sd_v1.5_f16.ckpt", prefix: "", version: .v1),
    Specification(
      name: "Inpainting (Stable Diffusion v1.5 Inpainting)", file: "sd_v1.5_inpainting_f16.ckpt",
      prefix: "", version: .v1, modifier: .inpainting),
    Specification(
      name: "Generic (Stable Diffusion v2.0)", file: "sd_v2.0_f16.ckpt", prefix: "", version: .v2,
      textEncoder: "open_clip_vit_h14_f16.ckpt", deprecated: true),
    Specification(
      name: "Generic HD (Stable Diffusion v2.0 768-v)", file: "sd_v2.0_768_v_f16.ckpt", prefix: "",
      version: .v2, defaultScale: 12, textEncoder: "open_clip_vit_h14_f16.ckpt", deprecated: true,
      objective: .v),
    Specification(
      name: "Inpainting (Stable Diffusion v2.0 Inpainting)", file: "sd_v2.0_inpainting_f16.ckpt",
      prefix: "", version: .v2, textEncoder: "open_clip_vit_h14_f16.ckpt", modifier: .inpainting),
    Specification(
      name: "Depth (Stable Diffusion v2.0 Depth)", file: "sd_v2.0_depth_f16.ckpt",
      prefix: "", version: .v2, textEncoder: "open_clip_vit_h14_f16.ckpt", modifier: .depth),
    Specification(
      name: "Generic (Stable Diffusion v2.1)", file: "sd_v2.1_f16.ckpt", prefix: "", version: .v2,
      textEncoder: "open_clip_vit_h14_f16.ckpt"),
    Specification(
      name: "Generic HD (Stable Diffusion v2.1 768-v)", file: "sd_v2.1_768_v_f16.ckpt", prefix: "",
      version: .v2, upcastAttention: true, defaultScale: 12,
      textEncoder: "open_clip_vit_h14_f16.ckpt", objective: .v),
    Specification(
      name: "Multi-Language HD (Kandinsky v2.1)", file: "kandinsky_f16.ckpt", prefix: "",
      version: .kandinsky21, upcastAttention: false, defaultScale: 12,
      textEncoder: "xlm_roberta_f16.ckpt", autoencoder: "kandinsky_movq_f16.ckpt",
      deprecated: true, imageEncoder: "image_vit_l14_f16.ckpt",
      clipEncoder: "clip_vit_l14_f16.ckpt",
      diffusionMapping: "kandinsky_diffusion_mapping_f16.ckpt"),
    Specification(
      name: "Stable Video Diffusion I2V v1.0", file: "svd_i2v_1.0_f16.ckpt", prefix: "",
      version: .svdI2v,
      defaultScale: 8, textEncoder: "open_clip_vit_h14_vision_model_f16.ckpt",
      clipEncoder: "svd_i2v_1.0_f16.ckpt", conditioning: .noise, objective: .v,
      noiseDiscretization: .edm(.init(sigmaMax: 700.0))),
    Specification(
      name: "Stable Video Diffusion I2V 1.0 (8-bit)", file: "svd_i2v_1.0_q6p_q8p.ckpt", prefix: "",
      version: .svdI2v,
      defaultScale: 8, textEncoder: "open_clip_vit_h14_vision_model_f16.ckpt",
      clipEncoder: "svd_i2v_1.0_q6p_q8p.ckpt", conditioning: .noise, objective: .v,
      noiseDiscretization: .edm(.init(sigmaMax: 700.0))),
    Specification(
      name: "Stable Video Diffusion I2V XT v1.0", file: "svd_i2v_xt_1.0_f16.ckpt", prefix: "",
      version: .svdI2v,
      defaultScale: 8, textEncoder: "open_clip_vit_h14_vision_model_f16.ckpt", deprecated: true,
      clipEncoder: "svd_i2v_xt_1.0_f16.ckpt", conditioning: .noise, objective: .v,
      noiseDiscretization: .edm(.init(sigmaMax: 700.0))),
    Specification(
      name: "Stable Video Diffusion I2V XT 1.0 (8-bit)", file: "svd_i2v_xt_1.0_q6p_q8p.ckpt",
      prefix: "",
      version: .svdI2v,
      defaultScale: 8, textEncoder: "open_clip_vit_h14_vision_model_f16.ckpt", deprecated: true,
      clipEncoder: "svd_i2v_xt_1.0_q6p_q8p.ckpt", conditioning: .noise, objective: .v,
      noiseDiscretization: .edm(.init(sigmaMax: 700.0))),
    Specification(
      name: "Stable Video Diffusion I2V XT v1.1", file: "svd_i2v_xt_1.1_f16.ckpt", prefix: "",
      version: .svdI2v,
      defaultScale: 8, textEncoder: "open_clip_vit_h14_vision_model_f16.ckpt",
      clipEncoder: "svd_i2v_xt_1.1_f16.ckpt", conditioning: .noise, objective: .v,
      noiseDiscretization: .edm(.init(sigmaMax: 700.0))),
    Specification(
      name: "Stable Video Diffusion I2V XT 1.1 (8-bit)", file: "svd_i2v_xt_1.1_q6p_q8p.ckpt",
      prefix: "", version: .svdI2v,
      defaultScale: 8, textEncoder: "open_clip_vit_h14_vision_model_f16.ckpt",
      clipEncoder: "svd_i2v_xt_1.1_q6p_q8p.ckpt", conditioning: .noise, objective: .v,
      noiseDiscretization: .edm(.init(sigmaMax: 700.0))),
    Specification(
      name: "Playground v2.5", file: "playground_v2.5_f16.ckpt", prefix: "",
      version: .sdxlBase,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt",
      conditioning: .noise, objective: .edm(sigmaData: 0.5), noiseDiscretization: .edm(.init()),
      latentsMean: [-1.6574, 1.886, -1.383, 2.5155], latentsStd: [8.4927, 5.9022, 6.5498, 5.2299],
      latentsScalingFactor: 0.5),
    Specification(
      name: "Playground v2.5 (8-bit)", file: "playground_v2.5_q6p_q8p.ckpt", prefix: "",
      version: .sdxlBase,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt",
      conditioning: .noise, objective: .edm(sigmaData: 0.5), noiseDiscretization: .edm(.init()),
      latentsMean: [-1.6574, 1.886, -1.383, 2.5155], latentsStd: [8.4927, 5.9022, 6.5498, 5.2299],
      latentsScalingFactor: 0.5),
    Specification(
      name: "SSD 1B (Segmind SDXL)", file: "ssd_1b_f16.ckpt", prefix: "",
      version: .ssd1b,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "SSD 1B (8-bit)", file: "ssd_1b_q6p_q8p.ckpt", prefix: "",
      version: .ssd1b,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt"),
    Specification(
      name: "LCM SSD 1B (Segmind SDXL)", file: "lcm_ssd_1b_f16.ckpt", prefix: "",
      version: .ssd1b,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt",
      isConsistencyModel: true),
    Specification(
      name: "LCM SSD 1B (8-bit)", file: "lcm_ssd_1b_q6p_q8p.ckpt", prefix: "",
      version: .ssd1b,
      defaultScale: 16, textEncoder: "open_clip_vit_bigg14_f16.ckpt",
      autoencoder: "sdxl_vae_v1.0_f16.ckpt", deprecated: true, clipEncoder: "clip_vit_l14_f16.ckpt",
      isConsistencyModel: true),
    Specification(
      name: "Generic SD (MiniSD v1.4)", file: "minisd_v1.4_f16.ckpt", prefix: "", version: .v1,
      defaultScale: 4, deprecated: true),
    Specification(
      name: "Editing (Instruct Pix2Pix)", file: "instruct_pix2pix_22000_f16.ckpt", prefix: "",
      version: .v1,
      defaultScale: 8, modifier: .editing, deprecated: true),
    Specification(
      name: "Anime (Waifu Diffusion v1.3)", file: "wd_v1.3_f16.ckpt", prefix: "", version: .v1,
      deprecated: true),
    Specification(
      name: "Multi-Style (Nitro Diffusion v1)", file: "nitro_v1_f16.ckpt", prefix: "", version: .v1,
      textEncoder: "nitro_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Cyberpunk Anime", file: "cyberpunk_anime_f16.ckpt", prefix: "dgs illustration style ",
      version: .v1,
      textEncoder: "cyberpunk_anime_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "3D Model (Redshift v1)", file: "redshift_v1_f16.ckpt", prefix: "redshift style ",
      version: .v1,
      textEncoder: "redshift_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "3D Model 768 (Redshift 768)", file: "redshift_768_v_f16.ckpt",
      prefix: "redshift style ",
      version: .v2, defaultScale: 12,
      textEncoder: "redshift_768_v_open_clip_vit_h14_f16.ckpt", deprecated: true, objective: .v),
    Specification(
      name: "Dungeons and Diffusion (30000)", file: "dnd_30000_f16.ckpt", prefix: "", version: .v1,
      textEncoder: "dnd_30000_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Tron Legacy", file: "trnlgcy_f16.ckpt", prefix: "trnlgcy style ", version: .v1,
      textEncoder: "trnlgcy_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Openjourney", file: "mdjrny_v4_f16.ckpt", prefix: "mdjrny-v4 style ", version: .v1,
      textEncoder: "mdjrny_v4_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Anime (Anything v3)", file: "anything_v3_f16.ckpt", prefix: "", version: .v1,
      textEncoder: "anything_v3_clip_vit_l14_f16.ckpt", autoencoder: "anything_v3_vae_f16.ckpt",
      deprecated: true),
    Specification(
      name: "Classic Animation (v1)", file: "classicanim_v1_f16.ckpt",
      prefix: "classic disney style ", version: .v1,
      textEncoder: "classicanim_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Modern Disney (v1)", file: "modi_v1_f16.ckpt", prefix: "modern disney style ",
      version: .v1,
      textEncoder: "modi_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Arcane (v3)", file: "arcane_v3_f16.ckpt", prefix: "arcane style ", version: .v1,
      textEncoder: "arcane_v3_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Hassanblend (v1.4)", file: "hassanblend_v1.4_f16.ckpt", prefix: "", version: .v1,
      deprecated: true),
    Specification(
      name: "Hassanblend (v1.5.1.2)", file: "hassanblend_v1.5.1.2_f16.ckpt", prefix: "",
      version: .v1, textEncoder: "hassanblend_v1.5.1.2_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Van Gogh Style (Lvngvncnt v2)", file: "lvngvncnt_v2_f16.ckpt", prefix: "lvngvncnt ",
      version: .v1, textEncoder: "lvngvncnt_v2_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Spider-Verse (v1)", file: "spiderverse_v1_f16.ckpt", prefix: "spiderverse style ",
      version: .v1, textEncoder: "spiderverse_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Elden Ring (v3)", file: "eldenring_v3_f16.ckpt", prefix: "elden ring style ",
      version: .v1, textEncoder: "eldenring_v3_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Paper Cut (v1)", file: "papercut_v1_f16.ckpt", prefix: "papercut ",
      version: .v1, textEncoder: "papercut_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "VoxelArt (v1)", file: "voxelart_v1_f16.ckpt", prefix: "voxelart ",
      version: .v1, textEncoder: "voxelart_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Balloon Art (v1)", file: "balloonart_v1_f16.ckpt", prefix: "balloonart ",
      version: .v1, textEncoder: "balloonart_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "F222", file: "f222_f16.ckpt", prefix: "", version: .v1, deprecated: true),
    Specification(
      name: "Super Mario Nation (v2)", file: "supermarionation_v2_f16.ckpt",
      prefix: "supermarionation ", version: .v1,
      textEncoder: "supermarionation_v2_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Inkpunk (v2)", file: "inkpunk_v2_f16.ckpt", prefix: "nvinkpunk ", version: .v1,
      textEncoder: "inkpunk_v2_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "SamDoesArt (v3)", file: "samdoesart_v3_f16.ckpt", prefix: "samdoesart ", version: .v1,
      textEncoder: "samdoesart_v3_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Ghibli (v1)", file: "ghibli_v1_f16.ckpt", prefix: "ghibli style ", version: .v1,
      textEncoder: "ghibli_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Analog (v1)", file: "analog_v1_f16.ckpt", prefix: "analog style ", version: .v1,
      textEncoder: "analog_v1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "DnD Classes and Species", file: "dnd_classes_and_species_f16.ckpt", prefix: "",
      version: .v1,
      textEncoder: "dnd_classes_and_species_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "AloeVera's SimpMaker 3K1", file: "aloeveras_simpmaker_3k1_f16.ckpt", prefix: "",
      version: .v1, deprecated: true),
    Specification(
      name: "H&A's 3DKX 1.0b", file: "hna_3dkx_1.0b_f16.ckpt", prefix: "a 3d render / cartoon of ",
      version: .v1, textEncoder: "hna_3dkx_1.0b_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "H&A's 3DKX 1.1", file: "hna_3dkx_1.1_f16.ckpt", prefix: "a 3d render / cartoon of ",
      version: .v1, textEncoder: "hna_3dkx_1.1_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "seek.art MEGA (v1)", file: "seek_art_mega_v1_f16.ckpt", prefix: "",
      version: .v1, defaultScale: 10, textEncoder: "seek_art_mega_v1_clip_vit_l14_f16.ckpt",
      deprecated: true),
    Specification(
      name: "Deliberate v2.0 (8-bit)", file: "deliberate_v2_q6p_q8p.ckpt", prefix: "",
      version: .v1, textEncoder: "deliberate_v2_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "Disney Pixar Cartoon Type B (8-bit)", file: "disney_pixar_cartoon_type_b_q6p_q8p.ckpt",
      prefix: "", version: .v1, textEncoder: "disney_pixar_cartoon_type_b_clip_vit_l14_f16.ckpt",
      deprecated: true),
    Specification(
      name: "Realistic Vision v3.0 (8-bit)", file: "realistic_vision_v3.0_q6p_q8p.ckpt", prefix: "",
      version: .v1, textEncoder: "realistic_vision_v3.0_clip_vit_l14_f16.ckpt", deprecated: true),
    Specification(
      name: "DreamShaper v6.31 (8-bit)", file: "dreamshaper_v6.31_q6p_q8p.ckpt", prefix: "",
      version: .v1, textEncoder: "dreamshaper_v6.31_clip_vit_l14_f16.ckpt", deprecated: true),
  ]

  private static let builtinModelsAndAvailableSpecifications: (Set<String>, [Specification]) = {
    let jsonFile = ModelZoo.filePathForOtherModelDownloaded("custom.json")
    guard let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonFile)) else {
      return (Set(builtinSpecifications.map { $0.file }), builtinSpecifications)
    }
    let jsonDecoder = JSONDecoder()
    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let jsonSpecifications = try? jsonDecoder.decode([Specification].self, from: jsonData)
    else {
      return (Set(builtinSpecifications.map { $0.file }), builtinSpecifications)
    }
    var availableSpecifications = builtinSpecifications
    var builtinModels = Set(builtinSpecifications.map { $0.file })
    for specification in jsonSpecifications {
      if builtinModels.contains(specification.file) {
        builtinModels.remove(specification.file)
        // Remove this from previous list.
        availableSpecifications = availableSpecifications.filter { $0.file != specification.file }
      }
      availableSpecifications.append(specification)
    }
    return (builtinModels, availableSpecifications)
  }()

  private static let builtinModels: Set<String> = builtinModelsAndAvailableSpecifications.0
  public static var availableSpecifications: [Specification] =
    builtinModelsAndAvailableSpecifications.1

  public static func availableSpecificationForTriggerWord(_ triggerWord: String) -> Specification? {
    let cleanupTriggerWord = String(triggerWord.lowercased().filter { $0.isLetter || $0.isNumber })
    for specification in availableSpecifications {
      if String(specification.name.lowercased().filter { $0.isLetter || $0.isNumber }).contains(
        cleanupTriggerWord)
      {
        return specification
      }
    }
    return nil
  }

  public static func sortCustomSpecifications() {
    dispatchPrecondition(condition: .onQueue(.main))
    var customSpecifications = [Specification]()
    let jsonFile = ModelZoo.filePathForOtherModelDownloaded("custom.json")
    if let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonFile)) {
      let jsonDecoder = JSONDecoder()
      jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
      if let jsonSpecification = try? jsonDecoder.decode([Specification].self, from: jsonData) {
        customSpecifications.append(contentsOf: jsonSpecification)
      }
    }
    customSpecifications = customSpecifications.sorted(by: {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    })

    let jsonEncoder = JSONEncoder()
    jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    jsonEncoder.outputFormatting = .prettyPrinted
    guard let jsonData = try? jsonEncoder.encode(customSpecifications) else { return }
    try? jsonData.write(to: URL(fileURLWithPath: jsonFile), options: .atomic)

    // Because this only does sorting, it won't impact the builtinModels set.
    var availableSpecifications = builtinSpecifications
    let builtinModels = Set(builtinSpecifications.map { $0.file })
    for specification in customSpecifications {
      if builtinModels.contains(specification.file) {
        availableSpecifications = availableSpecifications.filter { $0.file != specification.file }
      }
      availableSpecifications.append(specification)
    }
    self.availableSpecifications = availableSpecifications
  }

  public static func appendCustomSpecification(_ specification: Specification) {
    dispatchPrecondition(condition: .onQueue(.main))
    var customSpecifications = [Specification]()
    let jsonFile = ModelZoo.filePathForOtherModelDownloaded("custom.json")
    if let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonFile)) {
      let jsonDecoder = JSONDecoder()
      jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
      if let jsonSpecification = try? jsonDecoder.decode([Specification].self, from: jsonData) {
        customSpecifications.append(contentsOf: jsonSpecification)
      }
    }
    customSpecifications = customSpecifications.filter { $0.file != specification.file }
    customSpecifications.append(specification)
    let jsonEncoder = JSONEncoder()
    jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    jsonEncoder.outputFormatting = .prettyPrinted
    guard let jsonData = try? jsonEncoder.encode(customSpecifications) else { return }
    try? jsonData.write(to: URL(fileURLWithPath: jsonFile), options: .atomic)
    // Modify these two are not thread safe. availableSpecifications are OK. specificationMapping is particularly problematic (as it is access on both main thread and a background thread).
    var availableSpecifications = availableSpecifications
    availableSpecifications = availableSpecifications.filter { $0.file != specification.file }
    // Still respect the order.
    availableSpecifications.append(specification)
    self.availableSpecifications = availableSpecifications
    specificationMapping[specification.file] = specification
  }

  private static var specificationMapping: [String: Specification] = {
    var mapping = [String: Specification]()
    for specification in availableSpecifications {
      mapping[specification.file] = specification
    }
    return mapping
  }()

  public static var anyModelDownloaded: String? {
    let availableSpecifications = availableSpecifications
    for specification in availableSpecifications {
      if isModelDownloaded(specification) {
        return specification.file
      }
    }
    return nil
  }

  private static func filePathForDefaultModelDownloaded(_ name: String) -> String {
    let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let modelZooUrl = urls.first!.appendingPathComponent("model_zoo")
    try? FileManager.default.createDirectory(at: modelZooUrl, withIntermediateDirectories: true)
    return modelZooUrl.appendingPathComponent(name).path
  }

  private static func filePathForOtherModelDownloaded(_ name: String) -> String {
    let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let modelZooUrl = urls.first!.appendingPathComponent("Models")
    try? FileManager.default.createDirectory(at: modelZooUrl, withIntermediateDirectories: true)
    return modelZooUrl.appendingPathComponent(name).path
  }

  public static var externalUrl: URL? = nil {
    didSet {
      #if (os(macOS) || (os(iOS) && targetEnvironment(macCatalyst)))
        oldValue?.stopAccessingSecurityScopedResource()
        let _ = externalUrl?.startAccessingSecurityScopedResource()
      #endif
    }
  }

  public static func specificationForHumanReadableModel(_ name: String) -> Specification? {
    return availableSpecifications.first { $0.name == name }
  }

  public static func specificationForModel(_ name: String) -> Specification? {
    return specificationMapping[name]
  }

  public static func internalFilePathForModelDownloaded(_ name: String) -> String {
    return filePathForOtherModelDownloaded(name)
  }

  public static func filePathForModelDownloaded(_ name: String) -> String {
    guard let externalUrl = externalUrl else {
      return filePathForOtherModelDownloaded(name)
    }
    // If it exists at internal storage, prefer that.
    let otherFilePath = filePathForOtherModelDownloaded(name)
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: otherFilePath) else {
      return otherFilePath
    }
    // Check external storage, return path at external storage regardless.
    let filePath = externalUrl.appendingPathComponent(name).path
    return filePath
  }

  public static func isModelDownloaded(_ specification: Specification) -> Bool {
    var result =
      isModelDownloaded(specification.file)
      && isModelDownloaded(specification.autoencoder ?? "vae_ft_mse_840000_f16.ckpt")
      && isModelDownloaded(
        specification.textEncoder
          ?? (specification.version == .v1 ? "clip_vit_l14_f16.ckpt" : "open_clip_vit_h14_f16.ckpt")
      )
    if let imageEncoder = specification.imageEncoder {
      result = result && isModelDownloaded(imageEncoder)
    }
    if let clipEncoder = specification.clipEncoder {
      result = result && isModelDownloaded(clipEncoder)
    }
    if let diffusionMapping = specification.diffusionMapping {
      result = result && isModelDownloaded(diffusionMapping)
    }
    return result
  }

  public static func isModelInExternalUrl(_ name: String) -> Bool {
    guard let externalUrl = externalUrl else {
      return false
    }
    return FileManager.default.fileExists(atPath: externalUrl.appendingPathComponent(name).path)
  }

  public static func isModelDownloaded(_ name: String) -> Bool {
    let fileManager = FileManager.default
    if let externalUrl = externalUrl {
      let filePath = externalUrl.appendingPathComponent(name).path
      if fileManager.fileExists(atPath: filePath) {
        return true
      }
    }
    let otherModelPath = filePathForOtherModelDownloaded(name)
    if fileManager.fileExists(atPath: otherModelPath) {
      return true
    }
    // Move the file to the document directory so people can manage it themselves.
    let defaultModelPath = filePathForDefaultModelDownloaded(name)
    if fileManager.fileExists(atPath: defaultModelPath) {
      try? fileManager.moveItem(atPath: defaultModelPath, toPath: otherModelPath)
      return true
    }
    return false
  }

  public static func isBuiltinModel(_ name: String) -> Bool {
    return builtinModels.contains(name)
  }

  public static func humanReadableNameForModel(_ name: String) -> String {
    guard let specification = specificationMapping[name] else { return name }
    return specification.name
  }

  public static func textPrefixForModel(_ name: String) -> String {
    guard let specification = specificationMapping[name] else { return "" }
    return specification.prefix
  }

  public static func textEncoderForModel(_ name: String) -> String? {
    guard let specification = specificationMapping[name] else { return nil }
    return specification.textEncoder
  }

  public static func imageEncoderForModel(_ name: String) -> String? {
    guard let specification = specificationMapping[name] else { return nil }
    return specification.imageEncoder
  }

  public static func CLIPEncoderForModel(_ name: String) -> String? {
    guard let specification = specificationMapping[name] else { return nil }
    return specification.clipEncoder
  }

  public static func diffusionMappingForModel(_ name: String) -> String? {
    guard let specification = specificationMapping[name] else { return nil }
    return specification.diffusionMapping
  }

  public static func versionForModel(_ name: String) -> ModelVersion {
    guard let specification = specificationMapping[name] else { return .v1 }
    return specification.version
  }

  public static func autoencoderForModel(_ name: String) -> String? {
    guard let specification = specificationMapping[name] else { return nil }
    return specification.autoencoder
  }

  public static func isModelDeprecated(_ name: String) -> Bool {
    guard let specification = specificationMapping[name] else { return false }
    return specification.deprecated ?? false
  }

  public static func objectiveForModel(_ name: String) -> Denoiser.Objective {
    guard let specification = specificationMapping[name] else { return .epsilon }
    return specification.objective ?? (specification.predictV == true ? .v : .epsilon)
  }

  public static func conditioningForModel(_ name: String) -> Denoiser.Conditioning {
    guard let specification = specificationMapping[name] else { return .timestep }
    if let conditioning = specification.conditioning {
      return conditioning
    }
    switch specification.version {
    case .kandinsky21, .sdxlBase, .sdxlRefiner, .v1, .v2, .ssd1b, .wurstchenStageC,
      .wurstchenStageB:
      return .timestep
    case .svdI2v:
      return .noise
    }
  }

  public static func noiseDiscretizationForModel(_ name: String) -> NoiseDiscretization {
    guard let specification = specificationMapping[name] else {
      return .ddpm(
        .init(linearStart: 0.00085, linearEnd: 0.012, timesteps: 1_000, linspace: .linearWrtSigma))
    }
    if let noiseDiscretization = specification.noiseDiscretization {
      return noiseDiscretization
    }
    switch specification.version {
    case .kandinsky21:
      return .ddpm(
        .init(linearStart: 0.00085, linearEnd: 0.012, timesteps: 1_000, linspace: .linearWrtBeta))
    case .sdxlBase, .sdxlRefiner, .ssd1b, .v1, .v2:
      return .ddpm(
        .init(linearStart: 0.00085, linearEnd: 0.012, timesteps: 1_000, linspace: .linearWrtSigma))
    case .svdI2v:
      return .edm(.init(sigmaMax: 700.0))
    case .wurstchenStageC, .wurstchenStageB:
      return .edm(.init(sigmaMin: 0.01, sigmaMax: 99.995))
    }
  }

  public static func latentsScalingForModel(_ name: String) -> (
    mean: [Float]?, std: [Float]?, scalingFactor: Float
  ) {
    guard let specification = specificationMapping[name] else { return (nil, nil, 1) }
    if let mean = specification.latentsMean, let std = specification.latentsStd,
      let scalingFactor = specification.latentsScalingFactor
    {
      return (mean, std, scalingFactor)
    }
    if let scalingFactor = specification.latentsScalingFactor {
      return (nil, nil, scalingFactor)
    }
    switch specification.version {
    case .v1, .v2, .svdI2v:
      return (nil, nil, 0.18215)
    case .ssd1b, .sdxlBase, .sdxlRefiner:
      return (nil, nil, 0.13025)
    case .kandinsky21:
      return (nil, nil, 1)
    case .wurstchenStageC, .wurstchenStageB:
      return (nil, nil, 2.32558139535)
    }
  }

  public static func stageModelsForModel(_ name: String) -> [String] {
    guard let specification = specificationMapping[name] else { return [] }
    return specification.stageModels ?? []
  }

  public static func isUpcastAttentionForModel(_ name: String) -> Bool {
    guard let specification = specificationMapping[name] else { return false }
    return specification.upcastAttention
  }

  public static func isHighPrecisionAutoencoderForModel(_ name: String) -> Bool {
    guard let specification = specificationMapping[name] else { return false }
    return specification.highPrecisionAutoencoder ?? false
  }

  public static func modifierForModel(_ name: String) -> SamplerModifier {
    guard let specification = specificationMapping[name] else { return .none }
    return specification.modifier ?? .none
  }

  public static func isConsistencyModelForModel(_ name: String) -> Bool {
    guard let specification = specificationMapping[name] else { return false }
    return specification.isConsistencyModel ?? false
  }

  public static func defaultScaleForModel(_ name: String?) -> UInt16 {
    guard let name = name, let specification = specificationMapping[name] else { return 8 }
    return specification.defaultScale
  }

  public static func defaultRefinerForModel(_ name: String) -> String? {
    guard let specification = specificationMapping[name] else { return nil }
    return specification.defaultRefiner
  }

  public static func mergeFileSHA256(_ sha256: [String: String]) {
    var fileSHA256 = fileSHA256
    for (key, value) in sha256 {
      fileSHA256[key] = value
    }
    self.fileSHA256 = fileSHA256
  }

  public static func fileSHA256ForModelDownloaded(_ name: String) -> String? {
    return fileSHA256[name]
  }

  public static func is8BitModel(_ name: String) -> Bool {
    let filePath = Self.filePathForModelDownloaded(name)
    let fileSize = (try? URL(fileURLWithPath: filePath).resourceValues(forKeys: [.fileSizeKey]))?
      .fileSize
    let externalFileSize =
      (try? URL(fileURLWithPath: TensorData.externalStore(filePath: filePath)).resourceValues(
        forKeys: [.fileSizeKey]))?.fileSize
    if var fileSize = fileSize {
      fileSize += externalFileSize ?? 0
      let version = versionForModel(name)
      switch version {
      case .sdxlBase, .sdxlRefiner:
        return fileSize < 3 * 1_024 * 1_024 * 1_024
      case .ssd1b:
        return fileSize < 2 * 1_024 * 1_024 * 1_024
      case .v1, .v2:
        return fileSize < 1_024 * 1_024 * 1_024
      case .kandinsky21:
        return fileSize < 2 * 1_024 * 1_024 * 1_024
      case .svdI2v:
        return fileSize < 2 * 1_024 * 1_024 * 1_024
      case .wurstchenStageC:
        return fileSize < 4 * 1_024 * 1_024 * 1_024
      case .wurstchenStageB:
        return fileSize < 2 * 1_024 * 1_024 * 1_024
      }
    }
    return false
  }
}

extension ModelZoo {
  public static func ensureDownloadsDirectoryExists() {
    let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let downloadsUrl = urls.first!.appendingPathComponent("Downloads")
    try? FileManager.default.createDirectory(at: downloadsUrl, withIntermediateDirectories: true)
  }

  public static func allDownloadedFiles(
    _ includesSystemDownloadUrl: Bool = true,
    matchingSuffixes: [String] = [
      ".safetensors", ".ckpt", ".ckpt.zip", ".pt", ".pt.zip", ".pth", ".pth.zip", ".bin", ".patch",
    ]
  ) -> [String] {
    let fileManager = FileManager.default
    let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
    let downloadsUrl = urls.first!.appendingPathComponent("Downloads")
    let systemDownloadUrl = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    var fileUrls = [URL]()
    if let urls = try? fileManager.contentsOfDirectory(
      at: downloadsUrl, includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants])
    {
      fileUrls.append(contentsOf: urls)
    }
    if includesSystemDownloadUrl,
      let systemDownloadUrl = systemDownloadUrl?.resolvingSymlinksInPath(),
      let urls = try? fileManager.contentsOfDirectory(
        at: systemDownloadUrl, includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants])
    {
      // From the system download directory, we only include file with ckpt, pt or safetensors suffix.
      fileUrls.append(
        contentsOf: urls.filter {
          let path = $0.path.lowercased()
          return matchingSuffixes.contains { path.hasSuffix($0) }
        })
    }
    return fileUrls.compactMap {
      guard let values = try? $0.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
      guard let fileSize = values.fileSize, fileSize > 0 else { return nil }
      let file = $0.lastPathComponent
      guard !file.hasSuffix(".part") else { return nil }
      return file
    }
  }

  public static func filePathForDownloadedFile(_ file: String) -> String {
    let fileManager = FileManager.default
    let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
    let downloadsUrl = urls.first!.appendingPathComponent("Downloads")
    let filePath = downloadsUrl.appendingPathComponent(file).path
    if !fileManager.fileExists(atPath: filePath),
      // Check if the file exists in system download directory.
      let systemDownloadUrl = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    {
      let systemFilePath = systemDownloadUrl.appendingPathComponent(file).path
      return fileManager.fileExists(atPath: systemFilePath) ? systemFilePath : filePath
    }
    return filePath
  }

  public static func fileBytesForDownloadedFile(_ file: String) -> Int64 {
    let filePath = Self.filePathForDownloadedFile(file)
    let fileSize = (try? URL(fileURLWithPath: filePath).resourceValues(forKeys: [.fileSizeKey]))?
      .fileSize
    return Int64(fileSize ?? 0)
  }

  public static func availableFiles(excluding file: String?) -> Set<String> {
    var files = Set<String>()
    for specification in availableSpecifications {
      guard specification.file != file, ModelZoo.isModelDownloaded(specification.file) else {
        continue
      }
      files.insert(specification.file)
      let textEncoder = specification.textEncoder ?? "clip_vit_l14_f16.ckpt"
      files.insert(textEncoder)
      let autoencoder = specification.autoencoder ?? "vae_ft_mse_840000_f16.ckpt"
      files.insert(autoencoder)
      if let imageEncoder = specification.imageEncoder {
        files.insert(imageEncoder)
      }
      if let clipEncoder = specification.clipEncoder {
        files.insert(clipEncoder)
      }
      if let diffusionMapping = specification.diffusionMapping {
        files.insert(diffusionMapping)
      }
      if let stageModels = specification.stageModels {
        files.formUnion(stageModels)
      }
    }
    return files
  }
}
