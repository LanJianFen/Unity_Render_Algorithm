Shader "Custom/3D_Cube_Geometry_Fog"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _FogColor ("Fog Color", Color) = (0.5,0.8,1,1)
        _Intensity ("Intensity", Range(0.0, 1.0)) = 0.867

        [Header(Falloff)]
        [Space(5)]
        [PowerSlider(3.0)] _HorizontalFade ("X Horizontal Fade", Range(0.0, 1.0)) = 0.095
        [PowerSlider(3.0)] _VerticalFade ("Y Vertical Fade", Range(0.0, 1.0)) = 0.023
        [PowerSlider(3.0)] _DepthFade ("Z DepthFade Fade", Range(0.0, 1.0)) = 0.023

        [Header(Noise)]
        [Space(5)]
        [PowerSlider(2.0)] _NoiseScale("流动区域密度", Range(0.01, 1.0)) = 1.0
        _NoiseIntensity("流动强度", Range(0.0, 1.0)) = 0.5
        _NoiseSpeedX("X轴流动速度", Range(-1.0, 1.0)) = 1.0
        _NoiseSpeedY("Y轴流动速度", Range(-1.0, 1.0)) = 1.0
        _NoiseSpeedZ("Z轴流动速度", Range(-1.0, 1.0)) = 1.0

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
        Cull Front

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
                float3 position_os : TEXCOORD1;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _FogColor;
                half _Intensity;
                half _HorizontalFade;
                half _VerticalFade;
                half _DepthFade;
                half _NoiseScale;
                half _NoiseIntensity;
                half _NoiseSpeedX;
                half _NoiseSpeedY;
                half _NoiseSpeedZ;
                half _SpreadAngle;
                half _BlendDistance;
            CBUFFER_END

            #define L 1.0f

            v2f vertexShader(Attributes i)
            {
                v2f o;
                o.uv = i.uv;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_os = i.position_os.xyz;
                return o;
            }

            half4 fragmentShader(v2f i) : SV_Target
            {
                // 从归一化参数变到实际用的参数
                _VerticalFade = 40.0h * (_VerticalFade + 0.001h);
                _HorizontalFade = 40.0h * (_HorizontalFade + 0.001h);
                _DepthFade = 40.0h * (_DepthFade + 0.001h);
                _NoiseScale = 10.0h * _NoiseScale;
                _NoiseSpeedX = 0.2h * _NoiseSpeedX;
                _NoiseSpeedY = 0.2h * _NoiseSpeedY;
                _NoiseSpeedZ = 0.2h * _NoiseSpeedZ;

                // ============
                // 求射线与球的入射点和出射点
                // ============
                float3 ray_ori_os = TransformWorldToObject(_WorldSpaceCameraPos);
                float3 ray_dir_os = normalize(i.position_os - ray_ori_os);

                // AABB
                float3 box_min = float3(-L, -L, -L);
                float3 box_max = float3(L, L, L);

                float3 inv_ray_dir_os = 1.0f / (ray_dir_os + 1e-5);

                float3 t1 = (box_min - ray_ori_os) * inv_ray_dir_os;
                float3 t2 = (box_max - ray_ori_os) * inv_ray_dir_os;

                float3 t_in = min(t1, t2);
                float3 t_out = max(t1, t2);

                float t_near = max(t_in.z, max(t_in.x, t_in.y));
                float t_far = min(t_out.z, min(t_out.x, t_out.y));

                if (t_near > t_far) return half4(1, 0, 0, 0);
                t_near = max(0.0, t_near);
                // ============
                // 横向和纵向自然指数衰减 exp(- x * x * _Fade);
                // 立方体的几何雾气做不到没破绽，
                // exp(- x * x * _Fade)的几何形状是个椭圆球，遇到边界就会发生突变，颜色就断层了
                // exp(- x * x * x * x _Fade)的几何形状是个圆角立方体，但是求不出解析解
                // ============
                
                // 这个一元二次方程的极值点和最小值 / 中点  
                float t_mid = (t_near + t_far) * 0.5f;
                float3 mid_pos = ray_ori_os + t_mid * ray_dir_os;
                float average_falloff = exp(- pow(mid_pos.x,4)* _HorizontalFade- pow(mid_pos.y,4) * _VerticalFade -pow(mid_pos.z,4) * _DepthFade);
                

                // 路径上的极值点
                float3 sample_pos = mid_pos * _NoiseScale - _Time.y * float3(_NoiseSpeedX, _NoiseSpeedY, _NoiseSpeedZ);
                half noise_val = fbm3D(sample_pos);
                // 把低浓度的地方变成 0， 增加镂空感
                // noise_val = smoothstep(0.2h, 0.7h, noise_val)
                // 均匀雾, _NoiseIntensity = 0; 流动雾, _NoiseIntensity > 0
                half noise_falloff = lerp(1.0h, noise_val, _NoiseIntensity);

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
                half3 finalColor = depth_blend_falloff * noise_falloff * average_falloff * _Intensity * _FogColor.rgb;
                return half4(finalColor, 1.0h);
            }
            ENDHLSL
        }
    }
}