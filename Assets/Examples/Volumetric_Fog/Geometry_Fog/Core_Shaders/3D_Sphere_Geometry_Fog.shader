Shader "Custom/3D_Sphere_Geometry_Fog"
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
            #include  "../../../../Common/Shaders/Math.hlsl"
            #include  "../../../../Common/Shaders/Noise.hlsl"

            struct Attributes
            {
                float4 position_os : POSITION;
            };

            struct v2f
            {
                float4 position_cs : SV_POSITION;
                float3 position_os : TEXCOORD0;
                float3 ray_ori_os  : TEXCOORD1;
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
                half _NoiseSpeedZ;
                half _SpreadAngle;
                half _BlendDistance;
            CBUFFER_END

            #define _R 0.5f
            #define _R2 0.25f

            v2f vertexShader(Attributes i)
            {
                v2f o;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_os = i.position_os.xyz;
                o.ray_ori_os = TransformWorldToObject(_WorldSpaceCameraPos); // 这个值放到 VS 里用一个插值器 trade off FS里每个像素的矩阵乘法
                return o;
            }

            half4 fragmentShader(v2f i) : SV_Target
            {
                // 从归一化参数变到实际用的参数
                _VerticalFade = 40.0h * (_VerticalFade + 0.001h);
                _HorizontalFade = 40.0h * (_HorizontalFade + 0.001h);
                _NoiseScale = 10.0h * _NoiseScale;
                _NoiseSpeedX = 0.2h * _NoiseSpeedX;
                _NoiseSpeedY = 0.2h * _NoiseSpeedY;
                _NoiseSpeedZ = 0.2h * _NoiseSpeedZ;

                // 积分法，这是错的，没考虑路径上的透射衰减，直接在路径上对场积分是错误的
                /*
                // ============
                // 求射线与球的入射点和出射点
                // ============
                float3 ray_ori_os = TransformWorldToObject(_WorldSpaceCameraPos);
                float3 ray_dir_os = normalize(i.position_os - ray_ori_os);

                // 代入球方程得到 (D · D) t² + 2 (O · D) t + (O · O - R²) = 0
                // ray_dir_os 是归一化的 所以 a = 1
                float B = dot(ray_ori_os, ray_dir_os);
                float C = dot(ray_ori_os, ray_ori_os) - R * R;
                float delta = B * B - C;
                if (delta < 0.0f) return half4(0.0h, 0.0h, 0.0h, 0.0h);

                float sqrt_delta = sqrt(delta);
                float t_near = -B - sqrt_delta;
                float t_far = -B + sqrt_delta;
                t_near = max(t_near, 0.0f);

                // ============
                // 横向和纵向自然指数衰减 exp(- x * x * _Fade);
                // 本该在 [t_near, t_far]上找个重心，但是这样会加剧计算量，实际上只算 ∫ HorizontalFade * VerticalFade dt 在这个例子里趋势的正确的
                // 求极值好像也行？
                // ============

                // O + t D 代入指数，得到一元二次方程
                float a = _HorizontalFade * (ray_dir_os.x * ray_dir_os.x + ray_dir_os.z * ray_dir_os.z) + _VerticalFade
                    * ray_dir_os.y * ray_dir_os.y;
                float b = (_HorizontalFade * (ray_ori_os.x * ray_dir_os.x + ray_ori_os.z * ray_dir_os.z) + _VerticalFade
                    * ray_ori_os.y * ray_dir_os.y) * 2.0f;
                float c = _HorizontalFade * (ray_ori_os.x * ray_ori_os.x + ray_ori_os.z * ray_ori_os.z) + _VerticalFade
                    * ray_ori_os.y * ray_ori_os.y;

                // 这个一元二次方程的极值点和最小值  
                float t_extremum = -b / (2.0f * a);
                float min_value = c - t_extremum * t_extremum * a;

                // ============= 纵向衰减函数和横向衰减函数在路径 [t_near, t_far] 的解析原函数 ========================  
                float sqrt_a = sqrt(a);
                half average_falloff = 0.5f * exp(-min_value) * sqrt(PI / a) *
                    (erfApproximate(sqrt_a * (t_far - t_extremum)) -erfApproximate(sqrt_a * (t_near - t_extremum)));
                */

                // 正确的做法是在 [t_near, t_far] 找一点代入标量场 ，这里找最靠近球心的一点
                float3 ray_ori_os = i.ray_ori_os;
                float3 ray_dir_os = normalize(i.position_os - ray_ori_os);
                // (O + t · D)² ，tmin = - (O · D)
                // 路径上的极值点, 可能在入射点和出射点外部，但是不用在意
                float t_extremum = -dot(ray_ori_os , ray_dir_os);
                float3 extremum_pos = ray_ori_os + t_extremum * ray_dir_os;
                //half average_falloff = exp(- (extremum_pos.x * extremum_pos.x + extremum_pos.z * extremum_pos.z) * _HorizontalFade - extremum_pos.y * extremum_pos.y * _VerticalFade );
                half horizontal_ratio2 = (extremum_pos.x * extremum_pos.x + extremum_pos.z * extremum_pos.z) / _R2;  // 这里是两个方向的衰减形状当成一个圆柱了，不然减少横向的时候看起来还是一个球
                half horizontal_falloff = pow(1.0h - horizontal_ratio2, _HorizontalFade);

                half vertical_ratio2 = extremum_pos.z * extremum_pos.z / _R2;
                half vertical_falloff = pow(1.0h - vertical_ratio2, _VerticalFade);
                half average_falloff = horizontal_falloff * vertical_falloff;

                half3 sample_pos = extremum_pos * _NoiseScale - (half)_Time.y * half3(_NoiseSpeedX, _NoiseSpeedY, _NoiseSpeedZ);
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
                half depth_diff = background_real_depth - cone_real_depth;
                // 归一化，只有 [0, _BlendDistance] 的背景才会软化
                half depth_blend_falloff = saturate(depth_diff / _BlendDistance);

                // FadeIntensity 的物理意义是 每前进 1 米，这团物质能吸收多少光线
                // fixed_density 的 乘数说的是 透明的地方少衰减一点，不透明的地方多衰减一点（有意义吗？）
                // half fixed_density = _FadeIntensity * (1.0h + noise_val * 2.0h)
                // half blend_falloff = 1.0h - exp(- depth_diff * fixed_density)
                // 最终融合！  Blend One One, alpha 返回什么无所谓
                return depth_blend_falloff * noise_falloff * average_falloff *_Intensity * _FogColor;
            }
            ENDHLSL
        }
    }
}