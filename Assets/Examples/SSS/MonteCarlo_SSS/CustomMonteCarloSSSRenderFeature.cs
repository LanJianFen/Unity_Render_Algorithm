using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class CustomMonteCarloSSSRenderFeature : ScriptableRendererFeature
{
    public Material sssMonteCarloMaterial;

    private class SSSForwardPass : ScriptableRenderPass
    {
        private ShaderTagId m_ShaderTagId = new ShaderTagId("SSS_MRT"); // 对应 Shader 里的暗号
        private RTHandle m_SkinDiffuseRT; // 用来接 SV_Target1 的 RenderTexture

        private RTHandle[] m_MRTBindings = new RTHandle[2];

        // MRT 重载 (无论 CommandBuffer 还是 CoreUtils) 都只接受 RenderTargetIdentifier[],
        // 靠 RTHandle→RenderTargetIdentifier 的隐式转换填充
        private RenderTargetIdentifier[] m_MRTIds = new RenderTargetIdentifier[2];

        public SSSForwardPass()
        {
            // 在不透明物体画完之后、天空盒之前，渲染我们的 SSS 物体
            this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        }

        // 1. 只申请 RT (原来在这里 ConfigureTarget+ConfigureClear 会把相机色缓冲一起清成黑)
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGB32;
            desc.depthBufferBits = 0;

            // 申请一张屏幕大小的 RT (给后续 SSS blur 消费)
            RenderingUtils.ReAllocateIfNeeded(ref m_SkinDiffuseRT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp,
                name: "_SkinDiffuseRT");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("SSS Forward Pass");

            RTHandle cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            RTHandle cameraDepthTarget = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            // === FIX: 只清 SkinDiffuseRT, 不动 camera color ===
            //   相机色此时已经画好了非 SSS 的所有 opaque 物体, 不能被清掉否则背景全黑
            //   用 CoreUtils.SetRenderTarget 保持 RTHandle 生态一致 (CommandBuffer.SetRenderTarget 不接受 RTHandle[])
            CoreUtils.SetRenderTarget(cmd, m_SkinDiffuseRT, ClearFlag.Color, Color.clear);
            // === END FIX ===

            // 绑定 MRT: Target0=相机色, Target1=SkinDiffuseRT, 深度用相机深度
            m_MRTBindings[0] = cameraColorTarget;
            m_MRTBindings[1] = m_SkinDiffuseRT;
            m_MRTIds[0] = cameraColorTarget; // RTHandle → RenderTargetIdentifier 隐式转换
            m_MRTIds[1] = m_SkinDiffuseRT;
            CoreUtils.SetRenderTarget(cmd, m_MRTIds, cameraDepthTarget);

            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            // 按前后顺序画不透明物体 (Early-Z)
            SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
            DrawingSettings drawingSettings = CreateDrawingSettings(m_ShaderTagId, ref renderingData, sortingCriteria);
            drawingSettings.perObjectData = PerObjectData.Lightmaps | PerObjectData.LightProbe |
                                            PerObjectData.LightProbeProxyVolume;
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.opaque);

            // 只画带 "SSSMRT" tag 的物体, 输出到 MRT
            context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);

            // FIX: 立刻设为全局贴图, 下一个 pass (SSSMonteCarlo) 就能读了
            // 原来放在 OnCameraCleanup 里, 那是所有 pass 都跑完之后才调用, 太晚了
            cmd.SetGlobalTexture("_SkinDiffuseRT", m_SkinDiffuseRT);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        // 3. Cleanup (不再在这里 SetGlobalTexture, 时机太晚)
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            // RTHandle 交由系统管理, 这里不用手动释放
        }

        public void Dispose()
        {
            m_SkinDiffuseRT?.Release();
        }
    }

    class SSSMonteCarloPass : ScriptableRenderPass
    {
        private Material m_BlurMaterial;

        public SSSMonteCarloPass(Material blurMat)
        {
            m_BlurMaterial = blurMat;
            // 它必须紧跟着 ForwardPass 之后执行！
            this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 1;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_BlurMaterial == null) return;

            CommandBuffer cmd = CommandBufferPool.Get("SSS_MonteCarlo");

            // 拿到相机 color + depth (depth 里带 stencil, shader 里的 Stencil{Ref 1 Comp Equal} 需要它)
            RTHandle cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            RTHandle cameraDepthTarget = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            // FIX: 必须绑 depth+stencil, 不然 shader 里 stencil 测试拿不到 buffer → 全屏不画或行为未定义
            CoreUtils.SetRenderTarget(cmd, cameraColorTarget, cameraDepthTarget);

            // 全屏面片, blur 材质自己内部有 Blend One One 保留原画面高光
            cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, m_BlurMaterial, 0, 0);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }

    SSSForwardPass m_ScriptablePass;
    SSSMonteCarloPass m_MonteCarloPass;

    // Feature 初始化时调用
    public override void Create()
    {
        m_ScriptablePass = new SSSForwardPass();
        m_MonteCarloPass = new SSSMonteCarloPass(sssMonteCarloMaterial);
    }

    // 每一帧决定是否把 Pass 注入到管线中
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 如果不是在画相机画面（比如在画阴影贴图），就不执行
        if (renderingData.cameraData.cameraType == CameraType.Preview) return;

        renderer.EnqueuePass(m_ScriptablePass);
        if (sssMonteCarloMaterial != null)
        {
            renderer.EnqueuePass(m_MonteCarloPass);
        }
    }

    protected override void Dispose(bool disposing)
    {
        m_ScriptablePass?.Dispose();
    }
}