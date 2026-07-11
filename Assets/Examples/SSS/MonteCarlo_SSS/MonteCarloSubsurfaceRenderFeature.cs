using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Serialization;

namespace Examples.SSS.MonteCarlo_SSS
{
    public class MonteCarloSubsurfaceScatteringRenderFeature : ScriptableRendererFeature
    {
        private class SubsurfaceScatteringForwardPass : ScriptableRenderPass
        {
            private readonly int _skinDiffuseRT = Shader.PropertyToID("_SkinDiffuseRT");
            private readonly ShaderTagId _shaderTagId = new ShaderTagId("Subsurface Scattering Forward"); // 对应 Shader 里的暗号
            private readonly RTHandle[] _mrtArrays = new RTHandle[2];
            private RTHandle _subsurfaceDiffuseIrradianceRT; // 用来接 SV_Target1 的 RenderTexture

            public SubsurfaceScatteringForwardPass()
            {
                // 在不透明物体画完之后、天空盒之前，渲染我们的 SSS 物体
                this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
				//  相机描述配置，颜色用ARGB
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.colorFormat = RenderTextureFormat.ARGB32;
                desc.depthBufferBits = 0;

                // 申请一张屏幕大小的 RT (给后续 SSS blur 消费)
                RenderingUtils.ReAllocateIfNeeded(ref _subsurfaceDiffuseIrradianceRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SkinDiffuseRT");
                
                // RTHandle : 内置了 Render Texture 的一个 Texture 管理类
                // colorTarget : 相机的 color Texture。depthTarget : 相机的 depth Texture
                RTHandle colorTargetHandle = renderingData.cameraData.renderer.cameraColorTargetHandle;
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;

                // 绑定 MRT: Target0 = 颜色色, Target1 = SkinDiffuseRT,
                _mrtArrays[0] = colorTargetHandle;
                _mrtArrays[1] = _subsurfaceDiffuseIrradianceRT;
                ConfigureTarget(_mrtArrays, depthTargetHandle);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawingSettings = CreateDrawingSettings(_shaderTagId, ref renderingData, sortingCriteria); // 只画带有 _shaderTagId 的 LightMode 的材质
                FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque);

                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);

                // CommandBuffer 相当于给 GPU 的命令清单。 取一个名字方便在 Debugger 里查看
                CommandBuffer cmd = CommandBufferPool.Get("SSS Forward Pass");
                cmd.SetGlobalTexture(_skinDiffuseRT, _subsurfaceDiffuseIrradianceRT);

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            
            public void Dispose()
            {
                _subsurfaceDiffuseIrradianceRT?.Release();
            }
        }

        class SubsurfaceScatteringMonteCarloPass : ScriptableRenderPass
        {
            private readonly int _subsurfaceScatteringDistanceParamsId = Shader.PropertyToID("_SubsurfaceScatteringDistance");
            private readonly int _surfaceScaleParamsId= Shader.PropertyToID("_SurfaceScale");
            private readonly Material _subsurfaceMonteCarloMaterial;
            private readonly Color _subsurfaceScatteringDistance;     // RGB 光在次表面内部能穿透的距离
            private readonly float _surfaceScale;                               // Unity 标准单位是 1m, 散射的单位是 mm, 需要根据模型的大小来调整散射的距离

            public SubsurfaceScatteringMonteCarloPass(Material subsurfaceMonteCarloMaterial, Color surfaceScatteringDistance, float surfaceScale)
            {
                _subsurfaceMonteCarloMaterial = subsurfaceMonteCarloMaterial;
                _subsurfaceScatteringDistance = surfaceScatteringDistance;
                _surfaceScale = surfaceScale;
                
                
                // 它必须紧跟着 ForwardPass 之后执行！
                this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 1;
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 拿到相机 color + depth (depth 里带 stencil, shader 里的 Stencil{Ref 1 Comp Equal} 需要它)
                RTHandle colorTargetHandle = renderingData.cameraData.renderer.cameraColorTargetHandle;
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;

                ConfigureTarget(colorTargetHandle, depthTargetHandle);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (_subsurfaceMonteCarloMaterial == null) return;

                CommandBuffer cmd = CommandBufferPool.Get("SSS MonteCarlo");

                // 给 Monte Carlo Shader传参
                // Burley Diffusion Profile 里的散射距离参数 s
                Vector3 s = new Vector3(
                    1.0f / Math.Max(_subsurfaceScatteringDistance.r * 255.0f, float.MinValue),
                    1.0f / Math.Max(_subsurfaceScatteringDistance.g * 255.0f, float.MinValue),
                    1.0f / Math.Max(_subsurfaceScatteringDistance.b * 255.0f, float.MinValue)
                );
                Debug.Log(_subsurfaceScatteringDistance.r);
                float rcpMaxScatteringDistance = Mathf.Min(s.x, Mathf.Min(s.x, s.y));
                Vector4 rcpSubsurfaceScatteringDistanceParams = new Vector4(s.x, s.y, s.z, rcpMaxScatteringDistance);
                
                cmd.SetGlobalVector(_subsurfaceScatteringDistanceParamsId, rcpSubsurfaceScatteringDistanceParams);
                cmd.SetGlobalFloat(_surfaceScaleParamsId, _surfaceScale);
                
                // 全屏面片, blur 材质自己内部有 Blend One One 保留原画面高光
                CoreUtils.DrawFullScreen(cmd, _subsurfaceMonteCarloMaterial);
                
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }
        
        [SerializeField] private Shader subsurfaceScatteringMonteCarloShader;  
        [ColorUsage(false, true)]
        [SerializeField] private Color subsurfaceScatteringDistance = new Color(15.0f, 5.0f, 2.0f, 1.0f);
        [SerializeField] private float surfaceScale = 1.0f;  // 模型的缩放大小，用于巨人和正常人
        private Material _subsurfaceScatteringMonteCarloMaterial;
        
        SubsurfaceScatteringForwardPass _subsurfaceScatteringForwardPass;
        SubsurfaceScatteringMonteCarloPass _subsurfaceScatteringMonteCarloPass;

        // Feature 初始化时调用
        public override void Create()
        {
            if (subsurfaceScatteringMonteCarloShader == null) return;
            _subsurfaceScatteringMonteCarloMaterial = new Material(subsurfaceScatteringMonteCarloShader);
            
            _subsurfaceScatteringForwardPass = new SubsurfaceScatteringForwardPass();
            _subsurfaceScatteringMonteCarloPass = new SubsurfaceScatteringMonteCarloPass(_subsurfaceScatteringMonteCarloMaterial, subsurfaceScatteringDistance, surfaceScale);
        }

        // 每一帧决定是否把 Pass 注入到管线中
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_subsurfaceScatteringForwardPass);
            if (_subsurfaceScatteringMonteCarloMaterial != null)
                renderer.EnqueuePass(_subsurfaceScatteringMonteCarloPass);
        }

        protected override void Dispose(bool disposing)
        {
            _subsurfaceScatteringForwardPass?.Dispose();
        }
    }
}