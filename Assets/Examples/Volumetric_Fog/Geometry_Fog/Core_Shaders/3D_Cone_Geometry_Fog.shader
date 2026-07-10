Shader "Custom/3D_Cone_Geometry_Fog"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _FogColor ("Fog Color", Color) = (0.5,0.8,1,1)
        _Intensity ("Intensity", Range(0.0, 1.0)) = 0.38

        [Header(Falloff)]
        [Space(5)]
        [PowerSlider(3.0)] _HorizontalFade ("Horizontal Fade", Range(0.0, 1.0)) = 0.13
        [PowerSlider(3.0)] _VerticalFade ("Vertical Fade", Range(0.0, 1.0)) = 0.22
        _CurveShape ("Curve Shape (Sharp to Smooth)", Range(0.0, 1.0)) = 0.73
        
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
                float2 uv            : TEXCOORD0;
            };

            struct v2f
            {
                float4 position_cs : SV_POSITION;
                float2 uv            : TEXCOORD0;
                float3 position_os : TEXCOORD1;
                float3 ray_ori_os  : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _FogColor;
                half _Intensity;
                half _HorizontalFade;
                half _VerticalFade;
                half _CurveShape;
                half _BlendDistance;
            CBUFFER_END

            #define _H  2.0f
            #define _R  0.5f
            #define _R2 0.25f
            #define _K2 0.0625f  // (_R / _H) ²
            
            v2f vertexShader(Attributes i)
            {
                v2f o;
                o.uv = i.uv;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_os = i.position_os.xyz;
                o.ray_ori_os = TransformWorldToObject(_WorldSpaceCameraPos); // 这个值放到 VS 里用一个插值器 trade off FS里每个像素的矩阵乘法
                return o;
            }

            half getPointFalloff(float3 p)
            {
                // 径向衰减 : (1 -x * x) 的 _HorizontalFade 次方  
                float dist_to_central_axis2 = p.x * p.x + p.z * p.z;
                float radius_at_point2 = _K2 * p.y * p.y; // ( _R / _H * p.y) ²
                half radial_ratio2 = saturate(dist_to_central_axis2 / radius_at_point2); // 数学上没必要saturate，但是防一下
                half radial_ratio = sqrt(radial_ratio2);  
                half radial_falloff = pow(1.0h - lerp(radial_ratio, radial_ratio2, _CurveShape), _HorizontalFade);
                //half radial_falloff = exp( - radial_ratio2, _HorizontalFade);
                
                // 纵向衰减: (1 - y) 的 _VerticalFade 次方  
                half vertical_radio = saturate(p.y / _H); // 数学上没必要saturate，但是防一下  
                half vertical_falloff = pow(1 - vertical_radio, _VerticalFade);

                return vertical_falloff * radial_falloff;
            }

            half4 fragmentShader(v2f i) : SV_Target
            {
                // 从归一化参数变到实际用的参数
                _Intensity = 10.0h * _Intensity;
                _VerticalFade = 20.0h * (_VerticalFade + 0.001h); // 0.25 ，在盖子和侧面的交界线两侧，雾气的厚度是逐渐下降的，造成了交界线的雾气最厚，颜色最淡，发生了断层，所以把整个盖子直接在垂直方向去掉
                _HorizontalFade = 20.0h * (_HorizontalFade + 0.001h);
                
                // Object Space 下的视线起点和视线方向  
                float3 ray_ori_os = i.ray_ori_os;
                float3 ray_dir_os = normalize(i.position_os - ray_ori_os);

                // ============
                // 求解射线 O + t · D 与 圆锥 x² + z² = (R/H)² · y² 的交点
                // ============
                // 联立后是一个二元一次方程
                // b, delta, t_1, t_2 可以把 2.0f 约分掉，但是这里为了阅读数学公式就不约分
                float a = ray_dir_os.x * ray_dir_os.x + ray_dir_os.z * ray_dir_os.z - _K2 * ray_dir_os.y * ray_dir_os.y;
                float b = 2.0f * (ray_ori_os.x * ray_dir_os.x + ray_ori_os.z * ray_dir_os.z - _K2 * ray_ori_os.y * ray_dir_os.y);
                float c = ray_ori_os.x * ray_ori_os.x + ray_ori_os.z * ray_ori_os.z - _K2 * ray_ori_os.y * ray_ori_os.y;

                float delta = b * b - 4.0f * a * c;
                if (delta < 0.000f) return half4(0.0h, 0.0h, 0.0h, 0.0h); // 没射中,返回全红当debug  

                float sqrt_delta = sqrt(delta);
                float t_1 = (-b - sqrt_delta) / (2.0f * a);
                float t_2 = (-b + sqrt_delta) / (2.0f * a);

                // 1. 准备篮子 (初始值为极端值)   
                float t_near = 9999.0f;
                float t_far = -9999.0f;
                
                // 安检 t_1：看真实 Y 坐标是否在 [0, H] 的真圆锥范围内  
                float y1 = ray_ori_os.y + t_1 * ray_dir_os.y;
                if (y1 >= 0.0f && y1 <= _H)
                {
                    // 合法！扔进篮子，更新最小和最大值  
                    t_near = min(t_near, t_1);
                    t_far = max(t_far, t_1);
                }

                // 安检 t_2：看真实 Y 坐标是否合法 (完美剔除了下半截假沙漏)   
                float y2 = ray_ori_os.y + t_2 * ray_dir_os.y;
                if (y2 >= 0.0f && y2 <= _H)
                {
                    // 合法！扔进篮子  
                    t_near = min(t_near, t_2);
                    t_far = max(t_far, t_2);
                }

                
                float t_bottom = (_H - ray_ori_os.y) / ray_dir_os.y;
                // 安检 t_bottom：算一下它打在了底面平面的哪个位置？   
                float3 p_bottom = ray_ori_os + t_bottom * ray_dir_os;
                // 它必须打在圆锥底面的那个实心圆盘里面！(半径为 _R)   
                if (dot(p_bottom.xz, p_bottom.xz) <= _R2)
                {
                    // 合法！扔进篮子  
                    t_near = min(t_near, t_bottom);
                    t_far = max(t_far, t_bottom);
                }

                if (t_near >= t_far) return half4(0.0h, 0.0h, 0.0h, 0.0h); // 彻底没射中,返回黄色Debug
                t_near = max(0.0f, t_near); // 在圆锥内部的时候，t_near是负数，此时会导致积分域从身后开始，看向圆锥底部时也会像光源一样发亮
                // ============
                // 开始取点，计算  VerticalFade(t) * HorizontalFade(t) ，计算积分必须引入物理透射率，否则是错的
                // 本质上是两个场的乘积，在射线路径 [t_near, t_far] 的上取点代入计算
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
                /*float3 mid_os = ray_ori_os + 0.5 * (t_near + t_far) * ray_dir_os;
                half falloff_mid = getPointFalloff(mid_os);
                half average_falloff = falloff_mid;
                */
                
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
                
                // 重心法
                // 在  Vertical (t) · Horizontal (t) 的基础上加上光源衰减（反比平方光源会曝光）变成  Center (t) · Vertical (t) · Horizontal (t) 
                // t_barycenter = ∫ t · Center (t) dt / ∫ Center (t) dt
                // Center (t) = 1 / r² (t)
                float v = dot(ray_ori_os, ray_dir_os);  
                float p2 = dot(ray_ori_os, ray_ori_os) - v * v;  
                float p = sqrt(max(p2,1e-5)); // 加微小值代表灯泡物理半径 , 去掉了，暂时不管
  
                // 计算t*  
                float M0 = (atan2(t_far + v, p) - atan2(t_near + v, p)) / p;  
                float M1 = (log((((t_far + v) * (t_far + v)) + p2) / (((t_near + v) * (t_near + v)) + p2))) / 2.0f - v * M0;  
  
                // t_barycenter: 真正的物理能量重心！  
                float t_barycenter = M1 / M0;  
                t_barycenter = clamp(t_barycenter, t_near, t_far);
                
                float3 p_barycenter = ray_ori_os + t_barycenter * ray_dir_os;  
                half average_falloff = getPointFalloff(p_barycenter);

                // ============
                // 当t_far被底盖截断时，会导致积分域变短，重心更靠近中心，于是俯视光源的时候，就能看到底盖中间亮，边缘暗。因此加上一个mask
                // ============
                //float3 pFar = ray_ori_os + t_far * ray_dir_os;

                // 制作一个底盖溶解遮罩 (假设 _H = 1.0)，这里是不对的，后续需要改
                // 当射线终点非常靠近底盖 (例如达到 0.9*H) 时，强行把透明度滑向 0
                //half bottom_falloff = smoothstep(1.0h, 0.9h, (half)pFar.y);
                
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
                
                // 最终融合！  Blend One One, alpha 返回什么无所谓
                return depth_blend_falloff * average_falloff * _Intensity * _FogColor;
            }
            ENDHLSL
        }
    }
}