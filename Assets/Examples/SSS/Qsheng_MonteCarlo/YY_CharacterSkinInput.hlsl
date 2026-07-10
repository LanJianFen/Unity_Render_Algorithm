
#ifndef YY_CHARACTER_SKIN_INPUT
#define YY_CHARACTER_SKIN_INPUT

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

int _SKinType;

float _NormalStrength;
float _WorldScale;
float _ShadowPower;
float _ShadowMultiply;
float _DarkRimPower;
float _DarkRimMultiply;

float _Thickness;
float3 _SkinColor;
float3 _ShadowColor;
float3 _DarkRimColor;
float3 _SpecularColor;
float _SpecularPower;
float _SpecularRange;
float _SpecularStrength;
float3 _SpecularColor1;
float _SpecularPower1;
float _SpecularStrength1;
float _SpecularPower2;
float _DetailTilling;
float _DetailStrength;
float _SHADOW_ON;

float _LightIntensity;
float3 _LightColor;
float3 _LightDirection;

//补光
float3 _AddLightDirection;
float4 _AddLightColor;
float _AddLightStrength;

//阴影
float _CustomShadowBias;
float4 _CustomShadowColor;
float4 _CustomShadowOffset;

//颜色修正
float _Saturation;
float _Contrast;

//捏脸
float2 _FaceMaskCenter;
float _FaceMaskIndexG;
float _FaceMaskIndexB;
float4 _FaceMaskColor;
float _FaceMaskIntensity;
float _FaceMaskWaveValue;
float4 _FaceMaskWaveST;
float4 _FaceMaskWaveColor;

float4 _TransmissionTintAndFresnel0;
float4 _ShapeParamsAndMaxScatterDists;
float4 _SkinSSS_TexelSize;
float _MainLightMultiplier;
float _FlipVertically;

float _GlobalTransparent;

//妆容
float4 _EyeShadowColor;
float4 _EyeShadowTillingAndOffset;

float4 _EyeLinerColor;
float4 _EyeLinerTillingAndOffset;

float4 _EyebrowsColor;
float4 _EyebrowsTillingAndOffset;

float4 _BlushColor;
float4 _BlushTillingAndOffset;

float4 _LipstickColor;
float4 _LipstickTillingAndOffset;
float _LipstickSpecularStrength;
float _LipstickSpecularWeight;


float3 normalWS;
float ao, smoothness;

float4x4 _CustomMatVPFace;
float _A;

struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    float2 uv2 : TEXCOORD1;
    float2 staticLightmapUV  : TEXCOORD2;
    float2 uv4 : TEXCOORD3;
};

struct Varings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 1);
    float3 positionWS : TEXCOORD2;
    float3 normalWS : TEXCOORD3;
    float4 tangentWS : TEXCOORD4;
    float3 bitangentWS : TEXCOORD5;
    float4 shadowCoord : TEXCOORD6;
    float4 positionSS : TEXCOORD7;
    float3 viewDirWS : TEXCOORD8;
    float2 uv4 : TEXCOORD9;
    float4 shadowPosFace : TEXCOORD10;
    float3 lightDirecton : TEXCOORD11;
    float2 uv2 : TEXCOORD12;
    float3 addLightDirecton : TEXCOORD13;
};

SAMPLER(SamplerState_Linear_Repeat);
SAMPLER(SamplerState_Linear_Clamp);

TEXTURE2D(_AlbedoMap);
SAMPLER(sampler_AlbedoMap);

// TEXTURE2D(_MixMap);
// SAMPLER(sampler_MixMap);
// === MODIFIED: 将 _MixMap 拆成四张独立贴图 ===
TEXTURE2D(_MetallicMap);
TEXTURE2D(_AOMap);
TEXTURE2D(_SmoothnessMap);
TEXTURE2D(_ThicknessMap);
// === END MODIFIED ===

TEXTURE2D(_NormalMap);
SAMPLER(sampler_NormalMap);

TEXTURE2D(_SkinSSS);
SAMPLER(sampler_SkinSSS);

TEXTURE2D(_SkinSSSCustom);
SAMPLER(sampler_SkinSSSCustom);

TEXTURE2D(_SSSMask);


TEXTURE2D(_SkinDiffuse);
SAMPLER(sampler_SkinDiffuse);

sampler2D _DetailNormal;
// SAMPLER(sampler_DetailNormal);

//妆容
TEXTURE2D(_EyeShadowMap);

TEXTURE2D(_EyeLinerMap);

sampler2D _EyebrowsMap;
// TEXTURE2D(_EyebrowsMap);

TEXTURE2D(_BlushMap);

TEXTURE2D(_LipstickMap);


float WrappedDiffuseLighting(float NdotL, float w)
{
    // w = TRANSMISSION_WRAP_LIGHT;

    return saturate((NdotL + w) / ((1.0 + w) * (1.0 + w)));
}

float3 Unity_RotateAboutAxisRadians(float3 In, float3 Axis, float Rotation)
{
    float s = sin(Rotation);
    float c = cos(Rotation);
    float one_minus_c = 1.0 - c;

    Axis = normalize(Axis);
    float3x3 rot_mat = 
    {   one_minus_c * Axis.x * Axis.x + c, one_minus_c * Axis.x * Axis.y - Axis.z * s, one_minus_c * Axis.z * Axis.x + Axis.y * s,
        one_minus_c * Axis.x * Axis.y + Axis.z * s, one_minus_c * Axis.y * Axis.y + c, one_minus_c * Axis.y * Axis.z - Axis.x * s,
        one_minus_c * Axis.z * Axis.x - Axis.y * s, one_minus_c * Axis.y * Axis.z + Axis.x * s, one_minus_c * Axis.z * Axis.z + c
    };
    return normalize(mul(rot_mat,  In));
}

inline half3 FresnelTerm (half3 F0, half cosA) //菲涅尔
{
    half t = pow(1.0 - cosA, 5);
    return F0 + (1.0 - F0) * t;
}


float3 ComputeSkinDiffuse(float3 f0, float lh, float nl, float nv, float3 lightColor, float shadow, float3 albedo, float3 transmittance, float thickness, float4 shapeParamsAndMaxScatterDists, Light lightData, bool isPunctualLight)
{
    float3 fTerm = FresnelTerm(f0, lh);
    float3 kS = fTerm;
    float3 kD = 1.0 - kS;
    nl = (nl + 0.8)/(1 + 0.8);//smoothstep(-1, 0.5, nl);
    float3 diffR = kD * nl;
    float3 diffT = WrappedDiffuseLighting(-nl, 1);
    if(isPunctualLight)
    {
        float thicknessInUnits = -nl;
        float thicknessInMillimeters = thicknessInUnits * 1000 * _WorldScale;
        float3 S = shapeParamsAndMaxScatterDists.rgb;
        float dt = max(0, thicknessInMillimeters - thickness);
        float3 exp_13 = exp2(((LOG2_E * (-1.0 / 3.0)) * dt) * S);
        transmittance = transmittance * exp_13;
    }
    float3 value = 1 - saturate(pow(abs(diffR + diffT * transmittance), 3));
    float3 result = lerp(albedo, _ShadowColor * albedo, smoothstep(0, 0.7, (pow(abs(value * _ShadowMultiply), _ShadowPower))));
    result = lerp(result * _CustomShadowColor.rgb, result, shadow);
    result *= lightColor;
    return result;// * lightData.distanceAttenuation * max(0.9, lightData.shadowAttenuation);
}

float3 ComputeTransmittanceDisney(float3 S, float3 volumeAlbedo, float thickness)
{
    float3 exp_13 = exp2(((LOG2_E * (-1.0 / 3.0)) * thickness) * S);
    return volumeAlbedo * (exp_13 * (exp_13 * exp_13 + 3));
}

float2 TillingAndOffset(float2 uv, float2 tilling, float2 offset)
{
    uv = uv * tilling + offset;
    return uv;
}

float4 SymmetryRGBAValue(Texture2D tex, sampler sampler_texture, float2 uv, float4 tillingAndOffset)
{
    float2 tilling = tillingAndOffset.xy;
    float2 offset = tillingAndOffset.zw;
    float4 value = SAMPLE_TEXTURE2D(tex, sampler_texture, TillingAndOffset(uv, tilling, offset));
    value += SAMPLE_TEXTURE2D(tex, sampler_texture, TillingAndOffset(uv, float2(-tilling.x, tilling.y), float2(offset.x + tilling.x, offset.y)));
    return value;
}

//非左右对称单色
float AsymmetryAlphaValue(Texture2D tex, sampler sampler_texture, float2 uv, float4 tillingAndOffset)
{
    float2 tilling = tillingAndOffset.xy;
    float2 offset = tillingAndOffset.zw;
    float value = SAMPLE_TEXTURE2D(tex, sampler_texture, TillingAndOffset(uv, tilling, offset)).a;
    return value;
}

half3 GlobalIllumination(half3 bakedGI, half occlusion, half3 normalWS, half3 viewDirectionWS, half smoothness, half3 diffuse, half3 specular)
{
    half perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);

    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = saturate(dot(normalWS, viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    half3 indirectDiffuse = bakedGI + 0.2;//提亮肤色
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, perceptualRoughness, half(1.0));

    half3 color = indirectDiffuse * diffuse;
    color += indirectSpecular * specular;
    return color * occlusion;
}


float SymmetryAlphaValueBias(sampler2D tex, float2 uv, float4 tillingAndOffset)
{
    float2 tilling = tillingAndOffset.xy;
    float2 offset = tillingAndOffset.zw;
    float2 uvValue = TillingAndOffset(uv, tilling, offset);
    float value = tex2Dbias(tex, float4(uvValue, 0.0, -0.4)).a;
    uvValue = TillingAndOffset(uv, float2(-tilling.x, tilling.y), float2(offset.x + tilling.x, offset.y));
    value += tex2Dbias(tex, float4(uvValue, 0.0, -0.4)).a;
    return value;
}

//左右对称RGB，胡子边缘处理
float4 SymmetryRGBAValueBeard(sampler2D tex, float2 uv, float4 tillingAndOffset)
{
    float2 tilling = tillingAndOffset.xy;
    float2 offset = tillingAndOffset.zw;
    float2 uv1 = TillingAndOffset(uv, tilling, offset);
    float4 value = tex2Dbias(tex, float4(uv1, 0.0, -0.4));
    value = uv1.x > 1 ? 0 : value;
    uv1 = TillingAndOffset(uv, float2(-tilling.x, tilling.y), float2(offset.x + tilling.x, offset.y));
    float4 value1 = tex2Dbias(tex, float4(uv1, 0.0, -0.4));
    value1 = uv1.x > 1 ? 0 : value1;
    return value + value1;
}

//左右对称单色
float SymmetryAlphaValue(Texture2D tex, sampler sampler_texture, float2 uv, float4 tillingAndOffset)
{
    float2 tilling = tillingAndOffset.xy;
    float2 offset = tillingAndOffset.zw;
    float value = SAMPLE_TEXTURE2D(tex, sampler_texture, TillingAndOffset(uv, tilling, offset)).a;
    value += SAMPLE_TEXTURE2D(tex, sampler_texture, TillingAndOffset(uv, float2(-tilling.x, tilling.y), float2(offset.x + tilling.x, offset.y))).a;
    return value;
}

//非左右对称RGB
float4 AsymmetryRGBAValue(Texture2D tex, sampler sampler_texture, float2 uv, float4 tillingAndOffset)
{
    float2 tilling = tillingAndOffset.xy;
    float2 offset = tillingAndOffset.zw;
    uv = (uv + offset - float2(0.5, 0.5)) * tilling + float2(0.5, 0.5);
    float4 value = SAMPLE_TEXTURE2D(tex, sampler_texture, uv);
    return value;
}


half3 DirectBDRE_Duallobespecular(half3 specular, half smoothness, half3 normalWS, half3 lightDirectionWS, half3 viewDirectionWS, half mask, half lobeWeight, half lipSpecular)
{
    smoothness = lerp(smoothness, _LipstickSpecularStrength, lipSpecular);

    half perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
    half roughness = max(PerceptualRoughnessToRoughness(perceptualRoughness), HALF_MIN);
    half roughness2 = roughness * roughness;
    half roughness2MinusOne = roughness2 - 1;
    half normalizationTerm = roughness * 4.0 + 2.0;


    float3 halfDir = SafeNormalize(float3(lightDirectionWS)+ float3(viewDirectionWS));
    float NoH =saturate(dot(normalWS, halfDir));
    half LoH = saturate(dot(lightDirectionWS, halfDir));
    float d = NoH * NoH * roughness2MinusOne + 1.00001f;
    half nv = saturate(dot(normalWS, lightDirectionWS));
    half LoH2 = LoH * LoH;
    float sAO =saturate(-0.3f + nv * nv);
    sAO = lerp(pow(0.75, 8.00f), 1.0f, sAO);
    half SpecularOcclusion = sAO;
    half specularTermGGX = roughness2 / ((d * d) * max(0.1h, LoH2)* normalizationTerm);
    half specularTermBeckMann = (2.0 * (roughness2)/((d * d) * max(0.1h, LoH2) * normalizationTerm)) * max(0.01, lobeWeight * mask);
    half specularTerm = (specularTermGGX/2 + specularTermBeckMann) * SpecularOcclusion;

    specularTerm = pow(specularTerm, _SpecularPower1) * _SpecularStrength;

    half3 color = min(4, specularTerm) * specular;
    return color;
}


Varings vertSkin(Attributes IN)
{
    Varings OUT = (Varings)0;
    VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);

    VertexNormalInputs normalInputs = GetVertexNormalInputs(IN.normalOS.xyz);
    OUT.positionCS = positionInputs.positionCS;
    OUT.positionWS = positionInputs.positionWS;
    OUT.positionSS = ComputeScreenPos(OUT.positionCS);
    OUT.viewDirWS = normalize(GetCameraPositionWS().xyz - TransformObjectToWorld(IN.positionOS.xyz));//GetCameraPositionWS() - positionInputs.positionWS;
    OUT.normalWS = normalInputs.normalWS;
    OUT.tangentWS.xyz = normalInputs.tangentWS;
    OUT.tangentWS.w = IN.tangentOS.w * GetOddNegativeScale();
    OUT.bitangentWS = normalInputs.bitangentWS;
    OUT.uv = IN.uv;
    OUT.uv4 = IN.uv4;
    OUT.uv2 = IN.uv2;

    //灯光角度
    float3 lightDirecton = float3(OUT.viewDirWS.x, _LightDirection.x, OUT.viewDirWS.z);
    lightDirecton = Unity_RotateAboutAxisRadians(lightDirecton, float3(0, 1, 0), _LightDirection.y);
    OUT.lightDirecton = lightDirecton;
    
    //补光角度
    float radians = atan2(OUT.viewDirWS.x, OUT.viewDirWS.z);
    float3 addLightDirection = Unity_RotateAboutAxisRadians(_AddLightDirection, float3(0, 1, 0), radians);
    OUT.addLightDirecton = addLightDirection;

    float4x4 matrixMVP = mul(_CustomMatVPFace, unity_ObjectToWorld);
    OUT.shadowPosFace = mul(matrixMVP, float4(IN.positionOS, 1));

    return OUT;
}
#endif
