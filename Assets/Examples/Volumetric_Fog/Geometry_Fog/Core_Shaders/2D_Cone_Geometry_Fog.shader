Shader "Custom/2D_Cone_Geometry_Fog"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _FogColor ("Fog Color", Color) = (0.5,0.8,1,1)
        _Intensity ("Intensity", Range(0.0, 1.0)) = 0.867

        [Header(Shape)]
        [Space(5)]
        [PowerSlider(3.0)] _SpreadAngle ("Spread Angle", Range(0.001, 45.0)) = 30.0
        
        [Header(Falloff)]
        [Space(5)]
        [PowerSlider(3.0)] _HorizontalFade ("Horizontal Fade", Range(0.0, 1.0)) = 0.095
        [PowerSlider(3.0)] _VerticalFade ("Vertical Fade", Range(0.0, 1.0)) = 0.023
        _CurveShape ("Curve Shape (Sharp to Smooth)", Range(0.0, 1.0)) = 0.23
        
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
        Cull Off

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
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _FogColor;
                half _Intensity;
                half _HorizontalFade;
                half _VerticalFade;
                half _CurveShape;
                half _SpreadAngle;
                half _BlendDistance;
            CBUFFER_END
            
            v2f vertexShader(Attributes i)
            {
                v2f o;
                o.uv = i.uv;

                // ==================
                // 圆柱形 BillBoard 算法，绕 y 轴旋转
                // ==================
                // 计算中心点在 WS 的位置
                float3 center_ws = TransformObjectToWorld(float3(0.0f, 0.0f, 0.0f));
                // 从 M 矩阵提取出 Scale，用 length 是消除表达式里的 Rotation 
                float scale_x = length(unity_ObjectToWorld._m00_m10_m20);
                float scale_y = length(unity_ObjectToWorld._m01_m11_m21);

                // 算出中心点的三轴，其中 forward 面向相机。这三个新轴是一个新的正交基，构成了一个从标准正交基旋转过来的矩阵
                float3 up_ws = TransformObjectToWorldDir(float3(0.0f, 1.0f, 0.0f), true);
                float3 forward_ws = normalize(_WorldSpaceCameraPos - center_ws);
                float3 right_ws = normalize(cross(up_ws, forward_ws));

                // 把 position_os 经过 Scale 变换后，再经过新的 Rotation 变换，但是这里不需要 Z 轴
                float3 offset_ws = right_ws * (i.position_os.x * scale_x) + up_ws * (i.position_os.y * scale_y);
                float3 new_ws = center_ws + offset_ws;
                o.position_cs = TransformWorldToHClip(new_ws);
                return o;
            }

            half4 fragmentShader(v2f i) : SV_Target
            {
                // 从归一化参数变到实际用的参数
                _Intensity = 10.0h * _Intensity;
                _VerticalFade = 30.0h * (_VerticalFade + 0.001h); 
                _HorizontalFade = 30.0h * (_HorizontalFade + 0.001h);
                
                // ============
                // 将 uv 坐标的原点变到底边的中点
                // ============
                float pos_x = abs(i.uv.x - 0.5f) * 2.0f;
                float pos_y = saturate(i.uv.y);
                
                // ============
                // 在 uv 空间计算纵向衰减和径向衰减
                // ============
                
                // 径向衰减 : (1 -x * x) 的k1次方
                // 需要画一个三角形。在三角形内部归一化的到中轴的距离 = 与中轴的实际距离 / 当前y的三角形的边到中轴的实际距离
                float tan_center_angle = tan(radians(_SpreadAngle)); 
                half normalized_dist_to_central_axis = saturate(pos_x / (max(pos_y, 1e-5) * tan_center_angle));
                half horizontal_falloff = pow(1.0h - lerp(normalized_dist_to_central_axis, normalized_dist_to_central_axis, _CurveShape), _HorizontalFade);

                // 纵向衰减: (1 - y) 的 k2次方
                half vertical_falloff = pow(saturate(1.0h - pos_y), _VerticalFade);
                
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
                return depth_blend_falloff * horizontal_falloff * vertical_falloff * _Intensity * _FogColor;
            }
            ENDHLSL
        }
    }
}