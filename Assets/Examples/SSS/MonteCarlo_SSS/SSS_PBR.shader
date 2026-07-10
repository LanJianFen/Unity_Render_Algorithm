Shader "Custom/SSS/SSS_PBR"
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
        _Metallic ("Metallic", Range(0, 1)) = 0.0
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
                "LightMode" = "SSS_MRT"
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
            
            // 定义 MRT 输出结构体
            struct FragmentOutput
            {
                half4 specular_radiance : SV_Target0; // 这是最终相机的画面 (Color Buffer)
                half4 sss_diffuse_irradiance : SV_Target1; // 留给 SSS 用的 Ft (xi, wi) \* Li \* ( Ni \* Wi ) 
            };
            
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
                float _Metallic;
                float _Roughness;
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


            FragmentOutput fragShader(Varings i) : SV_Target
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
                F0 = lerp(F0, albedo.rgb, _Metallic);


                float3 F = F_Schlick_Custom(VdotH, F0);
                float G = G_SmithJointGGX_Custom(NdotL, NdotV, _Roughness * _Roughness);
                float D = D_GGX_Custom(NdotH, _Roughness * _Roughness);
                
                float3 ggx_BRDF = D * G * F / max(4.0f * NdotL * NdotV, 0.000001f);;
                float3 direct_specular_radiance = ggx_BRDF * main_light.color * NdotL * PI;
                float3 IBL_ambient = IBL_SpecularCustom(final_normal_ws, V, NdotV, F0, _Roughness);
                // ==== IBL 间接高光 (掠射角 → 边缘发光) ====
                float3 specular_radiance = direct_specular_radiance + IBL_ambient;


                // Diffuse
                // 根据能量守恒，高光弹飞了 F，剩下钻进物体的光就是 (1 - F)
                float3 kD = 1.0f - F;
                // Diffuse BRDF: c/PI, 但是美术认为如果给 1.0 的光不该是 1 /PI，所以给Diffuse 和 Specular 的BRDF 都乘 PI
                // C 就是 albedo.rgb
                float3 direct_diffuse_radiance = albedo.rgb * main_light.color * NdotL; // 普通的 PBR

                // ==== SH 环境光 (间接漫反射) ====
                float3 sh_ambient = albedo.rgb * SampleSH(final_normal_ws);
                // 这里本来是乘 1 - Specular LUT = 1 - (F0 * A + B) ,在下一行简化成KD
                float3 diffuse_radiance = (direct_diffuse_radiance + sh_ambient) * kD * (1.0f - _Metallic);
                // 纯金属没有漫反射（光子进不去，直接吸收或弹飞）
                
                // 专门给 SSS 打造的 diffuse 的加了菲涅尔入射率的 irradiance
                float3 Ft_in = 1.0f - F_Schlick_Custom(NdotL, F0);
                float3 sss_direct_diffuse_irradiance = Ft_in * albedo.rgb * main_light.color * NdotL;
                float3 sss_diffuse_irradiance = sss_direct_diffuse_irradiance * (1.0f - _Metallic);
                //环境光就不扔进去了，低频送给SSS模糊没意义，最后直接叠加上去。如果要扔进去，写成 ∫ (1- FSchlick) * dot(N,wi) dwi

                FragmentOutput output;
                output.specular_radiance = half4(specular_radiance, 1.0);
                output.sss_diffuse_irradiance = half4(sss_diffuse_irradiance, 1.0);

                return output;
            }
            ENDHLSL

        }
    }
}