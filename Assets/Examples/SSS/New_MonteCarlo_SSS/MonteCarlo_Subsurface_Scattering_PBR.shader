Shader "Custom/SSS/MonteCarlo_SSS_PBR"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _AlbedoMap ("Albedo Map", 2D) = "white" {}
        _AlbedoColor ("Albedo Color", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Base Normal)]
        [Space(5)]
        _NormalMap("Normal Map", 2D) = "bump"{}         //normal map 默认必须是 "bump" (Unity 内置平面法线),
        [Header(Surface Detail)]
        [Space(5)]
        _DetailMap("Detail Map", 2D) = "bump"{}
       // _Metallic ("Metallic", Range(0, 1)) = 0.0
        _Roughness ("Roughness", Range(0, 1)) = 0.5
        _Specular("Specular", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }
        
        Pass
        {
            Tags
            {
                "LightMode" = "Subsurface Scattering Direct Diffuse"
            }

            Stencil
            {
                Ref 1 // 我们的暗号是数字 1
                Comp Always // 永远通过
                Pass Replace // 画到哪里，就把哪里的模板值替换成 1
            }

            HLSLPROGRAM
            #pragma vertex vertShader
            #pragma fragment fragShader
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include  "../../../Common/Shaders/Math.hlsl"
            #include  "../../../Common/Shaders/Custom_BRDF.hlsl"
            
            struct Attributes
            {
                float4 position_os : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_os : NORMAL;
                float4 tangent_os : TANGENT;
            };
            
            struct Varings
            {
                float4 position_cs : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 position_ws : TEXCOORD1;
                float3 normal_ws : TEXCOORD2;
                float4 tangent_ws : TEXCOORD3;
            };


            TEXTURE2D(_AlbedoMap);
            TEXTURE2D(_NormalMap);
            TEXTURE2D(_DetailMap);
            
            SAMPLER(sampler_AlbedoMap);
            SAMPLER(sampler_NormalMap);
            SAMPLER(sampler_DetailMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _AlbedoColor;
                float _Specular;
            CBUFFER_END
            
            Varings vertShader(Attributes i)
            {
                Varings o = (Varings)0;
                o.uv = i.uv;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_ws = TransformObjectToWorld(i.position_os.xyz);
                o.normal_ws = TransformObjectToWorldNormal(i.normal_os, true);
                o.tangent_ws = float4(TransformObjectToWorldDir(i.tangent_os.xyz), i.tangent_os.w);
                return o;
            }
            
            half4 fragShader(Varings i) : SV_Target
            {
                float4 albedo = SAMPLE_TEXTURE2D(_AlbedoMap, sampler_AlbedoMap, i.uv) * _AlbedoColor;
                // 法线旋转叠加：旋转到在宏观法线方向，叠加更细节的法线。这个要在 宏观法线的起点 Tangent Space 才能叠加上去
                float3 normal_ts = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv));
                float3 detail_normal_ts = UnpackNormal(SAMPLE_TEXTURE2D(_DetailMap, sampler_DetailMap, i.uv));
                float3 final_normal_ts = BlendNormalRNMCustom(normal_ts, detail_normal_ts);
                
                // 构建 TBN 矩阵
                float3 bitangent_ws = cross(i.normal_ws, i.tangent_ws.xyz) * i.tangent_ws.w * GetOddNegativeScale();
                float3x3 tbn = float3x3(i.tangent_ws.xyz, bitangent_ws, i.normal_ws);
                // 把叠加 detail 法线后在最终法线 转移到 ws，这里用的是 final\_normal\_ts 右乘 tbn 的转置
                float3 final_normal_ws = normalize(mul(final_normal_ts, tbn));
                
                Light main_light = GetMainLight();
                float3 L = normalize(main_light.direction);
                
                float NdotL = saturate(dot(final_normal_ws, L));
                
                // ==== SH 环境光 (间接漫反射) ====
                float3 sh_ambient = albedo.rgb * SampleSH(final_normal_ws);
                //环境光就不扔进去了，低频送给SSS模糊没意义，最后直接叠加上去。如果要扔进去，写成 ∫ (1- FSchlick) * dot(N,wi) dwi

                // 专门给 SSS 打造的 diffuse 的加了菲涅尔入射率的 irradiance
                float3 F0 = float3(0.08, 0.08, 0.08) * _Specular;
                float3 Ft_in = 1.0f - F_Schlick_Custom(NdotL, F0);
                float3 sss_direct_diffuse_irradiance = Ft_in * albedo.rgb * main_light.color * NdotL;
                // float3 sss_diffuse_irradiance = sss_direct_diffuse_irradiance * (1.0f - _Metallic); // SSS 加金属度没意义，金属没有次表面散射

                return half4(sss_direct_diffuse_irradiance, 1.0f);
            }
            ENDHLSL
        }

        Pass
        {
            Tags
            {
                "LightMode" = "Subsurface Scattering Final Blend"
            }
            
            ZWrite Off 
            ZTest LEqual
            
            HLSLPROGRAM
            #pragma vertex vertShader
            #pragma fragment fragShader
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include  "../../../Common/Shaders/Math.hlsl"
            #include  "../../../Common/Shaders/Custom_BRDF.hlsl"
            
            struct Attributes
            {
                float4 position_os : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_os : NORMAL;
                float4 tangent_os : TANGENT;
            };
            
            struct Varings
            {
                float4 position_cs : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 position_ws : TEXCOORD1;
                float3 normal_ws : TEXCOORD2;
                float4 tangent_ws : TEXCOORD3;
            };


            TEXTURE2D(_AlbedoMap);
            TEXTURE2D(_NormalMap);
            TEXTURE2D(_DetailMap);
            
            SAMPLER(sampler_AlbedoMap);
            SAMPLER(sampler_NormalMap);
            SAMPLER(sampler_DetailMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _AlbedoColor;
                //float _Metallic;
                float _Roughness;
                float _Specular;
            CBUFFER_END

            TEXTURE2D(_SubsurfaceScatteringRT);
            SAMPLER(sampler_SubsurfaceScatteringRT);
            
            Varings vertShader(Attributes i)
            {
                Varings o = (Varings)0;
                o.uv = i.uv;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_ws = TransformObjectToWorld(i.position_os.xyz);
                o.normal_ws = TransformObjectToWorldNormal(i.normal_os, true);
                o.tangent_ws = float4(TransformObjectToWorldDir(i.tangent_os.xyz), i.tangent_os.w);
                return o;
            }


            half4 fragShader(Varings i) : SV_Target
            {
                float4 albedo = SAMPLE_TEXTURE2D(_AlbedoMap, sampler_AlbedoMap, i.uv) * _AlbedoColor;
                // 法线旋转叠加：旋转到在宏观法线方向，叠加更细节的法线。这个要在 宏观法线的起点 Tangent Space 才能叠加上去
                float3 normal_ts = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv));
                float3 detail_normal_ts = UnpackNormal(SAMPLE_TEXTURE2D(_DetailMap, sampler_DetailMap, i.uv));
                float3 final_normal_ts = BlendNormalRNMCustom(normal_ts, detail_normal_ts);
                
                // 构建 TBN 矩阵
                float3 bitangent_ws = cross(i.normal_ws, i.tangent_ws.xyz) * i.tangent_ws.w * GetOddNegativeScale();
                float3x3 tbn = float3x3(i.tangent_ws.xyz, bitangent_ws, i.normal_ws);
                // 把叠加 detail 法线后在最终法线 转移到 ws，这里用的是 final\_normal\_ts 右乘 tbn 的转置
                float3 final_normal_ws = normalize(mul(final_normal_ts, tbn));
                
                Light main_light = GetMainLight();
                float3 L = normalize(main_light.direction);
                float3 V = normalize(_WorldSpaceCameraPos - i.position_ws);
                float3 H = normalize(L + V);
                
                float NdotH = saturate(dot(final_normal_ws, H));
                float NdotV = saturate(dot(final_normal_ws, V));
                float NdotL = saturate(dot(final_normal_ws, L));
                float VdotH = saturate(dot(V, H));
                
                // Specular
                // 基础反射率 F0 (非金属为 0.04，金属为 Albedo)
                float3 F0 = float3(0.08, 0.08, 0.08) * _Specular;
                
                float3 F = F_Schlick_Custom(VdotH, F0);
                float G = G_SmithJointGGX_Custom(NdotL, NdotV, _Roughness * _Roughness);
                float D = D_GGX_Custom(NdotH, _Roughness * _Roughness);
                
                float3 ggx_BRDF = D * G * F / max(4.0f * NdotL * NdotV, 0.000001f);;
                float3 direct_specular_radiance = ggx_BRDF * main_light.color * NdotL * PI;
                float3 IBL_ambient = IBL_SpecularCustom(final_normal_ws, V, NdotV, F0, _Roughness);
                // ==== IBL 间接高光 (掠射角 → 边缘发光) ====
                float3 specular_radiance = direct_specular_radiance + IBL_ambient;
                
                // ==== SH 环境光 ====
                float3 kD = 1.0f - F;
                float3 sh_ambient = albedo.rgb * SampleSH(final_normal_ws) * kD;

                float3 Ft_out = 1.0f - F_Schlick_Custom(NdotV, F0);
                float2 ss_uv = i.position_cs.xy / _ScreenParams.xy;
                float3 sss_radiance = Ft_out * SAMPLE_TEXTURE2D(_SubsurfaceScatteringRT, sampler_SubsurfaceScatteringRT, ss_uv);

                // 测试一下 普通 PBR 有没有错误
                //float3 kD = 1.0f - F;
                //float3 direct_diffuse_radiance = albedo.rgb * main_light.color * NdotL; // 普通的 PBR
                //float3 diffuse_radiance = (direct_diffuse_radiance + sh_ambient) * kD;

                return half4(specular_radiance  + sh_ambient + sss_radiance, 1.0f);
            }
            ENDHLSL

        }
    }
}