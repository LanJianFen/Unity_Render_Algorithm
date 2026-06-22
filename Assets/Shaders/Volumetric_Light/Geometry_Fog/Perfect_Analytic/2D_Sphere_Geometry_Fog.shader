Shader "Custom/2D_Sphere_Geometry_Fog"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _FogColor ("Fog Color", Color) = (0.5,0.8,1,1)
        _Intensity ("Intensity", Range(0.0, 1.0)) = 0.867
        
        [Header(Falloff)]
        [Space(5)]
        [PowerSlider(3.0)] _HorizontalFade ("Horizontal Fade", Range(0.0, 1.0)) = 0.095
        [PowerSlider(3.0)] _VerticalFade ("Vertical Fade", Range(0.0, 1.0)) = 0.023
        
        [Header(Noise)]
        [Space(5)]
        [PowerSlider(2.0)] _NoiseScale("流动区域密度", Range(0.01, 1.0)) = 1.0
        _NoiseIntensity("流动强度", Range(0.0, 1.0)) = 0.5
        _NoiseSpeedX("X轴流动速度", Range(-1.0, 1.0)) = 0.1
        _NoiseSpeedY("Y轴流动速度", Range(-1.0, 1.0)) = 0.1
        
        [Header(Background Blend)]
        [Space(5)]
        _BlendDistance ("Blend Distance", Range(0.0, 5.0)) = 2.0
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        Blend One One
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vertexShader
            #pragma fragment fragmentShader

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include  "../../../Common/Noise.hlsl"
            
            struct Attributes
            {
                float4 position_os : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 position_cs : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _FogColor;
                half _Intensity;
                half _HorizontalFade;
                half _VerticalFade;
                half _NoiseScale;
                half _NoiseIntensity;
                half _NoiseSpeedX;
                half _NoiseSpeedY;
                half _SpreadAngle;
                half _BlendDistance;
            CBUFFER_END

            v2f vertexShader(Attributes i)
            {
                v2f o;
                o.uv = i.uv;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                return o;
            }

            half4 fragmentShader(v2f i) : SV_Target
            {
                // 从归一化参数变到实际用的参数
                _Intensity = 10.0h * _Intensity;
                _VerticalFade = 40.0h * (_VerticalFade + 0.001h); 
                _HorizontalFade = 40.0h * (_HorizontalFade + 0.001h);
                _NoiseScale = 10.0h * _NoiseScale;
                _NoiseSpeedX = 0.2h * _NoiseSpeedX;
                _NoiseSpeedY = 0.2h * _NoiseSpeedY;

                // ============
                // 将 uv 坐标的原点移动到面片的中心
                // ============
                float2 uv = float2((i.uv.x - 0.5f) * 2.0f, (i.uv.y - 0.5f) * 2.0f);

                // ============
                // 横向和纵向自然指数衰减
                // ============
                half horizontal_falloff = exp(- uv.x * uv.x * _HorizontalFade);
                half vertical_falloff = exp(- uv.y * uv.y * _VerticalFade);
                
                 // ============
                // 流动噪声
                // ============
                // 采样坐标 = 绝对坐标 - 时间 * 方向。是为了噪声能够随时间连续变化
                // uv 本来是 [-1, 1] , Scale 放大到了 [-_NoiseScale, _NoiseScale] ,相当于给噪声创建了更多格子
                half2 sample_pos = (uv - _Time.y * half2(_NoiseSpeedX, _NoiseSpeedY)) * _NoiseScale;
                half noise_val = fBm2D(sample_pos);
                half noise_falloff = lerp(1.0h, noise_val, _NoiseIntensity); // 在无噪声和有噪声之间插值
                
                // ============
                // 深度软相交 shader 在这里藏了一手，把position_cs变成了position_ss
                // ============
                float2 screen_uv = i.position_cs.xy / _ScreenParams.xy;  
                float background_01_depth = SampleSceneDepth(screen_uv);
                float background_real_depth = LinearEyeDepth(background_01_depth, _ZBufferParams);
                // 圆锥和背景的深度差值
                float cone_real_depth = LinearEyeDepth(i.position_cs.z, _ZBufferParams);
                float depth_diff = background_real_depth - cone_real_depth;
                // 归一化，只有 [0, _BlendDistance] 的背景才会软化
                float depth_blend_falloff = saturate(depth_diff / _BlendDistance);

                // FadeIntensity 的物理意义是 每前进 1 米，这团物质能吸收多少光线
                // fixed_density 的 乘数说的是 透明的地方少衰减一点，不透明的地方多衰减一点（有意义吗？）
                // half fixed_density = _FadeIntensity * (1.0h + noise_val * 2.0h)
                // half blend_falloff = 1.0h - exp(- depth_diff * fixed_density)
                // 最终融合！  
                half3 finalColor = depth_blend_falloff * noise_falloff * horizontal_falloff * vertical_falloff * _Intensity * _FogColor.rgb;
                return half4(finalColor, 1.0h);
            }
            ENDHLSL
        }
    }
}