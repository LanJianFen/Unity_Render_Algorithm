Shader "Custom/SSS/SSS_MonteCarlo"
{
    Properties {}
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
                "LightMode" = "Subsurface Scattering MonteCarlo"
            }

            Stencil
            {
                Ref 1 // 拿着暗号 1 去对比
                Comp Equal // 只有底层值等于 1 时，才允许执行这个全屏像素！
            }

            Blend One One
            ZWrite Off
            ZTest Always // 无视遮挡，强行覆盖全屏
            Cull off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Burley_MonteCarlo_Math.hlsl"

            struct Attibutes
            {
                uint vertex_id : SV_VertexID;
                //float4 position_os : POSITION;
                //float2 uv : TEXCOORD0;
            };

            struct Varings
            {
                float2 uv : TEXCOORD0;
                float4 position_cs : SV_POSITION;
            };

            // 拿到我们在 C# 里画好的入流漫反射图
            TEXTURE2D(_SkinDiffuseRT);
            SAMPLER(sampler_SkinDiffuseRT);
            float4 _SkinDiffuseRT_TexelSize;
            float4 _SubsurfaceScatteringDistance;
            float _SurfaceScale;
            
            Varings vert(Attibutes i)
            {
                Varings o;
                //o.position_cs = float4(i.position_os.xy, 0.0, 1.0);
                o.position_cs = GetFullScreenTriangleVertexPosition(i.vertex_id);
                //o.uv = i.uv;
                o.uv = GetFullScreenTriangleTexCoord(i.vertex_id);
                return o;
            }

            #define _MM_PER_METER 1000.0f * _SurfaceScale
            #define _METER_PER_MM 0.001f

            half4 frag(Varings i) : SV_Target
            {
                // 当前像素的数据
                float center_01_depth = SampleSceneDepth(i.uv);
                float center_real_depth = LinearEyeDepth(center_01_depth, _ZBufferParams);
                float3 irradiance = SAMPLE_TEXTURE2D(_SkinDiffuseRT, sampler_SkinDiffuseRT, i.uv).rgb;

                // 
                float fovScale = unity_CameraProjection[1][1];
                float metersPerPixel = (2.0 * center_real_depth) / (fovScale * _ScreenParams.y);
                float pixelsPerMm = rcp(max(0.00001f, metersPerPixel) * _MM_PER_METER);

                uint2 pixelCoord = (uint2)(i.uv * _ScreenParams.xy);
                float base_angle = TWO_PI * GenerateHashedRandomFloat(uint3(pixelCoord, (uint)(center_01_depth * 1235670.0f)));
                float sin_base_angle, cos_base_angle;
                sincos(base_angle, sin_base_angle, cos_base_angle);

                float3 total_radiance = 0.0;
                float3 total_weight = 0.0;
                int sample_count = 32;
                for (int k = 0; k < sample_count; k++)
                {
                    float scale = rcp(sample_count);
                    float offset = rcp(sample_count) * 0.5;
                    float cdf = k * scale + offset;
                    float sample_r, rcp_pdf;
                    SampleBurleyPDF(cdf, _SubsurfaceScatteringDistance.a, sample_r, rcp_pdf);

                    float random_angle = SampleDiskGolden1(k, sample_count).y;
                    float cos_random_angle, sin_random_angle;
                    sincos(random_angle, sin_random_angle, cos_random_angle);

                    // 和角公式，基础角度加随机角度
                    float sin_sample_angle = cos_base_angle * sin_random_angle + sin_base_angle * cos_random_angle;
                    float cos_sample_angle = cos_base_angle * cos_random_angle - sin_base_angle * sin_random_angle;
                    float2 sample_dir = float2(cos_sample_angle, sin_sample_angle);
                    // 当前屏幕坐标 + (采样方向 * 采样半径)(mm单位) * (每mm占的像素) = 新的像素坐标
                    float2 sample_position_ss = pixelCoord + round(pixelsPerMm * sample_r * sample_dir);

                    float2 sample_uv = sample_position_ss / _ScreenParams.xy;
                    float3 sample_irradiance = SAMPLE_TEXTURE2D(_SkinDiffuseRT, sampler_SkinDiffuseRT, sample_uv).rgb;
                    sample_irradiance = max(HALF_MIN, sample_irradiance);

                    // 计算 3D 距离
                    float sample_01_depth = SampleSceneDepth(sample_uv);
                    float sample_real_depth = LinearEyeDepth(sample_01_depth, _ZBufferParams);

                    float sample_depth = (sample_real_depth - center_real_depth) * _MM_PER_METER;
                    float real_sample_r = sqrt(sample_r * sample_r + sample_depth * sample_depth);
                    // 3d 世界里的真实距离
                    float3 weight = BurleyDiffusionProfile(real_sample_r, _SubsurfaceScatteringDistance.rgb) * rcp_pdf;

                    total_radiance += weight * sample_irradiance;
                    total_weight += weight;
                }

                //return half4(i.uv.y,0.0f,0.0f,0.0f);
                return half4(total_radiance / total_weight, 1.0);
            }
            ENDHLSL
        }
    }
}