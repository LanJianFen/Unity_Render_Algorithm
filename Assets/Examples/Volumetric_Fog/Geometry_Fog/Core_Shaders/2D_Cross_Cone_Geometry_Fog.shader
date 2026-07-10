Shader "Custom/2D_Cross_Cone_Geometry_Fog"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _FogColor ("Fog Color", Color) = (0.5,0.8,1,1)
        _Intensity ("Intensity", Range(0.0, 1.0)) = 0.38
        
        [Header(Shape)]
        [Space(5)]
        [PowerSlider(3.0)] _SpreadAngle ("Spread Angle", Range(0.001, 45.0)) = 30.0
        
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
                float3 normal_os  : NORMAL;
            };

            struct v2f
            {
                float4 position_cs : SV_POSITION;
                float2 uv            : TEXCOORD0;
                float3 position_os : TEXCOORD1;
                float3 normal_os  : TEXCOORD2;
                float3 camera_os  : TEXCOORD3;
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
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_os = i.position_os.xyz;
                o.normal_os = i.normal_os;
                o.camera_os = TransformWorldToObject(_WorldSpaceCameraPos); // 这个值放到 VS 里用一个插值器 trade off FS里每个像素的矩阵乘法
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
                // 视角融合 交叉90度一个是 cos²θ 另一个cos²(θ-90) 加起来是1
                // 三个交叉 cos²θ cos²(θ-60) cos²(θ-120) 加起来是1，5
                // ============
                float3 camera_os = i.camera_os;
                half3 view_dir = normalize(camera_os - i.position_os);
                half NdotV = dot(i.normal_os, view_dir);
                half NdotV2 = NdotV * NdotV;
                
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
                return depth_blend_falloff  * NdotV2 * horizontal_falloff * vertical_falloff * _Intensity * _FogColor;
            }
            ENDHLSL
        }
    }
}