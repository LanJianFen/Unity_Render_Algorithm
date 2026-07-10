//  Schlick 菲涅尔近似 (F项)
// F0 + (1 - F0) * pow (1 - N · H, 5)
float3 F_Schlick_Custom(float3 V, float3 H, float3 F0)
{
    float VdotH = dot(V, H);
    return F0 + (1.0f - F0) * pow(clamp(1.0f - VdotH, 0.0f, 1.0f), 5.0f);
}

float3 F_Schlick_Custom(float VdotH, float3 F0)
{
    return F0 + (1.0f - F0) * pow(clamp(1.0f - VdotH, 0.0f, 1.0f), 5.0f);
}

// Smith Joint 几何遮挡函数 (G项)
// 分子 : 2 * N·L * N·V
// (N·L) * sqrt(alpha² + (1-alpha²) * (N·V)²)  +
// (N·V) * sqrt(alpha² + (1-alpha²) * (N·L)²)
float G_SmithJointGGX_Custom(float3 N, float3 L, float3 V, float alpha)
{
    float NdotV = dot(N, V); //?要不要sacturate
    float NdotL =  dot(N, L);
    float numerator = 2.0f * NdotL * NdotV;
    float alpha2 = alpha * alpha;
    float denominator1 = NdotL * sqrt(alpha2 + (1.0f - alpha2) * NdotV * NdotV);
    float denominator2 = NdotV * sqrt(alpha2 + (1.0f - alpha2) * NdotL * NdotL);
    return numerator / max(denominator1 + denominator2, 0.00001f);
}

float G_SmithJointGGX_Custom(float NdotL, float NdotV, float alpha)
{
    float numerator = 2.0f * NdotL * NdotV;
    float alpha2 = alpha * alpha;
    float denominator1 = NdotL * sqrt(alpha2 + (1.0f - alpha2) * NdotV * NdotV);
    float denominator2 = NdotV * sqrt(alpha2 + (1.0f - alpha2) * NdotL * NdotL);
    return numerator / max(denominator1 + denominator2, 0.00001f);
}

// GGX 法线分布函数 (D项)
// 分子 : alpha ²
// 分母 : PI * ((N · H) ² * (alpha ² - 1) + 1)  ²
float D_GGX_Custom(float3 N, float3 H, float alpha)
{
    float alpha2 = alpha * alpha;
    float NdotH = dot(N, H);
    float denominator = PI * pow(NdotH * NdotH * (alpha2 - 1.0f) + 1.0f, 2.0f); // 分母
    return alpha2 / max(denominator, 0.0000001f); // 防止除以 0
}

float D_GGX_Custom(float NdotH, float alpha)
{
    float alpha2 = alpha * alpha;
    float denominator = PI * pow(NdotH * NdotH * (alpha2 - 1.0f) + 1.0f, 2.0f); // 分母
    return alpha2 / max(denominator, 0.0000001f); // 防止除以 0
}

// ============================================================================
// IBL 间接高光 (Image-Based Lighting)
//   从 unity_SpecCube0 (场景默认反射立方体贴图, 通常由 skybox 烘出) 采样,
//   用 roughness 决定 mip level (越粗糙采样越模糊的 mip),
//   用 split-sum Fresnel 让掠射角边缘发光.
//
// 参数:
//   N            世界空间法线 (已归一化)
//   V            世界空间视线方向 (已归一化)
//   NdotV        saturate(dot(N, V))
//   F0           基础反射率 (dielectric=0.04, metallic=albedo)
//   roughness    perceptualRoughness [0, 1] (材质滑块值)
//
// 返回:
//   环境反射的高光贡献, 直接加到 specular_radiance 上即可
// ============================================================================
float3 IBL_SpecularCustom(float3 N, float3 V, float NdotV, float3 F0, float roughness)
{
    // 1. 反射方向 + mip level (UE4 mobile 近似公式)
    float3 R = reflect(-V, N);
    float mip = roughness * (1.7 - 0.7 * roughness) * 6.0;

    // 2. 采样立方体贴图并 HDR 解码
    float4 env_raw = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, R, mip);
    float3 env_color = DecodeHDREnvironment(env_raw, unity_SpecCube0_HDR);

    // 3. Split-sum Fresnel: 用 NdotV, lerp 到 grazing term 让边缘不失能
    //    掠射角 (NdotV → 0) → pow(1-NdotV, 4) → 1 → F 接近 grazing → 边缘发亮
    float smoothness_val = 1.0 - roughness;
    float reflectivity = max(max(F0.r, F0.g), F0.b);
    float3 grazing = saturate(smoothness_val + reflectivity).xxx;
    float3 F_env = lerp(F0, grazing, pow(1.0 - NdotV, 4.0));

    // 4. Surface reduction: α² = perceptualRoughness⁴, 粗糙度越大能量越分散
    float alpha2 = pow(roughness, 4.0);
    float surfaceReduction = 1.0 / (alpha2 + 1.0);

    return env_color * F_env * surfaceReduction;
}