
Shader "QSheng/Subsurface Scattering"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "Ture" }
        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D_FLOAT(_SkinDepth);
        SAMPLER(sampler_SkinDepth);
        float4 _SkinDepth_TexelSize;

        TEXTURE2D(_SkinDiffuse);
        SAMPLER(sampler_SkinDiffuse);

        float4 _ShapeParamsAndMaxScatterDists;
        float4 _TransmissionTintAndFresne10;

        float4x4 _InvProjectMatrix;
        float _WorldScale;

        struct Attributes
        {
            float4 positionOS : POSITION;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float4 uv : TEXCOORD0;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        // Burley Normalized Diffusion
        void SampleBurleyDiffusionProfile(float u, float rcpS, out float r, out float rcpPdf)
        {
            u = 1 - u; // Convert CDF to CCDF

            float g = 1 + (4 * u) * (2 * u + sqrt(1 + (4 * u) * u));
            float n = exp2(log2(g) * (- 1.0 / 3.0));
            float p = (g * n) * n;
            float c = 1 + p + n;
            float d = (3 / LOG2_E * 2) + (3 / LOG2_E) * log2(u);
            float x = (3 / LOG2_E) * log2(c) - d;

            float rcpExp = ((c * c) * c) * rcp((4 * u) * ((c * c) + (4 * u) * (4 * u)));

            r = x * rcpS;
            rcpPdf = (8 * PI * rcpS) * rcpExp;
        }

        float2 SampleDiskGolden1(uint i, uint sampleCount)
        {
            float2 f = Golden2dSeq(i, sampleCount);
            return float2(sqrt(f.x), TWO_PI * f.y);
        }

        float3 EvalBurleyDiffusionProfile(float r, float3 S)
        {
            float3 exp_13 = exp2(((LOG2_E * (- 1.0 / 3.0)) * r) * S);
            float3 expSum = exp_13 * (1 + exp_13 * exp_13);

            return (S * rcp(8 * PI)) * expSum;
        }

        float3 ComputeBilateralWeight(float xy2, float z, float mmPerUnit, float3 S, float rcpPdf)
        {
            float r = sqrt(xy2 + (z * mmPerUnit) * (z * mmPerUnit));
            float area = rcpPdf;
            return saturate(EvalBurleyDiffusionProfile(r, S) * area);
        }

        Varyings VertexSS (Attributes input)
        {
            Varyings output;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

            // 从模型空间转换到裁剪空间
            output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
            float4 cs = output.positionCS / output.positionCS.w;
            output.uv = ComputeScreenPos(cs);

            return output;
        }

        // float _FrameCount;
        float _FilterRadii;
        #define SSS_PIXELS_PER_SAMPLE 4 // 4像素一个采样点


        half4 FragmentSS (Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.uv.xy / input.uv.w;
            float2 posSS = uv * _SkinDepth_TexelSize.zw;
            float depth = SAMPLE_TEXTURE2D_X(_SkinDepth, sampler_SkinDepth, uv).r;
            float linearDepth = LinearEyeDepth(depth, _ZBufferParams);
            float2 cornerPosNDC = uv + 0.5 * _SkinDepth_TexelSize.xy;

            #if UNITY_REVERSED_Z
            depth = 1 - depth;
            #endif
            depth = 2 * depth - 1;

            float3 centerPosVS = ComputeViewSpacePosition(uv, depth, _InvProjectMatrix);
            float3 cornerPosVS = ComputeViewSpacePosition(cornerPosNDC, depth, _InvProjectMatrix);
            float mmPerUnit = 1000.0;
            float unitsPerMm = rcp(mmPerUnit);
            float worldScale = _WorldScale;
            float unitsPerPixel = max(0.001f, 2.0 * abs(cornerPosVS.x - centerPosVS.x)) * worldScale; // 1像素覆盖多少米
            float pixelsPerMm = rcp(unitsPerPixel) * unitsPerMm; // 1毫米覆盖多少像素

            // SSS散射最大距离(毫米)
            float filterRadius = _FilterRadii;
            float filterArea = PI * Sq(filterRadius * pixelsPerMm); // 圆盘范围内覆盖多少像素
            uint sampleCount = (uint)(filterArea / (SSS_PIXELS_PER_SAMPLE)); // 圆盘范围内采样点数量
            uint sampleBudget = (uint)5;
            uint n = min(sampleCount, sampleBudget);
            float3 S = _ShapeParamsAndMaxScatterDists.rgb;
            float d = _ShapeParamsAndMaxScatterDists.a;
            float2 pixelCoord = posSS;
            float3 totalIrradiance = 0;
            float3 totalWeight = 0;

            // 根据屏幕坐标随机生成一个角度
            float phase = TWO_PI * GenerateHashedRandomFloat(uint3(posSS, (uint)(depth * 16777216)));
            for(uint i = 0; i < n; i ++) // 循环
            {
                float scale = rcp(n);
                float offset = rcp(n) * 0.5;

                float sinPhase, cosPhase;
                sincos(phase, sinPhase, cosPhase);

                float r, rcpPdf;
                // 通过 i * scale + offset 的均匀递增数作为随机数计算出重要性采样的距离
                SampleBurleyDiffusionProfile(i * scale + offset, d, r, rcpPdf);
                float phi = SampleDiskGolden1(i, n).y;
                float sinPhi, cosPhi;
                sincos(phi, sinPhi, cosPhi);

                float sinPsi = cosPhase * sinPhi + sinPhase * cosPhi; // sin(phase + phi)
                float cosPsi = cosPhase * cosPhi + sinPhase * sinPhi; // cos(phase + phi)
                float2 vec = r * float2(cosPsi, sinPsi);
                //根据采样距离r，在圆盘上随机角度采样
                float2 position = pixelCoord + round((pixelsPerMm * r) * float2(cosPsi, sinPsi));

                float xy2 = r * r;
                float2 sampleUV = position * _SkinDepth_TexelSize.xy;
                float3 irradiance = SAMPLE_TEXTURE2D_X(_SkinDiffuse, sampler_SkinDiffuse, sampleUV);
                // 因为没有使用模板测试, 在Diffuse计算时需要通过 diffuse.b = max(diffuse.b, HALF_MIN) 来表示
                if(irradiance.b > 0.0)
                {
                    float sampleDevZ = SAMPLE_TEXTURE2D_X(_SkinDepth, sampler_SkinDepth, sampleUV).r;
                    float sampleLinearZ = LinearEyeDepth(sampleDevZ, _ZBufferParams);
                    float relZ = sampleLinearZ - linearDepth;
                    //根据r计算diffusion profile和权重
                    float3 weight = ComputeBilateralWeight(xy2, relZ, mmPerUnit, S, rcpPdf);
                    totalIrradiance += weight * irradiance;
                    totalWeight += weight;
                }
            }

            if(dot(totalIrradiance, float3(1, 1, 1)) == 0.0)
            {
                return SAMPLE_TEXTURE2D_X(_SkinDiffuse, sampler_SkinDiffuse, uv);
            }
            totalWeight = max(totalWeight, FLT_MIN);
            return float4(totalIrradiance / totalWeight, 1.0);
        }
        ENDHLSL
        LOD 100

        Pass
        {
            Name "Subsurface Scattering Pass"
            ZTest Always
            ZWrite Off
            Cull Off
            HLSLPROGRAM

            #pragma vertex VertexSS
            #pragma fragment FragmentSS
            ENDHLSL
        }
    }
}