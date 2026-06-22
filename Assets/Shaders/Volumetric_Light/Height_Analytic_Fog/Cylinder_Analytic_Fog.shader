Shader "Custom/3D_Cone_Geometry_Fog"
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
        _CurveShape ("Curve Shape (Sharp to Smooth)", Range(0.0, 1.0)) = 0.23

        [Header(Shape (No need to expose)]
        [Space(5)]
        _H ("Height", Float) = 2.0
        _R ("Radius", Float) = 0.5
        
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
            "RenderPipeline"="UniversalPipeline"
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
                half _CurveShape;
                half _H;
                half _R;
                half _BlendDistance;
            CBUFFER_END
            
            v2f vertexShader(Attributes i)
            {
                v2f o;
                o.uv = i.uv;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_os = i.position_os.xyz;
                return o;
            }

            float getPointFalloff(float3 p)
            {
                // 径向衰减 : (1 -x * x) 的k1次方  
                float dist_to_central_axis2 = p.x * p.x + p.z * p.z;
                float radius_at_point2 = _R * _R * p.y * p.y / (_H * _H); // _R/_H * p.y的平方  
                half radial_radio2 = saturate(dist_to_central_axis2 / radius_at_point2); // 数学上没必要saturate，但是防一下
                half radial_radio = sqrt(radial_radio2);  
                half radial_falloff = pow(1 - lerp(radial_radio, radial_radio2, _CurveShape), _HorizontalFade);

                // 纵向衰减: (1 - y) 的 k2次方  
                half vertical_radio = saturate(p.y / _H); // 数学上没必要saturate，但是防一下  
                half vertical_falloff = pow(1 - vertical_radio, _VerticalFade);

                return vertical_falloff * radial_falloff;
            }

            half4 fragmentShader(v2f i) : SV_Target
            {
                // 从归一化参数变到实际用的参数
                _Intensity = 10.0 * _Intensity;
                _VerticalFade = 10 * (_VerticalFade + 0.25); // 0.25 ，在盖子和侧面的交界线两侧，雾气的厚度是逐渐下降的，造成了交界线的雾气最厚，颜色最淡，发生了断层，所以把整个盖子直接在垂直方向去掉
                _HorizontalFade = 30 * (_HorizontalFade + 0.001);
                // Object Space 下的视线起点和视线方向  
                float3 ray_ori_os = TransformWorldToObject(_WorldSpaceCameraPos);
                float3 ray_dir_os = normalize(i.position_os - ray_ori_os);

                // ============
                // 求解射线 O + t · D 与 圆锥 x² + z² = (R/H)² · y² 的交点
                // ============
                // 联立后是一个二元一次方程
                float k2 = pow((_R / _H), 2);

                float a = ray_dir_os.x * ray_dir_os.x + ray_dir_os.z * ray_dir_os.z - k2 * ray_dir_os.y * ray_dir_os.y;
                float b = 2.0 * (ray_ori_os.x * ray_dir_os.x + ray_ori_os.z * ray_dir_os.z - k2 * ray_ori_os.y * ray_dir_os.y);
                float c = ray_ori_os.x * ray_ori_os.x + ray_ori_os.z * ray_ori_os.z - k2 * ray_ori_os.y * ray_ori_os.y;

                float delta = b * b - 4 * a * c;
                if (delta < 0.000) return half4(0, 0, 0, 0); // 没射中,返回全红当debug  

                float sqrt_delta = sqrt(delta);
                float t_1 = (-b - sqrt_delta) / (2.0 * a);
                float t_2 = (-b + sqrt_delta) / (2.0 * a);

                // 1. 准备篮子 (初始值为极端值)   
                float t_near = 999999.0;
                float t_far = -999999.0;
                // 安检 t_1：看真实 Y 坐标是否在 [0, H] 的真圆锥范围内  

                float y1 = ray_ori_os.y + t_1 * ray_dir_os.y;
                if (y1 >= 0.0 && y1 <= _H)
                {
                    // 合法！扔进篮子，更新最小和最大值  
                    t_near = min(t_near, t_1);
                    t_far = max(t_far, t_1);
                }

                // 安检 t_2：看真实 Y 坐标是否合法 (完美剔除了下半截假沙漏)   
                float y2 = ray_ori_os.y + t_2 * ray_dir_os.y;
                if (y2 >= 0.0 && y2 <= _H)
                {
                    // 合法！扔进篮子  
                    t_near = min(t_near, t_2);
                    t_far = max(t_far, t_2);
                }


                float t_bottom = (_H - ray_ori_os.y) / ray_dir_os.y;
                // 安检 t_bottom：算一下它打在了底面平面的哪个位置？   
                float3 p_bottom = ray_ori_os + t_bottom * ray_dir_os;
                // 它必须打在圆锥底面的那个实心圆盘里面！(半径为 _R)   
                if (dot(p_bottom.xz, p_bottom.xz) <= _R * _R)
                {
                    // 合法！扔进篮子  
                    t_near = min(t_near, t_bottom);
                    t_far = max(t_far, t_bottom);
                }

                if (t_near >= t_far) return half4(0, 0, 0, 0); // 彻底没射中,返回黄色Debug

                // ============
                // 开始取点，计算积分 Sum ( VerticalFade(t) * HorizontalFade(t) dt)
                // 本质上是两个场的乘积，在射线路径 [t_near, t_far] 的积分
                // ============
                
                // 辛普森 ：在区间[a, b]积分，近似为 (b - a) * (f(a) + f(0.5 * (a  + b)) + f(b)) /0.6
                // 但是在 t_near 和 t_far, getPointFalloff 的值为0，三点退化成 中点 了
                /*float3 enter_os = ray_ori_os + t_near * ray_dir_os;
                  float3 mid_os = ray_ori_os + 0.5 * (t_near + t_far) * ray_dir_os;
                  float3 exit_os = ray_ori_os + t_far * ray_dir_os;

                  half falloff_enter = getPointFalloff(enter_os);
                  half falloff_mid = getPointFalloff(mid_os);
                  half falloff_exit = getPointFalloff(exit_os);
                  half average_falloff = （t_far - t_near) * (falloff_enter + 4.0 * falloff_mid + falloff_exit) / 6.0;
                */
                
                // 中点近似。
                // 侧面效果不错，但是从圆锥底部方向看，中点的亮度比较低，即使直视灯光也很暗
                float3 mid_os = ray_ori_os + 0.5 * (t_near + t_far) * ray_dir_os;
                half falloff_mid = getPointFalloff(mid_os);
                half average_falloff = falloff_mid;
                
                // 两点近似
                // 稍微有点太平滑了
                /*float t_mid = 0.5f * (t_near + t_far);
                float half_interval = 0.5f * (t_far - t_near);  // 半区间长度
                float t1 = t_mid - half_interval * 0.57735027f;  
                float t2 = t_mid + half_interval * 0.57735027f;  // 高斯黄金采样点位置 (常数 0.57735027 是 1/sqrt(3))

                float3 p1_os = ray_ori_os + t1 * ray_dir_os;
                float3 p2_os = ray_ori_os + t2 * ray_dir_os;
                half falloff_p1 = getPointFalloff(p1_os); 
                half falloff_p2 = getPointFalloff(p2_os);

                half average_falloff = half_interval * (falloff_p1 + falloff_p2);
                */

                // 第一积分中值定理法
                // 在 ∫ Vertical (t) · Horizontal (t) dt 的基础上加上光源衰减（好积分，并且光源会曝光）变成 ∫ Center (t) · Vertical (t) · Horizontal (t) dt
                // 分离成 Vertical (t*) · Horizontal (t*) · ∫ Center (t)  dt, t* = ∫ t · Center (t) dt / ∫ Center (t) dt
                // Center (t) = 1 / r² (t)
                /*float v = dot(ray_ori_os, ray_dir_os);  
                float p2 = dot(ray_ori_os, ray_ori_os) - v * v;  
                float p = sqrt(max(p2,1e-5)); // 加微小值代表灯泡物理半径 , 去掉了，暂时不管
  
                // 计算t*  
                float M0 = (atan2(t_far + v, p) - atan2(t_near + v, p)) / p;  
                float M1 = (log((((t_far + v) * (t_far + v)) + p2) / (((t_near + v) * (t_near + v)) + p2))) / 2.0 - v * M0;  
  
                // t_star: 真正的物理能量重心！  
                float t_star = 0.0;  
                if (abs(M0) < 1e-6)  
                    t_star = (t_near + t_far) * 0.5; // 如果没收集到能量，退化为中点  
                else  
                    t_star = M1 / M0;  
  
                t_star = clamp(t_star, t_near, t_far);  
                float3 pStar = ray_ori_os + t_star * ray_dir_os;  
                half average_falloff = getPointFalloff(pStar) * M0;
                */
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
                
                // 最终融合！  
                half3 finalRadiance = depth_blend_falloff * average_falloff * _Intensity * _FogColor.rgb;
                return half4(finalRadiance, 1);
            }
            ENDHLSL
        }
    }
}