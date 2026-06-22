half hash21(half2 p)
{
    half3 p3 = frac(half3(p.xyx) * 0.1031h);
    p3 += dot(p3, p3.yzx + 33.33h);
    return frac((p3.x + p3.y) * p3.z);
}

// 2D Value Noise 噪声
half noise2D(half2 p)
{
    half2 i = floor(p); // 获取当前所在方格的左下角整数坐标
    half2 f = frac(p); // 获取当前所在方格的小数坐标
    // 这个平滑插值在 0 和 1 处的导数都是 0，让颜色在不同格子直接平滑过渡
    f = f * f * (3.0h - 2.0h * f);
    // 取出正方形 4 个角的随机值
    half a = hash21(i + half2(0.0h, 0.0h)); // 左下
    half b = hash21(i + half2(1.0h, 0.0h)); // 右下
    half c = hash21(i + half2(0.0h, 1.0h)); // 左上
    half d = hash21(i + half2(1.0h, 1.0h)); // 右上
    // 横向和纵向双线性插值, 这个插值让格子的交界处值是一样的
    // 交界处值相同，导数平滑，过渡就自然
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

// 2D 分形布朗运动
half fBm2D(half2 p)
{
    half value = 0.0h;
    half amplitude = 0.5h;
    // 叠加 3 层噪声
    // 第 1 层 增加 [0, 0.5] 的值
    // 第 2 层 增加 [0, 0.25]
    // 第 3 层 增加 [0, 0.125]
    for (int i = 0; i < 3; i++)
    {
        value += noise2D(p) * amplitude;
        p *= 2.0h;
        amplitude *= 0.5h;
    }
    return value;
}

half hash31(half3 p3)
{
    p3 = frac(p3 * 0.1031h);
    p3 += dot(p3, p3.yzx + 33.33h);
    return frac((p3.x + p3.y) * p3.z);
}

// 3D Value Noise 噪声
half noise3D(half3 p)
{
    half3 i = floor(p);
    half3 f = frac(p);
    f = f * f * (3.0h - 2.0h * f);
    half a = hash31(i + half3(0.0h, 0.0h, 0.0h));
    half b = hash31(i + half3(1.0h, 0.0h, 0.0h));
    half c = hash31(i + half3(0.0h, 1.0h, 0.0h));
    half d = hash31(i + half3(1.0h, 1.0h, 0.0h));
    half e = hash31(i + half3(0.0h, 0.0h, 1.0h));
    half s = hash31(i + half3(1.0h, 0.0h, 1.0h));
    half t = hash31(i + half3(0.0h, 1.0h, 1.0h));
    half u = hash31(i + half3(1.0h, 1.0h, 1.0h));
    return lerp(lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y), lerp(lerp(e, s, f.x), lerp(t, u, f.x), f.y), f.z);
}

// 3D 分形布朗运动
half fbm3D(half3 p)
{
    half value = 0.0h;
    half amplitude = 0.5h;
    for (int i = 0; i < 3; i++)
    {
        value += noise3D(p) * amplitude;
        p *= 2.0h;
        amplitude *= 0.5h;
    }
    return value;
}