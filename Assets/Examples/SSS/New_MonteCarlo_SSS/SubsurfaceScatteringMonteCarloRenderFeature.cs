using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Examples.SSS.New_MonteCarlo_SSS
{
    // 这个类将渲染分成了 3 个 Pass
    public class SubsurfaceScatteringMonteCarloRenderFeature : ScriptableRendererFeature
    {
        private class SubsurfaceScatteringMonteCarloPass : ScriptableRenderPass
        {
            private readonly SubsurfaceScatteringMonteCarloRenderFeature _sssMonteCarloRenderFeature;
            private readonly ShaderTagId _sssScatteringDiffuse = new ShaderTagId("Subsurface Scattering Direct Diffuse");
            private readonly ShaderTagId _sssFinalBlendId = new ShaderTagId("Subsurface Scattering Final Blend");
            private readonly int _subsurfaceDirectDiffuseRT = Shader.PropertyToID("_SubsurfaceDirectDiffuseRT");
            private readonly int _rcpSubsurfaceScatteringDistanceParamsId = Shader.PropertyToID("_RcpSubsurfaceScatteringDistance");
            private readonly int _surfaceScale = Shader.PropertyToID("_SurfaceScale");
            private readonly int _subsurfaceScatteringRT = Shader.PropertyToID("_SubsurfaceScatteringRT");

            private RTHandle _sssDirectDiffuseRT;   // Pass 1 输出的直接光的 diffuse RT， 交给 SSS Pass 生成 SSS RT
            private RTHandle _sssRT;                    // Pass 2 SSS 层 输出的 RT
            
            public SubsurfaceScatteringMonteCarloPass(SubsurfaceScatteringMonteCarloRenderFeature sssMonteCarloRenderFeature)
            {
                this._sssMonteCarloRenderFeature = sssMonteCarloRenderFeature;
                this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            }
            
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 获取相机的配置
                RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.colorFormat = RenderTextureFormat.ARGB32;  //颜色用普通的 srgb
                descriptor.depthBufferBits = 0;  //???、
                
                RenderingUtils.ReAllocateIfNeeded(ref _sssDirectDiffuseRT, descriptor, FilterMode.Bilinear,TextureWrapMode.Clamp, name: "Subsurface Scattering Direct Diffuse RT");
                RenderingUtils.ReAllocateIfNeeded(ref _sssRT, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "Subsurface Scattering RT");
            }

            // ==================================
            // Pass 1 :Direct Diffuse 只输出 直接光的 diffuse 到 _sssDirectDiffuseRT
            // ==================================
            private void ExecuteDirectDiffusePass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData, ref FilteringSettings filteringSettings)
            {
                // 按默认的渲染顺序，只给 opaque 的物体执行
                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings sssDirectDiffuseDrawSettings = CreateDrawingSettings(_sssScatteringDiffuse, ref renderingData, sortingCriteria);
                
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                cmd.SetRenderTarget(_sssDirectDiffuseRT, depthTargetHandle);
                cmd.ClearRenderTarget(false, true, Color.black);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                context.DrawRenderers(renderingData.cullResults, ref sssDirectDiffuseDrawSettings, ref filteringSettings);
            }

            // ==================================
            // Pass 2 :MonteCarlo SSS 只输出 SSS
            // ==================================
            private void ExecuteMonteCarloSubSurfaceScatteringPass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData, ref FilteringSettings filteringSettings)
            {
                cmd.SetGlobalTexture(_subsurfaceDirectDiffuseRT, _sssDirectDiffuseRT); // 把 Pass 1 画好的交给 MonteCarlo Pass 2
                
                Color sssDistance = _sssMonteCarloRenderFeature.sssDistance;
                // 各通道的 平均自由程 d 的倒数 s
                float rcpSubsurfaceScatteringDistanceR = 1.0f / Mathf.Max(sssDistance.r * 255.0f, 0.0001f);
                float rcpSubsurfaceScatteringDistanceG = 1.0f / Mathf.Max(sssDistance.g * 255.0f, 0.0001f);
                float rcpSubsurfaceScatteringDistanceB = 1.0f / Mathf.Max(sssDistance.b * 255.0f, 0.0001f);
                // 传给 Shader 的参数, w 是自由程最长的那个光
                Vector4 rcpSubsurfaceScatteringDistanceParams = new Vector4(
                    rcpSubsurfaceScatteringDistanceR,
                    rcpSubsurfaceScatteringDistanceG,
                    rcpSubsurfaceScatteringDistanceB,
                    Mathf.Min(rcpSubsurfaceScatteringDistanceR, Mathf.Min(rcpSubsurfaceScatteringDistanceG, rcpSubsurfaceScatteringDistanceB))
                );
                cmd.SetGlobalVector(_rcpSubsurfaceScatteringDistanceParamsId, rcpSubsurfaceScatteringDistanceParams);
                cmd.SetGlobalFloat(_surfaceScale, _sssMonteCarloRenderFeature.surfaceScale);
                
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                cmd.SetRenderTarget(_sssRT, depthTargetHandle);
                cmd.ClearRenderTarget(false, true, Color.black);
                
                // 在屏幕空间绘制 Monte Carlo SSS
                CoreUtils.DrawFullScreen(cmd, _sssMonteCarloRenderFeature._sssMonteCarloCoreMaterial);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
            }

            // ==================================
            // Pass 3 :混合高光、环境光、SSS
            // ==================================
            private void ExecuteFinalBlendPass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData, ref FilteringSettings filteringSettings)
            {
                RTHandle colorTargetHandle = renderingData.cameraData.renderer.cameraColorTargetHandle;
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;

                cmd.SetGlobalTexture(_subsurfaceScatteringRT, _sssRT);
                cmd.SetRenderTarget(colorTargetHandle, depthTargetHandle);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                SortingCriteria sorting = renderingData.cameraData.defaultOpaqueSortFlags;  
                DrawingSettings finalBlendDrawSettings = CreateDrawingSettings(_sssFinalBlendId, ref renderingData, sorting);
                context.DrawRenderers(renderingData.cullResults, ref finalBlendDrawSettings, ref filteringSettings);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (_sssDirectDiffuseRT == null) return;
                
                CommandBuffer cmd = CommandBufferPool.Get("3 Pass SSS Feature");
                FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
                
                ExecuteDirectDiffusePass(ref context, ref cmd, ref renderingData, ref filteringSettings);
                ExecuteMonteCarloSubSurfaceScatteringPass(ref context, ref cmd, ref renderingData, ref filteringSettings);
                ExecuteFinalBlendPass(ref context, ref cmd, ref renderingData, ref filteringSettings);

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            
            public void Dispose()
            {
                _sssDirectDiffuseRT?.Release();
                _sssRT?.Release();
            }
        }
        
        [SerializeField] private Shader sssMonteCarloCoreShader;  
        [ColorUsage(false, true)]
        [SerializeField] private Color sssDistance = new Color(15.0f, 5.0f, 2.0f, 1.0f);
        [SerializeField] private float surfaceScale = 1.0f;  // 模型的缩放大小，用于巨人和正常人
        private Material _sssMonteCarloCoreMaterial;
        
        SubsurfaceScatteringMonteCarloPass _subsurfaceScatteringMonteCarloPass;

        // Feature 初始化时调用
        public override void Create()
        {
            if (sssMonteCarloCoreShader == null) return;
            // 在内存里创建核心的 SSS Material
            _sssMonteCarloCoreMaterial = new Material(sssMonteCarloCoreShader);
            // 创建 SSS 的 Render Pass
            _subsurfaceScatteringMonteCarloPass = new SubsurfaceScatteringMonteCarloPass(this);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_subsurfaceScatteringMonteCarloPass);
        }

        protected override void Dispose(bool disposing)
        {
            _subsurfaceScatteringMonteCarloPass?.Dispose();
        }
    }
}