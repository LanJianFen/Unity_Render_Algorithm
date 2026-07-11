
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
public static class QualityParams {
    public static float fSkinTextureRate = 1.0f; // 渲染分辨率倍率
    public static float fSkinSSSReductRate = 0.7f; // SSS降采样倍率，建议0.5
    public static bool bEnableSkinSSS = true; // SSS总开关
}

public class QshengSkinRenderFeature : ScriptableRendererFeature
{
    public Material sssMat;

    [ColorUsage(false, true)]
    public Color scatteringDistance = Color.black;
    [ColorUsage(false, true)]
    public Color transmissionTint = Color.black;
    // public Vector2 thicknessRemap = new Vector2(1f,5f); 
    public float worldScale = 1f;
    public float ior = 1.4f;                        // 1.4 for skin (mean ~0.028)
                                                    // public LayerMask skinLayer = 0;

    class SkinRenderPass : ScriptableRenderPass
    {

        public SkinRenderPass(QshengSkinRenderFeature f)
        {
            this.feature = f;
        }

        QshengSkinRenderFeature feature;
        int sssWidth, sssHeight;
        int Width, Height;
        int[] diffuseRT;
        const string m_ProfilerTag = "Skin Diffuse";

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            // 设置纹理的高度和宽度
            Width = (int)(cameraTextureDescriptor.width * QualityParams.fSkinTextureRate);
            Height = (int)(cameraTextureDescriptor.height * QualityParams.fSkinTextureRate);
            sssWidth = (int)(cameraTextureDescriptor.width * QualityParams.fSkinSSSReductRate);
            sssHeight = (int)(cameraTextureDescriptor.height * QualityParams.fSkinSSSReductRate);

            if (diffuseRT == null)
            {
                diffuseRT = new int[3];
                diffuseRT[0] = Shader.PropertyToID("_SkinDiffuse");     // 漫反射
                diffuseRT[1] = Shader.PropertyToID("_SkinSSS");         // SSS
                diffuseRT[2] = Shader.PropertyToID("_SkinDepth");       // 深度值
            }
            // 创建纹理
            cmd.GetTemporaryRT(diffuseRT[0], Width, Height, 0, FilterMode.Bilinear, RenderTextureFormat.ARGB32);
            cmd.GetTemporaryRT(diffuseRT[2], Width, Height, 16, FilterMode.Point, RenderTextureFormat.Depth);
            if (QualityParams.bEnableSkinSSS)
                cmd.GetTemporaryRT(diffuseRT[1], sssWidth, sssHeight, 0, FilterMode.Bilinear, RenderTextureFormat.ARGB32);
        }

        static readonly ShaderTagId SkinDiffuseShaderTagId = new ShaderTagId("SkinDiffuse");
        // 启用所有渲染队列
        FilteringSettings m_FilteringSettings = new FilteringSettings(RenderQueueRange.all);

        static float SampleBurleyDiffusionProfile(float u, float rcpS)
        {
            u = 1 - u;// Convert CDF to CCDF

            float g = 1 + (4 * u) * (2 * u + Mathf.Sqrt(1 + (4 * u) * u));
            float n = Mathf.Pow(g, -1f / 3f);
            float p = (g * n) * n;
            float c = 1 + p + n;
            float x = 3 * Mathf.Log(c / (4 * u));
            return x * rcpS;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var camera = renderingData.cameraData.camera;
            // 获取新的缓冲区
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);

            var projectMatrix = renderingData.cameraData.camera.projectionMatrix;
            var invProject = projectMatrix.inverse;
            cmd.SetGlobalMatrix("_InvProjectMatrix", invProject);
            cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(), renderingData.cameraData.GetProjectionMatrix());
            cmd.SetViewport(new Rect(0f, 0f, sssWidth, sssHeight));

            //设置漫反射RT和深度值RT
            cmd.SetRenderTarget(new RenderTargetIdentifier(diffuseRT[0]), new RenderTargetIdentifier(diffuseRT[2]));
            cmd.ClearRenderTarget(true, true, RenderSettings.ambientLight * 0.3f);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            //绘制漫反射Pass
            var diffuseSetting = CreateDrawingSettings(SkinDiffuseShaderTagId, ref renderingData, SortingCriteria.None);
            context.DrawRenderers(renderingData.cullResults, ref diffuseSetting, ref m_FilteringSettings);

            if (QualityParams.bEnableSkinSSS)
            {
                // RGB散射距离
                Color scatteringDistance = feature.scatteringDistance;
                Vector3 shapeParam = new Vector3(Mathf.Min(16777216, 1.0f / scatteringDistance.r),
                    Mathf.Min(16777216, 1.0f / scatteringDistance.g),
                    Mathf.Min(16777216, 1.0f / scatteringDistance.b));

                // 计算出最大的散射范围
                float maxScatteringDistance = Mathf.Max(scatteringDistance.r, scatteringDistance.g, scatteringDistance.b);
                float cdf = 0.997f;
                float filterRadius = SampleBurleyDiffusionProfile(cdf, maxScatteringDistance);

                //透射部分的参数
                float fresnel0 = (feature.ior - 1.0f) / (feature.ior + 1.0f);
                fresnel0 *= fresnel0; // square
                Vector4 transmissionTintAndFresnel0 = new Vector4(feature.transmissionTint.r * 0.25f, feature.transmissionTint.g * 0.25f, feature.transmissionTint.b * 0.25f,
                    fresnel0);
                cmd.SetGlobalVector("_TransmissionTintAndFresnel0", transmissionTintAndFresnel0);
                //次表面散射参数
                cmd.SetGlobalFloat("_FilterRadii", filterRadius);
                cmd.SetGlobalVector("_ShapeParamsAndMaxScatterDists", new Vector4(shapeParam.x, shapeParam.y, shapeParam.z, maxScatteringDistance));
                cmd.SetGlobalFloat("_WorldScale", feature.worldScale);
                //设置次表面散射RT
                cmd.SetRenderTarget(new RenderTargetIdentifier(diffuseRT[1]));
                cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
                var sceenMatrix = Matrix4x4.identity;

                //Camera-relative rendering
                //if (ShaderOptions.k_ShaderoptionsCameraRelativeRendering != 0)
                //{
                //    var camPos = renderingData.cameraData.worldSpaceCameraPos;
                //    sceenMatrix.SetColumn(3, new Vector4(camPos.x, camPos.y, camPos.z, 1));
                //}

                //计算次表面散射
                cmd.DrawMesh(RenderingUtils.fullscreenMesh, sceenMatrix, feature.sssMat, 0, 0);
                cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(), renderingData.cameraData.GetProjectionMatrix());
                context.ExecuteCommandBuffer(cmd);
            }

            CommandBufferPool.Release(cmd);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void FrameCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(diffuseRT[0]);
            cmd.ReleaseTemporaryRT(diffuseRT[1]);
            cmd.ReleaseTemporaryRT(diffuseRT[2]);
        }
    }

    SkinRenderPass m_ScriptablePass;

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }

    public override void Create()
    {
        m_ScriptablePass = new SkinRenderPass(this);
        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingShadows + 1;
    }
}
