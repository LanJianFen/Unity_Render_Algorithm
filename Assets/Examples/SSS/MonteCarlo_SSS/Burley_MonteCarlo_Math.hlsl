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

    r = - log(x) * 3.0f / s;
    r = max(r, 1e-6);

    float pdf = s * (x * x * x + x) / (8.0f * PI * r);
    rcp_pdf = 1.0f / pdf;
}

//  s / ( 8 * PI * r) * exp(-sr) + exp(-sr / 3)
float3 BurleyDiffusionProfile(float r, float3 s)
{
    return exp(- s * r) + exp(- s * r / 3.0f) * s / (8.0f * PI * r);
}

// 黄金螺旋（Vogel's Spiral / 低差异序列）:这是图形学里大名鼎鼎的二维均匀撒点算法。
// 我们用的时候只要角度，第二个返回值
float2 SampleDiskGolden1(uint i, uint sampleCount)  
{  
    float2 f = Golden2dSeq(i, sampleCount);  
    return float2(sqrt(f.x), TWO_PI * f.y);  
}