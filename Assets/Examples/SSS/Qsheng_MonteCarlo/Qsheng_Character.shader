
Shader "QSheng/CharacterSkin"
{
    Properties
    {
        [HideInInspector]_BaseMap ("Base Map", 2D) = "white" { }
        _AlbedoMap ("Albedo Map", 2D) = "white" { }
        // _MixMap ("Mix Map", 2D) = "white" { }
        // === MODIFIED: 将 _MixMap 拆成四张独立贴图 ===
        _MetallicMap ("Metallic Map (R)", 2D) = "black" { }
        _AOMap ("AO Map (G)", 2D) = "white" { }
        _SmoothnessMap ("Smoothness Map (B)", 2D) = "white" { }
        _ThicknessMap ("Thickness Map (A)", 2D) = "white" { }
        // === END MODIFIED ===
        _NormalMap ("Normal Map", 2D) = "white" { }
        _SSSMask ("SSS Mask", 2D) = "white" { }

        [Toggle(_SUBSURFACE_SCATTERING_ON)] _SUBSURFACE_SCATTERING ("_SUBSURFACE_SCATTERING?", Float) = 0
        _SkinSSSCustom ("Skin SSS Custom", 2D) = "white" { }
        _SkinColor ("Skin Color", Color) = (1, 1, 1, 1)
        _ShadowColor ("Shadow Color", Color) = (1, 1, 1, 1)
        _DarkRimColor ("Shadow Color", Color) = (1, 1, 1, 1)

        _NormalStrength ("Normal Strength", float) = 1
        _Thickness ("Thickness", float) = 1
        _ShadowPower ("Shadow Range Min", Range(-2, 2)) = 0
        _ShadowMultiply ("Shadow Range Max", Range(-2, 2)) = 1
        _ShadowOpen ("Shadow Open", Int) = 0

        _DarkRimPower ("Dark Rim Max", Range(0, 1)) = 1
        _DarkRimMultiply ("Dark Rim Max", Range(0, 1)) = 1

        _SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        _SpecularPower ("Specular Range Min", float) = 0
        [HideInInspector]_SpecularRange ("Specular Range Max", float) = 1
        _SpecularStrength ("Specular Strength", float) = 1
        [HideInInspector]_SpecularColor1 ("Specular Color", Color) = (1, 1, 1, 1)
        _SpecularPower1 ("Specular Power", float) = 1
        [HideInInspector]_SpecularStrength1 ("Specular Strength", float) = 0
        [HideInInspector]_SpecularPower2 ("Specular Power", float) = 1

        _DetailNormal ("Detail Normal", 2D) = "black" { }
        _DetailTilling ("Detail Tilling", float) = 0
        _DetailStrength ("Detail Strength", float) = 0

        _LightIntensity ("Main Light Intensity", float) = 1.35
        _LightColor ("Main Light Color", Color) = (1, 1, 1, 1)
        _LightDirection ("Main Light Intensity", Vector) = (0.7, -0.5, 0, 0)

        //补光
        _AddLightDirection ("Add Light Direction", vector) = (0, -1, 0)
        _AddLightColor ("Add Light Color", color) = (0, 0, 0, 0)
        _AddLightStrength ("Add Light Intensity", float) = 0

        //阴影
        _CustomShadowBias ("Shadow Bias", float) = 0.0001
        _CustomShadowColor ("Shadow Bias", Color) = (1, 1, 1, 1)
        _CustomShadowOffset ("Shadow Offset", Vector) = (1, 0, 0, 0)

        //[Toggle] _SHADOW_ON ("_SHADOW_ON", Float) = 0


        //妆容
        [Toggle(_MAKEUP_ON)] _MAKEUP ("_MAKEUP", Float) = 1
        _EyeShadowMap ("眼影贴图", 2D) = "black" { }
        _EyeShadowColor ("眼影颜色", Color) = (0, 0, 0, 0)
        _EyeShadowTillingAndOffset ("眼影UV", Vector) = (1, 1, 0, 0)

        _EyeLinerMap ("眼线贴图", 2D) = "black" { }
        _EyeLinerColor ("眼线颜色", Color) = (0, 0, 0, 0)
        _EyeLinerTillingAndOffset ("眼线UV", Vector) = (1, 1, 0, 0)

        _EyebrowsMap ("眉毛贴图", 2D) = "black" { }
        _EyebrowsColor ("眉毛颜色", Color) = (0, 0, 0, 0)
        _EyebrowsTillingAndOffset ("眉毛UV", Vector) = (1, 1, 0, 0)

        _BlushMap ("腮红贴图", 2D) = "black" { }
        _BlushColor ("腮红颜色", Color) = (0, 0, 0, 0)
        _BlushTillingAndOffset ("腮红UV", Vector) = (1, 1, 0, 0)

        _LipstickMap ("嘴唇贴图", 2D) = "black" { }
        _LipstickColor ("嘴唇颜色", Color) = (0, 0, 0, 0)
        _LipstickTillingAndOffset ("嘴唇UV", Vector) = (1, 1, 0, 0)
        _LipstickSpecularStrength ("嘴唇高光强度", float) = 1
        _LipstickSpecularWeight ("嘴唇高光范围", float) = 0.35
    }

    HLSLINCLUDE
    #define CHARACTER_SKIN
    ENDHLSL
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            Name "SkinDiffuse"
            Tags { "LightMode" = "SkinDiffuse" }

            ZWrite On
            ZTest Less

            Stencil
            {
                Ref 3
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #include "YY_CharacterSkinInput.hlsl"

            #pragma vertex vertSkin
            #pragma fragment fragdif
            
            

            
            float4 fragdif (Varings input) : SV_Target
            {
                //SP
                _MainLightMultiplier = 0.9;
                float3 lightDir, lightColor;
                //灯光信息
                Light mainLight = GetMainLight(input.shadowCoord);

                // === ORIGINAL: 使用材质参数模拟的"跟随相机"伪光照 ===
                // lightDir = input.lightDirecton;
                // lightColor = _LightIntensity * _MainLightMultiplier * _LightColor;
                // === MODIFIED: 换成场景真正的 Directional Light ===
                lightDir = mainLight.direction;
                lightColor = mainLight.color * _MainLightMultiplier;
                // === END MODIFIED ===

                float4 posNDCFace = input.shadowPosFace / input.shadowPosFace.w;
                posNDCFace.y = -posNDCFace.y;
                float2 shadowUVFace = posNDCFace.xy * 0.5 + 0.5;
                float shadowDepthFace = posNDCFace.z;
                
                float3 albedo = SAMPLE_TEXTURE2D(_AlbedoMap, sampler_AlbedoMap, input.uv).rgb * 1.1;
                // float4 mixValue = SAMPLE_TEXTURE2D(_MixMap, SamplerState_Linear_Clamp, input.uv);
                // float metallic = mixValue.r;
                // ao = mixValue.g;
                // smoothness = mixValue.b;
                // float thickness = mixValue.a;
                // === MODIFIED: 从四张独立贴图采样，分别取 R 通道 ===
                float metallic  = SAMPLE_TEXTURE2D(_MetallicMap,   SamplerState_Linear_Clamp, input.uv).r;
                ao              = SAMPLE_TEXTURE2D(_AOMap,         SamplerState_Linear_Clamp, input.uv).r;
                smoothness      = SAMPLE_TEXTURE2D(_SmoothnessMap, SamplerState_Linear_Clamp, input.uv).r;
                float thickness = SAMPLE_TEXTURE2D(_ThicknessMap,  SamplerState_Linear_Clamp, input.uv).r;
                // === END MODIFIED ===

                //法线
                float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv));
                normalTS = float3(normalTS.xy * _NormalStrength, lerp(1, normalTS.z, saturate(_NormalStrength)));
                float3x3 tangentToWorld = float3x3(normalize(input.tangentWS.xyz), normalize(input.bitangentWS), normalize(input.normalWS));
                normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = normalize(normalWS);
                
                float normalMask = SAMPLE_TEXTURE2D(_SSSMask, SamplerState_Linear_Clamp, input.uv).r;
                normalWS = lerp(input.normalWS, normalWS, normalMask);

                //阴影
                float shadow = lerp(1, mainLight.shadowAttenuation, step(0.5, _SHADOW_ON));

                //补光
                float nl = dot(normalWS, input.addLightDirecton);
                albedo = albedo + _AddLightColor * max(0, _AddLightStrength) * saturate(nl);
                
                nl = dot(normalWS, lightDir);
                
                //眼影
                float4 eyeShadowColor = SymmetryRGBAValue(_EyeShadowMap, SamplerState_Linear_Clamp, input.uv, _EyeShadowTillingAndOffset);
                albedo = lerp(albedo, eyeShadowColor.rgb * _EyeShadowColor.rgb, eyeShadowColor.a * _EyeShadowColor.a);

                //腮红
                float4 blushColor = SymmetryRGBAValue(_BlushMap, SamplerState_Linear_Clamp, input.uv, _BlushTillingAndOffset);
                albedo = albedo * lerp(1, blushColor.rgb * _BlushColor.rgb, blushColor.a * _BlushColor.a * max(0.2, saturate(nl + 1)));

                //唇妆
                float lipColor = AsymmetryAlphaValue(_LipstickMap, SamplerState_Linear_Clamp, input.uv, _LipstickTillingAndOffset);
                albedo = albedo * lerp(1, _LipstickColor.rgb, lipColor * _LipstickColor.a);

                thickness = _Thickness * thickness;

                float f0 = lerp(_TransmissionTintAndFresnel0.a, max(albedo.r, max(albedo.g, albedo.b)), metallic);
                float3 halfDir = normalize(input.viewDirWS + lightDir);
                float lh = saturate(dot(lightDir, halfDir));
                float3 transmittance = ComputeTransmittanceDisney(_ShapeParamsAndMaxScatterDists.rgb, _TransmissionTintAndFresnel0.rgb, thickness);
                //dark rim
                float nv = saturate(dot(normalWS, input.viewDirWS));

                //主方向光
                float3 directLighting = ComputeSkinDiffuse(f0, lh, nl, nv, lightColor, shadow, albedo, transmittance, thickness, _ShapeParamsAndMaxScatterDists, mainLight, false);

                float3 result = directLighting * ao;

                result.b = max(result.b, HALF_MIN);
                
                return float4(result * _SkinColor * 0.7, shadow);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Universal Forward Front"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            ZTest LEqual

            Offset [_OffsetFactor], [_OffsetUnits]

            Stencil
            {
                Ref 3
                Comp Always
                Pass Replace
            }
            HLSLPROGRAM
            #pragma vertex vertSkin
            #pragma fragment fragsas

            #include "YY_CharacterSkinInput.hlsl"
            #pragma multi_compile_fragment _ _SUBSURFACE_SCATTERING_ON
            
            float4 fragsas(Varings input) : SV_Target
            {
                float fogFactor;
                fogFactor = ComputeFogFactor(input.positionCS.z * input.positionCS.w);

                Light mainLight = GetMainLight();
                // === ORIGINAL: 使用材质参数模拟的"跟随相机"伪光照 ===
                // float3 lightDir = input.lightDirecton;
                // float3 lightColor = _LightIntensity * _MainLightMultiplier * _LightColor;
                // === MODIFIED: 换成场景真正的 Directional Light ===
                float3 lightDir = mainLight.direction;
                float3 lightColor = mainLight.color * _MainLightMultiplier;
                // === END MODIFIED ===

                
                float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv));
                normalTS = float3(normalTS.xy * _NormalStrength, lerp(1, normalTS.z, saturate(_NormalStrength)));

                float3 detailNormal = UnpackNormal(tex2Dbias(_DetailNormal, float4(input.uv * _DetailTilling, 0.0, -1.5)));
                detailNormal = float3(detailNormal.xy * _DetailStrength, lerp(1, detailNormal.z, saturate(_DetailStrength)));
                detailNormal = normalize(detailNormal);
                
                float3x3 nBasis = float3x3(float3(normalTS.z, normalTS.y, -normalTS.x), float3(normalTS.x, normalTS.z, -normalTS.y), float3(normalTS.x, normalTS.y, normalTS.z));
                normalTS = normalize(detailNormal.x * nBasis[0] + detailNormal * nBasis[1] + detailNormal.z * nBasis[2]);
                
                float3x3 tangentToWorld = float3x3(normalize(input.tangentWS.xyz), normalize(input.bitangentWS), normalize(input.normalWS));
                normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = normalize(normalWS);
                
                
                // float4 mixValue = SAMPLE_TEXTURE2D(_MixMap, SamplerState_Linear_Clamp, input.uv);
                // float metallic = mixValue.r;
                // ao = mixValue.g;
                // smoothness = mixValue.b;
                // float thickness = mixValue.a;
                // === MODIFIED: 从四张独立贴图采样，分别取 R 通道 ===
                float metallic  = SAMPLE_TEXTURE2D(_MetallicMap,   SamplerState_Linear_Clamp, input.uv).r;
                ao              = SAMPLE_TEXTURE2D(_AOMap,         SamplerState_Linear_Clamp, input.uv).r;
                smoothness      = SAMPLE_TEXTURE2D(_SmoothnessMap, SamplerState_Linear_Clamp, input.uv).r;
                float thickness = SAMPLE_TEXTURE2D(_ThicknessMap,  SamplerState_Linear_Clamp, input.uv).r;
                // === END MODIFIED ===

                float nv = saturate(dot(normalWS, input.viewDirWS));
                float nl = saturate(dot(input.normalWS, lightDir));
                float3 shadowColor = lerp(_ShadowColor, 1, nl);
                float3 albedo = 0;
                float3 halfDir = normalize(input.viewDirWS + lightDir);
                float3 result = 0;
                
                float2 sssUV = input.positionCS.xy / _ScreenParams.xy;
                float4 diffuseAndShadow = SAMPLE_TEXTURE2D(_SkinDiffuse, sampler_SkinDiffuse, sssUV);
                float shadow = diffuseAndShadow.a;
                albedo = diffuseAndShadow;
                #if defined(_SUBSURFACE_SCATTERING_ON)
                    float sssMask = SAMPLE_TEXTURE2D(_SSSMask, SamplerState_Linear_Clamp, input.uv).a;
                    float3 sss = SAMPLE_TEXTURE2D(_SkinSSS, sampler_SkinSSS, sssUV).rgb;
                    result = lerp(diffuseAndShadow.rgb, sss, saturate(sssMask));
                #else
                    float sssMask = SAMPLE_TEXTURE2D(_SSSMask, SamplerState_Linear_Clamp, input.uv).a;
                    float3 sss = SAMPLE_TEXTURE2D(_SkinSSSCustom, sampler_SkinSSSCustom, float2((nl * 0.5 + 0.5) * shadow, thickness)).rgb;
                    result = float4(diffuseAndShadow.rgb * sss, 1);
                    //   return float4(result, 1);
                #endif
                
                result = lerp(result * _CustomShadowColor.rgb, result, 1);

                
                //眉毛
                float eyeBrowsValue = SymmetryAlphaValueBias(_EyebrowsMap, input.uv, _EyebrowsTillingAndOffset);
                result = lerp(result, _EyebrowsColor.rgb * shadowColor, eyeBrowsValue * _EyebrowsColor.a);
                float specValue = 1 - eyeBrowsValue;
                
                //腮红
                float4 blushColor = SymmetryRGBAValue(_BlushMap, SamplerState_Linear_Clamp, input.uv, _BlushTillingAndOffset);
                result = result * lerp(1, blushColor.rgb * _BlushColor.rgb, blushColor.a * _BlushColor.a * max(0.2, saturate(nl + 1)));

                //唇妆
                float lipColor = AsymmetryAlphaValue(_LipstickMap, SamplerState_Linear_Clamp, input.uv, _LipstickTillingAndOffset);
                result = result * lerp(1, _LipstickColor.rgb, lipColor * _LipstickColor.a);
                
                //darkrim
                result = lerp(result, _DarkRimColor * result, smoothstep(0, 0.5, (1 - pow(nv, _DarkRimPower)) * _DarkRimMultiply));

              
                //高光
                float3 specNormal = normalWS;
                float3 spec = DirectBDRE_Duallobespecular(_SpecularColor, smoothness, normalWS, lightDir, input.viewDirWS, 1, _SpecularPower, lipColor);

                //GI
                float3 giColor = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, normalWS);
                MixRealtimeAndBakedGI(mainLight, normalWS, giColor);
                giColor = GlobalIllumination(giColor, ao, normalWS, input.viewDirWS, smoothness, result, 0);

                result = result + giColor;
                spec = saturate(spec * saturate(specValue * shadow));
                result = (result + spec * ao);
                return float4(result, 1);
            }
            ENDHLSL
        }
    }
}
