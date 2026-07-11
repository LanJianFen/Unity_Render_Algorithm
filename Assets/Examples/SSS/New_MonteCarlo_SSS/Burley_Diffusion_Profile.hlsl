// u = cdf = 1 - 0.25 * exp(-sr) - 0.75 * exp(-sr / 3)
// v = 1 - u, x = -exp(-sr/3)
// v = 0.25 *x * x * x - 0.75 * x
// 一元三次方程，解出 x = intermediate - 1 / intermediate
// r = - 3 / r * ln x
// pdf = BurleyDiffusionProfile =  (s * x * x * x + x) / (8.0f * PI * r);
void SampleBurleyPDF(float u, float s, out float r, out float rcp_pdf)
{
    float v = 1.0f - u;
    float intermediate = pow(2.0f * v + sqrt(4.0f * v * v + 1.0f), 1.0f / 3.0f);
    float x = intermediate - 1.0f / intermediate;

    // 保护 x 不能为 0
    x = max(x, 1e-6);

    r = -log(x) * 3.0f / s;
    r = max(r, 1e-6);

    float pdf = s * (x * x * x + x) / (8.0f * PI * r);
    rcp_pdf = 1.0f / pdf;
}

void EvalSampleBurleyPDF(float u, float s, out float r, out float rcp_pdf)  
{            
    u = 1.0f - u;
    float rcp_s = 1.0f / s;
    float g = 1.0f + (4.0f * u) * (2.0f * u + sqrt(1.0f + (4.0f * u) * u));  
    float n = exp2(log2(g) * (- 1.0f / 3.0f));  
    float p = (g * n) * n;  
    float c = 1.0f + p + n;  
    float d = (3.0f / LOG2_E * 2.0f) + (3.0f / LOG2_E) * log2(u);  
    float x = (3.0f / LOG2_E) * log2(c) - d;  
    float rcpExp = ((c * c) * c) * rcp((4.0f * u) * ((c * c) + (4.0f * u) * (4.0f * u)));  
    r = x * rcp_s;  
    rcp_pdf = (8.0f * PI * rcp_s) * rcpExp;  
} 

//  s / ( 8 * PI * r) * (exp(-sr) + exp(-sr / 3))
float3 BurleyDiffusionProfile(float r, float3 s)
{
    return (exp(-s * r) + exp(-s * r / 3.0f)) * s / (8.0f * PI * r);
}

// 保护和优化版 BurleyDiffusionProfile
float3 EvalBurleyDiffusionProfile(float r, float3 s)
{
    float3 exp_13 = exp2(((LOG2_E * (-1.0f / 3.0f)) * r) * s);
    float3 expSum = exp_13 * (1.0f + exp_13 * exp_13);
    return (s * rcp(8.0f * PI)) * expSum;
}

// 黄金螺旋（Vogel's Spiral / 低差异序列）:这是图形学里大名鼎鼎的二维均匀撒点算法。
// 我们用的时候只要角度，第二个返回值
float2 SampleDiskGolden1(uint i, uint sampleCount)
{
    float2 f = Golden2dSeq(i, sampleCount);
    return float2(sqrt(f.x), TWO_PI * f.y);
}
